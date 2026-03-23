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
    @Published var recentDescriptions: [(String, UIImage?)] = [] // last descriptions with thumbnails

    /// In-memory index: assetId → description
    private var descriptionIndex: [String: String] = [:]

    // MARK: - Persistence

    private let keychainService = "com.fotify.descriptions"
    private let keychainAccount = "photo_descriptions"

    func loadPersistedTags() {
        guard let data = keychainRead() ,
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
        if let data = try? JSONEncoder().encode(entries) {
            keychainWrite(data)
        }
    }

    // MARK: - Keychain (survives app reinstall)

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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }

    // MARK: - Background Scan with Llama 4 Scout

    func backgroundScan(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        totalCount = allPhotos.count
        let batchSize = 10

        // Find photos that still need scanning
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

        // Phase 1: quick scan first batch, then mark as ready
        let quickScanLimit = Config.quickScanLimit
        let alreadyScanned = scannedCount
        let needsQuickPhase = alreadyScanned < quickScanLimit && toScan.count > 0

        state = .scanning(Double(scannedCount) / Double(min(totalCount, quickScanLimit)))

        // Process in batches
        for batchStart in stride(from: 0, to: toScan.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, toScan.count)
            let batch = Array(toScan[batchStart..<batchEnd])

            await withTaskGroup(of: (String, String?, UIImage?).self) { group in
                for asset in batch {
                    group.addTask {
                        guard let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 200, height: 200)),
                              let jpegData = image.jpegData(compressionQuality: 0.5) else {
                            return (asset.localIdentifier, nil, nil)
                        }

                        let base64 = jpegData.base64EncodedString()
                        var aiDesc = await self.describeWithLlama(base64Image: base64) ?? ""

                        // Append date + raw GPS (no geocoding, resolved at search time)
                        var meta: [String] = []
                        if let date = asset.creationDate {
                            let fmt = DateFormatter()
                            fmt.locale = Locale(identifier: "es_AR")
                            fmt.dateFormat = "d MMMM yyyy"
                            meta.append("Fecha: \(fmt.string(from: date))")
                        }
                        if let loc = asset.location {
                            meta.append("GPS: \(String(format: "%.4f", loc.coordinate.latitude)),\(String(format: "%.4f", loc.coordinate.longitude))")
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
                        scannedCount = descriptionIndex.count
                        recentDescriptions.insert((desc, thumb), at: 0)
                        if recentDescriptions.count > 10 {
                            recentDescriptions.removeLast()
                        }
                    }
                }
            }

            // After quick phase (500), mark as ready so user can search
            if needsQuickPhase && scannedCount >= quickScanLimit && state != .ready {
                state = .ready
                persistDescriptions()
            }

            // Update progress
            if state != .ready {
                state = .scanning(Double(scannedCount) / Double(min(totalCount, quickScanLimit)))
            }

            persistDescriptions()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        state = .ready
    }

    // MARK: - Llama 4 Scout API

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

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Handle rate limiting
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // wait 2s
                return await describeWithLlama(base64Image: base64Image)
            }

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
            let match = lowered.contains { searchTag in
                descLower.contains(searchTag)
            }

            if match {
                results.append(asset)
                if results.count >= 200 { break }
            }
        }

        return results
    }

    /// Search by location: geocode the place name once, then find photos with nearby GPS
    func searchByLocation(place: String, photoLibrary: PhotoLibraryService) async -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        // Geocode the search query to get coordinates
        let targetLocation: CLLocation? = await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(place) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.location)
            }
        }

        guard let target = targetLocation else { return [] }

        // Find photos within 5km of that location
        var results: [PHAsset] = []
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let assetLoc = asset.location else { continue }
            if assetLoc.distance(from: target) < 5000 { // 5km radius
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
            let match = keywords.contains { descLower.contains($0) }

            if match {
                results.append(asset)
                if results.count >= 300 { break }
            }
        }

        return results
    }

    /// Available tags for Groq context (now returns sample descriptions)
    var availableTags: [String] {
        return Array(descriptionIndex.values.prefix(50))
    }
}
