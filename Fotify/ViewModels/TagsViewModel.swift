import SwiftUI
import Photos
import Vision

struct TaggedPhoto {
    let asset: PHAsset
    let tags: [String]
    let confidence: [String: Float]
}

@MainActor
class TagsViewModel: ObservableObject {
    enum State {
        case idle
        case classifying(Double)
        case done
    }

    @Published var state: State = .idle
    @Published var tagGroups: [String: [TaggedPhoto]] = [:]
    @Published var allTagged: [TaggedPhoto] = []

    var sortedTags: [(key: String, value: [TaggedPhoto])] {
        tagGroups.sorted { $0.value.count > $1.value.count }
    }

    // MARK: - Vision Framework (on-device)

    func classifyPhotos(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        state = .classifying(0)
        tagGroups = [:]
        allTagged = []

        let totalCount = min(allPhotos.count, 500) // Limit first scan

        for i in 0..<totalCount {
            let asset = allPhotos.object(at: i)

            if let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 300, height: 300)),
               let cgImage = image.cgImage {

                let tags = await classifyWithVision(cgImage: cgImage)
                let tagged = TaggedPhoto(
                    asset: asset,
                    tags: tags.map { $0.0 },
                    confidence: Dictionary(uniqueKeysWithValues: tags)
                )
                allTagged.append(tagged)

                for tag in tagged.tags {
                    tagGroups[tag, default: []].append(tagged)
                }
            }

            state = .classifying(Double(i + 1) / Double(totalCount))
        }

        state = .done
    }

    private func classifyWithVision(cgImage: CGImage) async -> [(String, Float)] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                guard let results = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Take top tags with confidence > 0.3
                let topTags = results
                    .filter { $0.confidence > 0.3 }
                    .prefix(5)
                    .map { ($0.identifier, $0.confidence) }

                continuation.resume(returning: Array(topTags))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Grok Vision API (cloud)

    func classifyWithGrok(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        state = .classifying(0)
        tagGroups = [:]
        allTagged = []

        let totalCount = min(allPhotos.count, 100) // Limit for API costs

        for i in 0..<totalCount {
            let asset = allPhotos.object(at: i)

            if let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 512, height: 512)) {
                let tags = await GrokService.shared.classifyImage(image)
                let tagged = TaggedPhoto(
                    asset: asset,
                    tags: tags,
                    confidence: Dictionary(uniqueKeysWithValues: tags.map { ($0, Float(1.0)) })
                )
                allTagged.append(tagged)

                for tag in tagged.tags {
                    tagGroups[tag, default: []].append(tagged)
                }
            }

            state = .classifying(Double(i + 1) / Double(totalCount))
        }

        state = .done
    }
}
