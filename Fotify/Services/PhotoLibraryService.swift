import SwiftUI
import Photos

// MARK: - Photo Category

enum PhotoCategory: String, CaseIterable, Identifiable {
    case recents, places, people, screenshots, duplicates
    case favorites, videos, selfies, livePhotos
    case documents, landscapes, aiSearch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recents: "Recientes"
        case .places: "Lugares"
        case .people: "Personas"
        case .screenshots: "Capturas"
        case .duplicates: "Duplicados"
        case .favorites: "Favoritos"
        case .videos: "Videos"
        case .selfies: "Selfies"
        case .livePhotos: "Live Photos"
        case .documents: "Documentos"
        case .landscapes: "Paisajes"
        case .aiSearch: "Buscar IA"
        }
    }

    var icon: String {
        switch self {
        case .recents: "clock.arrow.circlepath"
        case .places: "map"
        case .people: "person.2.fill"
        case .screenshots: "rectangle.dashed"
        case .duplicates: "doc.on.doc.fill"
        case .favorites: "heart.fill"
        case .videos: "video.fill"
        case .selfies: "person.crop.square"
        case .livePhotos: "camera.viewfinder"
        case .documents: "doc.text.viewfinder"
        case .landscapes: "mountain.2.fill"
        case .aiSearch: "sparkle.magnifyingglass"
        }
    }

    var color: Color {
        switch self {
        case .recents: .blue
        case .places: .green
        case .people: .pink
        case .screenshots: .orange
        case .duplicates: .purple
        case .favorites: .red
        case .videos: .cyan
        case .selfies: .indigo
        case .livePhotos: .mint
        case .documents: .brown
        case .landscapes: .teal
        case .aiSearch: .purple
        }
    }

    /// Categories that need Vision background scan
    var needsVisionScan: Bool {
        switch self {
        case .documents, .landscapes: true
        default: false
        }
    }
}

// MARK: - Photo Library Service

@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: PHFetchResult<PHAsset>?
    @Published var screenshots: PHFetchResult<PHAsset>?
    @Published var favorites: PHFetchResult<PHAsset>?
    @Published var videos: PHFetchResult<PHAsset>?
    @Published var selfies: PHFetchResult<PHAsset>?
    @Published var livePhotos: PHFetchResult<PHAsset>?
    @Published var people: PHFetchResult<PHAsset>?
    @Published var photoCount: Int = 0
    @Published var screenshotCount: Int = 0
    @Published var favoritesCount: Int = 0
    @Published var videosCount: Int = 0
    @Published var selfiesCount: Int = 0
    @Published var livePhotosCount: Int = 0
    @Published var peopleCount: Int = 0
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

        let defaultSort = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // All photos
        let allOptions = PHFetchOptions()
        allOptions.sortDescriptors = defaultSort
        allPhotos = PHAsset.fetchAssets(with: .image, options: allOptions)
        photoCount = allPhotos?.count ?? 0

        // Screenshots (smart album — iOS manages this, more accurate)
        let screenshotCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil
        )
        if let screenshotAlbum = screenshotCollections.firstObject {
            let screenshotOptions = PHFetchOptions()
            screenshotOptions.sortDescriptors = defaultSort
            screenshots = PHAsset.fetchAssets(in: screenshotAlbum, options: screenshotOptions)
        }
        screenshotCount = screenshots?.count ?? 0

        // Favorites
        let favOptions = PHFetchOptions()
        favOptions.sortDescriptors = defaultSort
        favOptions.predicate = NSPredicate(format: "isFavorite == YES AND mediaType == %d", PHAssetMediaType.image.rawValue)
        favorites = PHAsset.fetchAssets(with: favOptions)
        favoritesCount = favorites?.count ?? 0

        // Videos
        let videoOptions = PHFetchOptions()
        videoOptions.sortDescriptors = defaultSort
        videos = PHAsset.fetchAssets(with: .video, options: videoOptions)
        videosCount = videos?.count ?? 0

        // Selfies
        let selfieCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil
        )
        if let selfieAlbum = selfieCollections.firstObject {
            let selfieOptions = PHFetchOptions()
            selfieOptions.sortDescriptors = defaultSort
            selfies = PHAsset.fetchAssets(in: selfieAlbum, options: selfieOptions)
        }
        selfiesCount = selfies?.count ?? 0

        // Live Photos
        let liveOptions = PHFetchOptions()
        liveOptions.sortDescriptors = defaultSort
        liveOptions.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoLive.rawValue
        )
        livePhotos = PHAsset.fetchAssets(with: .image, options: liveOptions)
        livePhotosCount = livePhotos?.count ?? 0

        // People — fetch all person smart albums and collect their assets
        var allPeopleAssets: [PHAsset] = []
        let personCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil
        )
        // Try fetching from Faces/People albums
        let faceCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        for i in 0..<faceCollections.count {
            if let collection = faceCollections.object(at: i) as? PHAssetCollection,
               collection.localizedTitle?.lowercased().contains("people") == true ||
               collection.localizedTitle?.lowercased().contains("personas") == true {
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                for j in 0..<min(assets.count, 300) {
                    allPeopleAssets.append(assets.object(at: j))
                }
            }
        }
        peopleCount = allPeopleAssets.count

        isLoading = false
    }

    // MARK: - Category Data

    func count(for category: PhotoCategory) -> Int? {
        switch category {
        case .recents: return photoCount
        case .screenshots: return screenshotCount > 0 ? screenshotCount : nil
        case .favorites: return favoritesCount > 0 ? favoritesCount : nil
        case .videos: return videosCount > 0 ? videosCount : nil
        case .selfies: return selfiesCount > 0 ? selfiesCount : nil
        case .livePhotos: return livePhotosCount > 0 ? livePhotosCount : nil
        case .people: return peopleCount > 0 ? peopleCount : nil
        case .places, .documents, .landscapes, .duplicates, .aiSearch: return nil
        }
    }

    func fetchResult(for category: PhotoCategory) -> PHFetchResult<PHAsset>? {
        switch category {
        case .recents: return allPhotos
        case .screenshots: return screenshots
        case .favorites: return favorites
        case .videos: return videos
        case .selfies: return selfies
        case .livePhotos: return livePhotos
        default: return nil
        }
    }

    func filteredAssets(for category: PhotoCategory, limit: Int = 300) async -> [PHAsset] {
        guard let all = allPhotos else { return [] }
        var result: [PHAsset] = []

        if category == .places {
            for i in 0..<all.count {
                let asset = all.object(at: i)
                if asset.location != nil {
                    result.append(asset)
                    if result.count >= limit { break }
                }
            }
        }
        return result
    }

    // MARK: - Images

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
