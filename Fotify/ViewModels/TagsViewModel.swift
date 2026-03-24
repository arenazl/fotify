import SwiftUI
import Photos
import CoreLocation

// MARK: - Indexed photo data

struct IndexedPhoto: Codable {
    let assetId: String
    let tags: [String]
    let date: String?
    let gps: String?
}

// MARK: - Tags ViewModel

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

    private var photoIndex: [String: IndexedPhoto] = [:]

    // MARK: - Persistence (Keychain)

    private let keychainService = "com.fotify.descriptions"
    private let keychainAccount = "photo_descriptions"
    private let currentSchemaVersion = 7 // force spanish tags // free tags

    func loadPersistedTags() {
        let savedVersion = UserDefaults.standard.integer(forKey: "fotify_schema_version")
        if savedVersion < currentSchemaVersion {
            keychainWrite(Data())
            UserDefaults.standard.set(currentSchemaVersion, forKey: "fotify_schema_version")
            return
        }

        guard let data = keychainRead(),
              let entries = try? JSONDecoder().decode([IndexedPhoto].self, from: data) else {
            return
        }
        for entry in entries {
            photoIndex[entry.assetId] = entry
        }
        scannedCount = photoIndex.count
        if scannedCount > 0 { state = .ready }
    }

    private func persistIndex() {
        let entries = Array(photoIndex.values)
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

    // MARK: - Background Scan

    func backgroundScan(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        totalCount = allPhotos.count
        let batchSize = 20

        var toScan: [PHAsset] = []
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            if photoIndex[asset.localIdentifier] == nil {
                toScan.append(asset)
            }
        }

        if toScan.isEmpty { state = .ready; return }

        let quickScanLimit = Config.quickScanLimit
        let needsQuickPhase = scannedCount < quickScanLimit

        state = .scanning(min(1.0, Double(scannedCount) / Double(totalCount)))

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "es_AR")
        dateFmt.dateFormat = "d MMMM yyyy"

        var batchesSinceLastPersist = 0

        for batchStart in stride(from: 0, to: toScan.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, toScan.count)
            let batch = Array(toScan[batchStart..<batchEnd])

            await withTaskGroup(of: (String, IndexedPhoto?, UIImage?).self) { group in
                for asset in batch {
                    let dateStr = asset.creationDate.map { dateFmt.string(from: $0) }
                    let lat = asset.location?.coordinate.latitude
                    let lng = asset.location?.coordinate.longitude
                    let gpsStr = (lat != nil && lng != nil) ? "\(String(format: "%.4f", lat!)),\(String(format: "%.4f", lng!))" : nil

                    group.addTask {
                        guard let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 150, height: 150)),
                              let jpegData = image.jpegData(compressionQuality: 0.3) else {
                            await DebugLogger.shared.log("INDEX", "ERROR: sin thumbnail")
                            return (asset.localIdentifier, nil, nil)
                        }

                        let base64 = jpegData.base64EncodedString()
                        let tags = await self.analyzeWithLlama(base64Image: base64)

                        if let tags = tags {
                            await DebugLogger.shared.log("INDEX", "OK: \(tags.prefix(5).joined(separator: ", "))")
                            if gpsStr != nil { await DebugLogger.shared.log("INDEX", "GPS: \(gpsStr!)") }

                            let indexed = IndexedPhoto(assetId: asset.localIdentifier, tags: tags, date: dateStr, gps: gpsStr)
                            return (asset.localIdentifier, indexed, image)
                        } else {
                            await DebugLogger.shared.log("INDEX", "ERROR: IA no respondió")
                            return (asset.localIdentifier, nil, nil)
                        }
                    }
                }

                for await (_, indexed, thumb) in group {
                    if let idx = indexed {
                        photoIndex[idx.assetId] = idx
                        scannedCount += 1
                        let desc = idx.tags.prefix(5).joined(separator: ", ")
                        if recentDescriptions.count >= 10 { recentDescriptions.removeLast() }
                        recentDescriptions.insert((desc, thumb), at: 0)
                    }
                }
            }

            if needsQuickPhase && scannedCount >= quickScanLimit && state != .ready {
                state = .ready
                persistIndex()
            }

            if state != .ready {
                state = .scanning(min(1.0, Double(scannedCount) / Double(totalCount)))
            }

            batchesSinceLastPersist += 1
            if batchesSinceLastPersist >= 5 {
                persistIndex()
                batchesSinceLastPersist = 0
            }
        }

        persistIndex()
        state = .ready
    }

    // MARK: - Llama 4 Scout (structured output)

    private var retryCount = 0

    private func analyzeWithLlama(base64Image: String) async -> [String]? {
        let requestBody: [String: Any] = [
            "model": Config.groqVisionModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Analizá esta foto y generá los 15 tags más importantes para poder encontrarla o agruparla en una búsqueda. Todos los tags en español. Solo respondé con un JSON: {\"tags\": [\"tag1\", ...]}"],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 400,
            "temperature": 0.1
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

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                retryCount += 1
                if retryCount > 3 { retryCount = 0; return nil }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let result = await analyzeWithLlama(base64Image: base64Image)
                retryCount = 0
                return result
            }
            retryCount = 0

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                // Parse tags JSON
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsonStart = cleaned.firstIndex(of: "{"),
                   let jsonEnd = cleaned.lastIndex(of: "}") {
                    let jsonStr = String(cleaned[jsonStart...jsonEnd])
                    if let jsonData = jsonStr.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let tags = parsed["tags"] as? [String] {
                        return tags
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Search (tag matching)

    func searchByTerms(_ searchTerms: [String], photoLibrary: PhotoLibraryService) -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        var results: [PHAsset] = []

        DebugLogger.shared.log("SEARCH", "Buscando: \(searchTerms.prefix(5).joined(separator: ", "))")
        DebugLogger.shared.log("SEARCH", "Index: \(photoIndex.count)")

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let indexed = photoIndex[asset.localIdentifier] else { continue }

            let match = searchTerms.contains { term in
                indexed.tags.contains { tag in
                    tag.lowercased().contains(term.lowercased()) || term.lowercased().contains(tag.lowercased())
                }
            }

            if match {
                results.append(asset)
                DebugLogger.shared.log("SEARCH", "MATCH: \(indexed.tags.prefix(5).joined(separator: ", "))")
                if results.count >= 200 { break }
            }
        }

        DebugLogger.shared.log("SEARCH", "Total: \(results.count) resultados")
        return results
    }

    /// Search by GPS location
    func searchByLocation(place: String, photoLibrary: PhotoLibraryService) async -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        DebugLogger.shared.log("GPS", "Geocodificando: \"\(place)\"")

        let targetLocation: CLLocation? = await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(place) { placemarks, _ in
                continuation.resume(returning: placemarks?.first?.location)
            }
        }

        guard let target = targetLocation else {
            DebugLogger.shared.log("GPS", "ERROR: no se pudo geocodificar")
            return []
        }

        DebugLogger.shared.log("GPS", "Coordenadas: \(String(format: "%.4f", target.coordinate.latitude)), \(String(format: "%.4f", target.coordinate.longitude))")

        var results: [PHAsset] = []
        var photosWithGPS = 0
        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let assetLoc = asset.location else { continue }
            photosWithGPS += 1
            if assetLoc.distance(from: target) < 5000 {
                results.append(asset)
                if results.count >= 200 { break }
            }
        }

        DebugLogger.shared.log("GPS", "Con GPS: \(photosWithGPS), matches: \(results.count)")
        return results
    }

    /// Category-based search
    func photosForCategory(_ category: PhotoCategory, photoLibrary: PhotoLibraryService) -> [PHAsset] {
        let terms: [String]
        switch category {
        case .documents:
            terms = ["documento", "captura", "pantalla", "texto", "papel", "libro", "recibo", "nota"]
        case .landscapes:
            terms = ["paisaje", "montaña", "montana", "playa", "lago", "rio", "bosque", "atardecer", "amanecer", "naturaleza"]
        default:
            return []
        }
        return searchByTerms(terms, photoLibrary: photoLibrary)
    }

    func photosForPeople(photoLibrary: PhotoLibraryService) -> [PHAsset] {
        return searchByTerms(["hombre", "mujer", "niño", "niña", "persona", "gente", "grupo", "bebé", "joven"], photoLibrary: photoLibrary)
    }

    func tagsForAsset(_ assetId: String) -> [String]? {
        return photoIndex[assetId]?.tags
    }

    var availableTags: [String] {
        var allTags: Set<String> = []
        for photo in photoIndex.values.prefix(100) {
            for tag in photo.tags { allTags.insert(tag) }
        }
        return Array(allTags).sorted()
    }
}
