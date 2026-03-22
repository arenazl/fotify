import SwiftUI
import Photos

// MARK: - Photo Category

enum PhotoCategory: String, CaseIterable, Identifiable {
    case timeline, places, people, screenshots, duplicates
    case favorites, videos, selfies, livePhotos
    case documents, night, aiTags

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timeline: "Timeline"
        case .places: "Lugares"
        case .people: "Personas"
        case .screenshots: "Capturas"
        case .duplicates: "Duplicados"
        case .favorites: "Favoritos"
        case .videos: "Videos"
        case .selfies: "Selfies"
        case .livePhotos: "Live Photos"
        case .documents: "Documentos"
        case .night: "Noche"
        case .aiTags: "Tags IA"
        }
    }

    var icon: String {
        switch self {
        case .timeline: "clock.arrow.circlepath"
        case .places: "map"
        case .people: "person.2.fill"
        case .screenshots: "rectangle.dashed"
        case .duplicates: "doc.on.doc.fill"
        case .favorites: "heart.fill"
        case .videos: "video.fill"
        case .selfies: "person.crop.square"
        case .livePhotos: "camera.viewfinder"
        case .documents: "doc.text.viewfinder"
        case .night: "moon.stars.fill"
        case .aiTags: "tag.fill"
        }
    }

    var color: Color {
        switch self {
        case .timeline: .blue
        case .places: .green
        case .people: .pink
        case .screenshots: .orange
        case .duplicates: .purple
        case .favorites: .red
        case .videos: .cyan
        case .selfies: .indigo
        case .livePhotos: .mint
        case .documents: .brown
        case .night: .indigo
        case .aiTags: .purple
        }
    }

    /// Categories that navigate to their own specialized view instead of a generic grid
    var hasCustomView: Bool {
        switch self {
        case .screenshots, .duplicates: true
        default: false
        }
    }
}

@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: PHFetchResult<PHAsset>?
    @Published var screenshots: PHFetchResult<PHAsset>?
    @Published var favorites: PHFetchResult<PHAsset>?
    @Published var videos: PHFetchResult<PHAsset>?
    @Published var selfies: PHFetchResult<PHAsset>?
    @Published var livePhotos: PHFetchResult<PHAsset>?
    @Published var photoCount: Int = 0
    @Published var screenshotCount: Int = 0
    @Published var favoritesCount: Int = 0
    @Published var videosCount: Int = 0
    @Published var selfiesCount: Int = 0
    @Published var livePhotosCount: Int = 0
    @Published var placesCount: Int = 0
    @Published var nightCount: Int = 0
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

        // Fetch favorites
        let favOptions = PHFetchOptions()
        favOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        favOptions.predicate = NSPredicate(format: "isFavorite == YES")
        favorites = PHAsset.fetchAssets(with: favOptions)
        favoritesCount = favorites?.count ?? 0

        // Fetch videos
        let videoOptions = PHFetchOptions()
        videoOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        videos = PHAsset.fetchAssets(with: videoOptions)
        videosCount = videos?.count ?? 0

        // Fetch selfies (from smart album)
        let selfieCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil
        )
        if let selfieAlbum = selfieCollections.firstObject {
            let selfieOptions = PHFetchOptions()
            selfieOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            selfies = PHAsset.fetchAssets(in: selfieAlbum, options: selfieOptions)
        }
        selfiesCount = selfies?.count ?? 0

        // Fetch live photos
        let liveOptions = PHFetchOptions()
        liveOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        liveOptions.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoLive.rawValue
        )
        livePhotos = PHAsset.fetchAssets(with: .image, options: liveOptions)
        livePhotosCount = livePhotos?.count ?? 0

        // Count places & night photos from allPhotos (single pass)
        var locationCount = 0
        var nightPhotoCount = 0
        let calendar = Calendar.current
        if let all = allPhotos {
            for i in 0..<min(all.count, 1000) {
                let asset = all.object(at: i)
                if asset.location != nil {
                    locationCount += 1
                }
                if let date = asset.creationDate {
                    let hour = calendar.component(.hour, from: date)
                    if hour >= 20 || hour < 6 {
                        nightPhotoCount += 1
                    }
                }
            }
        }
        placesCount = locationCount
        nightCount = nightPhotoCount

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

    /// Returns the count for a given category
    func count(for category: PhotoCategory) -> Int? {
        switch category {
        case .timeline: return photoCount
        case .places: return placesCount > 0 ? placesCount : nil
        case .screenshots: return screenshotCount
        case .favorites: return favoritesCount > 0 ? favoritesCount : nil
        case .videos: return videosCount > 0 ? videosCount : nil
        case .selfies: return selfiesCount > 0 ? selfiesCount : nil
        case .livePhotos: return livePhotosCount > 0 ? livePhotosCount : nil
        case .night: return nightCount > 0 ? nightCount : nil
        case .people, .documents, .duplicates, .aiTags: return nil
        }
    }

    /// Returns assets for a given category
    func assets(for category: PhotoCategory) -> [PHAsset] {
        let fetchResult: PHFetchResult<PHAsset>?
        switch category {
        case .timeline:
            fetchResult = allPhotos
        case .places:
            // Filter allPhotos by location
            guard let all = allPhotos else { return [] }
            var result: [PHAsset] = []
            for i in 0..<all.count {
                let asset = all.object(at: i)
                if asset.location != nil {
                    result.append(asset)
                }
            }
            return result
        case .screenshots:
            fetchResult = screenshots
        case .favorites:
            fetchResult = favorites
        case .videos:
            fetchResult = videos
        case .selfies:
            fetchResult = selfies
        case .livePhotos:
            fetchResult = livePhotos
        case .night:
            // Filter allPhotos by hour (8PM to 6AM)
            guard let all = allPhotos else { return [] }
            let calendar = Calendar.current
            var result: [PHAsset] = []
            for i in 0..<all.count {
                let asset = all.object(at: i)
                if let date = asset.creationDate {
                    let hour = calendar.component(.hour, from: date)
                    if hour >= 20 || hour < 6 {
                        result.append(asset)
                    }
                }
            }
            return result
        case .people, .documents, .duplicates, .aiTags:
            fetchResult = nil
        }
        guard let result = fetchResult else { return [] }
        var assets: [PHAsset] = []
        for i in 0..<result.count {
            assets.append(result.object(at: i))
        }
        return assets
    }

    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
        await loadLibrary()
    }
}
