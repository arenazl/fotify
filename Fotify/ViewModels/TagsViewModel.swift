import SwiftUI
import Photos
import Vision

// MARK: - Persisted tag data

struct PhotoTagEntry: Codable {
    let assetId: String
    let tags: [String]
}

// MARK: - Tags ViewModel (background scan + persistence + search)

@MainActor
class TagsViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning(Double) // progress 0..1
        case ready
    }

    @Published var state: State = .idle
    @Published var scannedCount: Int = 0
    @Published var totalCount: Int = 0

    /// In-memory tag index: assetId → [tags]
    private var tagIndex: [String: [String]] = [:]

    /// Tags that indicate landscape/outdoor photos
    static let landscapeTags: Set<String> = [
        "outdoor", "landscape", "sky", "mountain", "beach",
        "forest", "sunset", "sunrise", "ocean", "lake",
        "river", "field", "garden", "park", "snow",
        "cloud", "tree", "nature", "scenery", "hill",
        "coast", "horizon", "valley", "desert", "waterfall"
    ]

    /// Tags that indicate documents/text
    static let documentTags: Set<String> = [
        "text", "document", "paper", "book", "writing",
        "letter", "receipt", "label", "sign", "menu",
        "screen", "monitor", "whiteboard", "note", "page"
    ]

    // MARK: - Persistence

    private var tagsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("photo_tags.json")
    }

    func loadPersistedTags() {
        guard let data = try? Data(contentsOf: tagsFileURL),
              let entries = try? JSONDecoder().decode([PhotoTagEntry].self, from: data) else {
            return
        }
        for entry in entries {
            tagIndex[entry.assetId] = entry.tags
        }
        scannedCount = tagIndex.count
        if scannedCount > 0 {
            state = .ready
        }
    }

    private func persistTags() {
        let entries = tagIndex.map { PhotoTagEntry(assetId: $0.key, tags: $0.value) }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: tagsFileURL)
        }
    }

    // MARK: - Background Scan

    /// Scans most recent photos in background (limit 2000 to finish in minutes, not hours)
    func backgroundScan(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        let scanLimit = allPhotos.count
        totalCount = scanLimit
        let batchSize = 50

        // Find which photos still need scanning (most recent first)
        var toScan: [(Int, PHAsset)] = []
        for i in 0..<scanLimit {
            let asset = allPhotos.object(at: i)
            if tagIndex[asset.localIdentifier] == nil {
                toScan.append((i, asset))
            }
        }

        if toScan.isEmpty {
            state = .ready
            return
        }

        state = .scanning(Double(scannedCount) / Double(totalCount))

        // Process in batches at low priority so UI stays responsive
        for batchStart in stride(from: 0, to: toScan.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, toScan.count)
            let batch = toScan[batchStart..<batchEnd]

            for (_, asset) in batch {
                // Yield frequently to keep UI responsive
                await Task.yield()

                if let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 100, height: 100)),
                   let cgImage = image.cgImage {
                    let tags = await classifyWithVision(cgImage: cgImage)
                    tagIndex[asset.localIdentifier] = tags
                    scannedCount = tagIndex.count
                }
            }

            // Update progress
            state = .scanning(Double(scannedCount) / Double(totalCount))

            // Save after each batch
            persistTags()

            // Pause between batches to let UI breathe
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        state = .ready
    }

    // MARK: - Vision Classification

    private func classifyWithVision(cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                guard let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let tags = results
                    .filter { $0.confidence > 0.3 }
                    .prefix(8)
                    .map { $0.identifier.lowercased() }

                continuation.resume(returning: Array(tags))
            }

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Search

    /// Search photos by natural language query (matched against Vision tags)
    func search(tags searchTags: [String], photoLibrary: PhotoLibraryService) -> [PHAsset] {
        return searchWithDebug(tags: searchTags, photoLibrary: photoLibrary).assets
    }

    /// Search with debug info — returns matched assets and their tags
    func searchWithDebug(tags searchTags: [String], photoLibrary: PhotoLibraryService) -> (assets: [PHAsset], matchedTags: [[String]]) {
        guard let allPhotos = photoLibrary.allPhotos else { return ([], []) }

        let lowered = searchTags.map { $0.lowercased() }
        var results: [PHAsset] = []
        var matchedTags: [[String]] = []

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let assetTags = tagIndex[asset.localIdentifier] else { continue }

            // Strict match: tag must equal search tag exactly
            let match = assetTags.contains { tag in
                lowered.contains { searchTag in
                    tag == searchTag
                }
            }

            if match {
                results.append(asset)
                matchedTags.append(assetTags)
                if results.count >= 200 { break }
            }
        }

        return (results, matchedTags)
    }

    /// Get photos matching a category (documents or landscapes)
    func photosForCategory(_ category: PhotoCategory, photoLibrary: PhotoLibraryService) -> [PHAsset] {
        guard let allPhotos = photoLibrary.allPhotos else { return [] }

        let targetTags: Set<String>
        switch category {
        case .documents: targetTags = Self.documentTags
        case .landscapes: targetTags = Self.landscapeTags
        default: return []
        }

        var results: [PHAsset] = []

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            guard let assetTags = tagIndex[asset.localIdentifier] else { continue }

            let match = assetTags.contains { tag in
                targetTags.contains(where: { tag.contains($0) || $0.contains(tag) })
            }

            if match {
                results.append(asset)
                if results.count >= 300 { break }
            }
        }

        return results
    }

    /// Available tags for Groq context
    var availableTags: [String] {
        var allTags: Set<String> = []
        for tags in tagIndex.values {
            for tag in tags {
                allTags.insert(tag)
            }
        }
        return Array(allTags).sorted()
    }
}
