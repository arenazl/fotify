import SwiftUI
import Photos

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

    /// In-memory index: assetId → description
    private var descriptionIndex: [String: String] = [:]

    // MARK: - Persistence

    private var tagsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("photo_descriptions.json")
    }

    func loadPersistedTags() {
        guard let data = try? Data(contentsOf: tagsFileURL),
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
            try? data.write(to: tagsFileURL)
        }
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

        state = .scanning(Double(scannedCount) / Double(totalCount))

        // Process in batches
        for batchStart in stride(from: 0, to: toScan.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, toScan.count)
            let batch = Array(toScan[batchStart..<batchEnd])

            // Process batch concurrently (up to 5 at a time)
            await withTaskGroup(of: (String, String?).self) { group in
                for asset in batch {
                    group.addTask {
                        guard let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 200, height: 200)),
                              let jpegData = image.jpegData(compressionQuality: 0.5) else {
                            return (asset.localIdentifier, nil)
                        }

                        let base64 = jpegData.base64EncodedString()
                        let description = await self.describeWithLlama(base64Image: base64)
                        return (asset.localIdentifier, description)
                    }
                }

                for await (assetId, description) in group {
                    if let desc = description {
                        descriptionIndex[assetId] = desc
                        scannedCount = descriptionIndex.count
                    }
                }
            }

            state = .scanning(Double(scannedCount) / Double(totalCount))
            persistDescriptions()

            // Pause between batches
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
        return searchWithDebug(tags: searchTags, photoLibrary: photoLibrary).assets
    }

    func searchWithDebug(tags searchTags: [String], photoLibrary: PhotoLibraryService) -> (assets: [PHAsset], matchedTags: [[String]]) {
        guard let allPhotos = photoLibrary.allPhotos else { return ([], []) }

        let lowered = searchTags.map { $0.lowercased() }
        var results: [PHAsset] = []
        var matchedDescs: [[String]] = []

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let description = descriptionIndex[asset.localIdentifier] else { continue }

            let descLower = description.lowercased()
            let match = lowered.contains { searchTag in
                descLower.contains(searchTag)
            }

            if match {
                results.append(asset)
                matchedDescs.append([description])
                if results.count >= 200 { break }
            }
        }

        return (results, matchedDescs)
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
