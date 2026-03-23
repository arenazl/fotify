import SwiftUI
import Photos
import CoreLocation

// MARK: - Structured photo description

struct PhotoFields: Codable {
    let personas: String
    let lugar: String
    let objetos: String
    let escena: String
    let actividad: String
    let texto: String

    /// Check if any field matches the given values
    func matchesField(_ field: String, values: [String]) -> Bool {
        let fieldValue: String
        switch field {
        case "personas": fieldValue = personas
        case "lugar": fieldValue = lugar
        case "objetos": fieldValue = objetos
        case "escena": fieldValue = escena
        case "actividad": fieldValue = actividad
        case "texto": fieldValue = texto
        default: return false
        }
        let lower = fieldValue.lowercased()
        if values.contains("not_empty") { return !lower.isEmpty }
        return values.contains { lower.contains($0.lowercased()) }
    }
}

struct IndexedPhoto: Codable {
    let assetId: String
    let fields: PhotoFields
    let date: String?
    let gps: String? // "lat,lng"
}

// MARK: - Search filter (from Groq)

struct SearchFilter: Codable {
    let field: String
    let values: [String]
}

struct SearchResponse: Codable {
    let filters: [SearchFilter]
    let message: String
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
    private let currentSchemaVersion = 5 // structured fields

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
        let scanMax = Config.debugMode ? Config.quickScanLimit : allPhotos.count
        for i in 0..<min(allPhotos.count, scanMax) {
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
                        let fields = await self.analyzeWithLlama(base64Image: base64)

                        if let f = fields {
                            let summary = "[\(f.escena)] \(f.objetos.prefix(30))"
                            await DebugLogger.shared.log("INDEX", "OK: \(summary)")
                            if gpsStr != nil { await DebugLogger.shared.log("INDEX", "GPS: \(gpsStr!)") }

                            let indexed = IndexedPhoto(assetId: asset.localIdentifier, fields: f, date: dateStr, gps: gpsStr)
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
                        let desc = "[\(idx.fields.escena)] \(idx.fields.objetos.prefix(40))"
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

    private func analyzeWithLlama(base64Image: String) async -> PhotoFields? {
        let requestBody: [String: Any] = [
            "model": Config.groqVisionModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": """
                            Analizá esta foto y respondé SOLO con este JSON (sin markdown, sin ```):
                            {"personas":"","lugar":"","objetos":"","escena":"","actividad":"","texto":""}

                            Reglas:
                            - personas: quiénes se ven (hombre, mujer, niño, grupo, bebé). Vacío "" si no hay nadie.
                            - lugar: tipo de lugar (interior/exterior, y tipo: casa, oficina, playa, calle, parque, restaurante, etc)
                            - objetos: TODOS los objetos principales visibles (animales incluidos)
                            - escena: tipo de escena en 2-3 palabras
                            - actividad: qué está pasando
                            - texto: texto visible en la foto (carteles, pantallas, etiquetas). Vacío "" si no hay.
                            Solo lo que se ve. Campos vacíos "" si no aplica. Sé específico.
                            """],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 200,
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
                // Parse the structured JSON
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsonStart = cleaned.firstIndex(of: "{"),
                   let jsonEnd = cleaned.lastIndex(of: "}") {
                    let jsonStr = String(cleaned[jsonStart...jsonEnd])
                    if let fieldsData = jsonStr.data(using: .utf8),
                       let fields = try? JSONDecoder().decode(PhotoFields.self, from: fieldsData) {
                        return fields
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Search (structured filters)

    func searchWithFilters(_ filters: [SearchFilter], photoLibrary: PhotoLibraryService) -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        var results: [PHAsset] = []

        Task { @MainActor in
            DebugLogger.shared.log("SEARCH", "Filters: \(filters.map { "\($0.field):\($0.values.joined(separator: "|"))" }.joined(separator: " + "))")
            DebugLogger.shared.log("SEARCH", "Index size: \(photoIndex.count)")
        }

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let indexed = photoIndex[asset.localIdentifier] else { continue }

            let match = filters.allSatisfy { filter in
                indexed.fields.matchesField(filter.field, values: filter.values)
            }

            if match {
                results.append(asset)
                Task { @MainActor in
                    DebugLogger.shared.log("SEARCH", "MATCH: [\(indexed.fields.escena)] \(indexed.fields.objetos.prefix(40))")
                }
                if results.count >= 200 { break }
            }
        }

        Task { @MainActor in
            DebugLogger.shared.log("SEARCH", "Total: \(results.count) resultados")
        }

        return results
    }

    /// Legacy text search (fallback)
    func search(tags searchTags: [String], photoLibrary: PhotoLibraryService) -> [PHAsset] {
        let filters = searchTags.map { SearchFilter(field: "escena", values: [$0]) }
        return searchWithFilters(filters, photoLibrary: photoLibrary)
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
        let filters: [SearchFilter]
        switch category {
        case .documents:
            filters = [SearchFilter(field: "escena", values: ["documento", "captura", "pantalla", "texto", "papel", "libro", "recibo", "nota"])]
        case .landscapes:
            filters = [SearchFilter(field: "escena", values: ["paisaje", "natural", "montaña", "montana", "playa", "lago", "rio", "bosque", "atardecer", "amanecer"])]
        default:
            return []
        }
        return searchWithFilters(filters, photoLibrary: photoLibrary)
    }

    func photosForPeople(photoLibrary: PhotoLibraryService) -> [PHAsset] {
        let filters = [SearchFilter(field: "personas", values: ["not_empty"])]
        return searchWithFilters(filters, photoLibrary: photoLibrary)
    }

    var availableTags: [String] {
        Array(photoIndex.values.prefix(50).map { $0.fields.escena })
    }
}
