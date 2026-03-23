import SwiftUI
import Photos
import CoreLocation

// MARK: - Persisted description data

struct PhotoDescription: Codable {
    let assetId: String
    let description: String
}

// MARK: - Tags ViewModel (Llama 4 Scout indexing + semantic search)

@MainActor
class TagsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning(Double)
        case ready
    }

    @Published var state: State = .idle
    @Published var scannedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var recentDescriptions: [(String, UIImage?)] = []

    private var descriptionIndex: [String: String] = [:]

    // MARK: - Persistence (Keychain)

    private let keychainService = "com.fotify.descriptions"
    private let keychainAccount = "photo_descriptions"
    private let currentSchemaVersion = 2

    func loadPersistedTags() {
        let savedVersion = UserDefaults.standard.integer(forKey: "fotify_schema_version")
        if savedVersion < currentSchemaVersion {
            keychainWrite(Data())
            UserDefaults.standard.set(currentSchemaVersion, forKey: "fotify_schema_version")
            return
        }

        guard let data = keychainRead(),
              let entries = try? JSONDecoder().decode([PhotoDescription].self, from: data) else {
            return
        }
        for entry in entries {
            descriptionIndex[entry.assetId] = entry.description
        }
        scannedCount = descriptionIndex.count
        if scannedCount > 0 {
            state = .ready
        }
    }

    private func persistDescriptions() {
        let entries = descriptionIndex.map { PhotoDescription(assetId: $0.key, description: $0.value) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        keychainWrite(data)
    }

    private func keychainWrite(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func keychainRead() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
            return result as? Data
        }
        return nil
    }

    // MARK: - Background Scan with Llama 4 Scout

    func backgroundScan(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        totalCount = allPhotos.count
        let batchSize = 20

        var toScan: [PHAsset] = []
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            if descriptionIndex[asset.localIdentifier] == nil {
                toScan.append(asset)
            }
        }

        if toScan.isEmpty {
            state = .ready
            return
        }

        let quickScanLimit = Config.quickScanLimit
        let needsQuickPhase = scannedCount < quickScanLimit

        state = .scanning(min(1.0, Double(scannedCount) / Double(totalCount)))

        // Shared date formatter (created once)
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "es_AR")
        dateFmt.dateFormat = "d MMMM yyyy"

        var batchesSinceLastPersist = 0

        for batchStart in stride(from: 0, to: toScan.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, toScan.count)
            let batch = Array(toScan[batchStart..<batchEnd])

            await withTaskGroup(of: (String, String?, UIImage?).self) { group in
                for asset in batch {
                    let dateStr = asset.creationDate.map { dateFmt.string(from: $0) }
                    let lat = asset.location?.coordinate.latitude
                    let lng = asset.location?.coordinate.longitude

                    group.addTask {
                        guard let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 150, height: 150)),
                              let jpegData = image.jpegData(compressionQuality: 0.3) else {
                            return (asset.localIdentifier, nil, nil)
                        }

                        let base64 = jpegData.base64EncodedString()
                        var aiDesc = await self.describeWithLlama(base64Image: base64) ?? ""

                        var meta: [String] = []
                        if let d = dateStr { meta.append("Fecha: \(d)") }
                        if let la = lat, let ln = lng {
                            meta.append("GPS: \(String(format: "%.4f", la)),\(String(format: "%.4f", ln))")
                        }
                        if !meta.isEmpty {
                            aiDesc += ". " + meta.joined(separator: ". ")
                        }

                        return (asset.localIdentifier, aiDesc.isEmpty ? nil : aiDesc, image)
                    }
                }

                for await (assetId, description, thumb) in group {
                    if let desc = description {
                        descriptionIndex[assetId] = desc
                        scannedCount += 1
                        if recentDescriptions.count < 10 {
                            recentDescriptions.insert((desc, thumb), at: 0)
                        } else {
                            recentDescriptions[recentDescriptions.count - 1] = (desc, thumb)
                            recentDescriptions.insert(recentDescriptions.removeLast(), at: 0)
                        }
                        if recentDescriptions.count > 10 {
                            recentDescriptions.removeLast()
                        }
                    }
                }
            }

            // After quick phase, mark as ready
            if needsQuickPhase && scannedCount >= quickScanLimit && state != .ready {
                state = .ready
                persistDescriptions()
            }

            if state != .ready {
                state = .scanning(min(1.0, Double(scannedCount) / Double(totalCount)))
            }

            // Persist every 5 batches (~100 photos)
            batchesSinceLastPersist += 1
            if batchesSinceLastPersist >= 5 {
                persistDescriptions()
                batchesSinceLastPersist = 0
            }
        }

        persistDescriptions()
        state = .ready
    }

    // MARK: - Llama 4 Scout API

    private var retryCount = 0

    private func describeWithLlama(base64Image: String) async -> String? {
        let requestBody: [String: Any] = [
            "model": Config.groqVisionModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Describí esta foto en una línea corta en español. Incluí: personas visibles, lugar o ubicación si se reconoce, objetos principales, tipo de escena, momento del día. Solo la descripción, nada más."],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 120,
            "temperature": 0.3
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Rate limiting — wait and retry (max 3 times)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                retryCount += 1
                if retryCount > 3 {
                    retryCount = 0
                    return nil
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let result = await describeWithLlama(base64Image: base64Image)
                retryCount = 0
                return result
            }

            retryCount = 0

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return nil
        }

        return nil
    }

    // MARK: - Search

    func search(tags searchTags: [String], photoLibrary: PhotoLibraryService) -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        let lowered = searchTags.map { $0.lowercased() }
        var results: [PHAsset] = []

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let description = descriptionIndex[asset.localIdentifier] else { continue }

            let descLower = description.lowercased()
            if lowered.contains(where: { descLower.contains($0) }) {
                results.append(asset)
                if results.count >= 200 { break }
            }
        }

        return results
    }

    /// Search by location: geocode once, find nearby GPS photos
    func searchByLocation(place: String, photoLibrary: PhotoLibraryService) async -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        let targetLocation: CLLocation? = await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(place) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.location)
            }
        }

        guard let target = targetLocation else { return [] }

        var results: [PHAsset] = []
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let assetLoc = asset.location else { continue }
            if assetLoc.distance(from: target) < 5000 {
                results.append(asset)
                if results.count >= 200 { break }
            }
        }

        return results
    }

    /// Get photos matching a category (documents or landscapes)
    func photosForCategory(_ category: PhotoCategory, photoLibrary: PhotoLibraryService) -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        let keywords: [String]
        switch category {
        case .documents:
            keywords = ["documento", "papel", "texto", "libro", "recibo", "carta", "nota", "pantalla", "captura"]
        case .landscapes:
            keywords = ["paisaje", "montaña", "playa", "lago", "río", "campo", "bosque", "atardecer", "amanecer", "cielo", "naturaleza", "mar"]
        default:
            return []
        }

        var results: [PHAsset] = []
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let description = descriptionIndex[asset.localIdentifier] else { continue }

            let descLower = description.lowercased()
            if keywords.contains(where: { descLower.contains($0) }) {
                results.append(asset)
                if results.count >= 300 { break }
            }
        }

        return results
    }

    /// Get photos with people (from AI descriptions)
    func photosForPeople(photoLibrary: PhotoLibraryService) -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }
        let keywords = ["persona", "hombre", "mujer", "niño", "niña", "gente", "grupo", "retrato", "rostro", "cara"]

        var results: [PHAsset] = []
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let description = descriptionIndex[asset.localIdentifier] else { continue }

            let descLower = description.lowercased()
            if keywords.contains(where: { descLower.contains($0) }) {
                results.append(asset)
                if results.count >= 300 { break }
            }
        }
        return results
    }

    var availableTags: [String] {
        Array(descriptionIndex.values.prefix(50))
    }
}
