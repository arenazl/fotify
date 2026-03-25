import SwiftUI
import Photos

@MainActor
class DuplicatesViewModel: ObservableObject {
    enum State {
        case idle
        case scanning(Double)
        case done
    }

    @Published var state: State = .idle
    @Published var duplicateGroups: [[PHAsset]] = []

    func scanForDuplicates(photoLibrary: PhotoLibraryService) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        state = .scanning(0)
        duplicateGroups = []

        let totalCount = allPhotos.count
        guard totalCount > 1 else {
            state = .done
            return
        }

        // Generate dHash for each photo
        var hashes: [String: [PHAsset]] = [:]

        for i in 0..<totalCount {
            let asset = allPhotos.object(at: i)

            if let hash = await generateDHash(for: asset, photoLibrary: photoLibrary) {
                hashes[hash, default: []].append(asset)
            }

            state = .scanning(Double(i + 1) / Double(totalCount))
        }

        // Filter groups with more than 1 photo (duplicates)
        duplicateGroups = hashes.values
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }

        state = .done
    }

    /// Remove specific assets from groups without re-scanning
    func removeAssets(ids: Set<String>) {
        duplicateGroups = duplicateGroups.map { group in
            group.filter { !ids.contains($0.localIdentifier) }
        }.filter { $0.count > 1 }
    }

    func clearAll() {
        duplicateGroups = []
        state = .done
    }

    private func generateDHash(for asset: PHAsset, photoLibrary: PhotoLibraryService) async -> String? {
        // Get a small thumbnail for hashing
        guard let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 9, height: 8)) else {
            return nil
        }

        guard let cgImage = image.cgImage else { return nil }

        // Convert to grayscale and compute difference hash
        let width = 9
        let height = 8

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        // Compute difference hash: compare adjacent pixels
        var hash: UInt64 = 0
        var bit: UInt64 = 1

        for row in 0..<height {
            for col in 0..<(width - 1) {
                let leftPixel = pixels[row * width + col]
                let rightPixel = pixels[row * width + col + 1]
                if leftPixel > rightPixel {
                    hash |= bit
                }
                bit <<= 1
            }
        }

        return String(hash, radix: 16)
    }
}
