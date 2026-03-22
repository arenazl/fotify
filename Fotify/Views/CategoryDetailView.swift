import SwiftUI
import Photos

struct CategoryDetailView: View {
    let category: PhotoCategory
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @State private var assets: [PHAsset] = []
    @State private var fetchResult: PHFetchResult<PHAsset>?
    @State private var totalCount: Int = 0
    @State private var isLoading = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack {
            FotifyTheme.meshGradient
                .ignoresSafeArea()

            if isLoading {
                ProgressView("Cargando...")
                    .tint(.white)
            } else if totalCount == 0 {
                emptyView
            } else {
                photoGrid
            }
        }
        .navigationTitle(category.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundStyle(category.color)
                    Text(category.label)
                        .font(.headline)
                    if totalCount > 0 {
                        Text("(\(totalCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            await loadContent()
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sin \(category.label.lowercased())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if category.needsVisionScan && tagsVM.scannedCount < tagsVM.totalCount {
                Text("Escaneando en background... \(tagsVM.scannedCount)/\(tagsVM.totalCount)")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                if let fetch = fetchResult {
                    // Use PHFetchResult directly — lazy, no 33k array
                    ForEach(0..<min(fetch.count, 5000), id: \.self) { index in
                        CategoryPhotoCell(asset: fetch.object(at: index))
                    }
                } else {
                    ForEach(0..<assets.count, id: \.self) { index in
                        CategoryPhotoCell(asset: assets[index])
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Load Content

    private func loadContent() async {
        switch category {
        case .recents, .screenshots, .favorites, .videos, .selfies, .livePhotos:
            let fetch = photoLibrary.fetchResult(for: category)
            fetchResult = fetch
            totalCount = fetch?.count ?? 0

        case .places:
            let filtered = await photoLibrary.filteredAssets(for: category, limit: 300)
            assets = filtered
            totalCount = filtered.count

        case .people:
            let fetch = photoLibrary.fetchResult(for: .selfies)
            fetchResult = fetch
            totalCount = fetch?.count ?? 0

        case .documents, .landscapes:
            let found = tagsVM.photosForCategory(category, photoLibrary: photoLibrary)
            assets = found
            totalCount = found.count

        case .duplicates, .aiSearch:
            break
        }

        isLoading = false
    }
}

// MARK: - Category Photo Cell

struct CategoryPhotoCell: View {
    let asset: PHAsset
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.15))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 200, height: 200))
        }
    }
}
