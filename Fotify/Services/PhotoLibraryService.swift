import SwiftUI
import Photos

@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: PHFetchResult<PHAsset>?
    @Published var screenshots: PHFetchResult<PHAsset>?
    @Published var photoCount: Int = 0
    @Published var screenshotCount: Int = 0
    @Published var isLoading: Bool = false

    private let imageManager = PHCachingImageManager()

    func checkAuthorization() async {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            await loadLibrary()
        }
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            await loadLibrary()
        }
    }

    func loadLibrary() async {
        isLoading = true

        // Fetch all photos sorted by date
        let allOptions = PHFetchOptions()
        allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        allOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        allPhotos = PHAsset.fetchAssets(with: .image, options: allOptions)
        photoCount = allPhotos?.count ?? 0

        // Fetch screenshots
        let screenshotOptions = PHFetchOptions()
        screenshotOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        screenshotOptions.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        screenshots = PHAsset.fetchAssets(with: .image, options: screenshotOptions)
        screenshotCount = screenshots?.count ?? 0

        isLoading = false
    }

    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func fullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
        await loadLibrary()
    }
}
