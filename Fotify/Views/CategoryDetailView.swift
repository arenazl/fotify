import SwiftUI
import Photos

struct CategoryDetailView: View {
    let category: PhotoCategory
    let onBack: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @State private var assets: [PHAsset] = []
    @State private var fetchResult: PHFetchResult<PHAsset>?
    @State private var totalCount: Int = 0
    @State private var isLoading = true
    @State private var dragOffset: CGFloat = 0
    @State private var searchText: String = ""
    @State private var isSearching = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if category == .aiSearch {
                aiSearchView
            } else if isLoading {
                loadingView
            } else if totalCount == 0 {
                emptyView
            } else {
                photoGrid
            }
        }
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width > 100 {
                        onBack()
                    } else {
                        withAnimation(.spring(duration: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task {
            if category != .aiSearch {
                await loadContent()
            } else {
                isLoading = false
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(Circle())
            }

            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(category.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.label.uppercased())
                    .font(.caption.bold())
                    .kerning(2)
                    .foregroundStyle(category.color)
                if category.needsVisionScan {
                    Text("\(totalCount) encontradas · \(tagsVM.scannedCount)/\(tagsVM.totalCount) escaneadas")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if category != .aiSearch {
                    Text("\(totalCount) elementos")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - AI Search View

    private var aiSearchView: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(.purple)
                TextField("Buscá: perro, playa, comida...", text: $searchText)
                    .onSubmit { Task { await performSearch() } }
                if isSearching {
                    ProgressView().tint(.purple).scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            // Scan status
            if case .scanning(let progress) = tagsVM.state {
                HStack(spacing: 8) {
                    ProgressView().tint(.purple).scaleEffect(0.7)
                    Text("Escaneando biblioteca... \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if tagsVM.scannedCount > 0 {
                Text("\(tagsVM.scannedCount) fotos indexadas para búsqueda")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Results
            if assets.isEmpty && !searchText.isEmpty && !isSearching {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Sin resultados para \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if tagsVM.scannedCount < tagsVM.totalCount {
                        Text("Aún faltan \(tagsVM.totalCount - tagsVM.scannedCount) fotos por escanear")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }
                Spacer()
            } else if assets.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.purple.opacity(0.5))
                    Text("Escribí qué querés buscar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Text("\(assets.count) resultados")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(0..<assets.count, id: \.self) { index in
                            CategoryPhotoCell(asset: assets[index])
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Cargando...")
                .tint(.white)
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack {
            Spacer()
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
                    .padding(.top, 4)
            }
            Spacer()
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 2) {
                if let fetch = fetchResult {
                    ForEach(0..<fetch.count, id: \.self) { index in
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
        // PHFetchResult-backed — instant
        case .recents, .screenshots, .favorites, .videos, .selfies, .livePhotos:
            let fetch = photoLibrary.fetchResult(for: category)
            fetchResult = fetch
            totalCount = fetch?.count ?? 0
            isLoading = false

        // Filtered by location
        case .places:
            let filtered = await photoLibrary.filteredAssets(for: category, limit: 300)
            assets = filtered
            totalCount = filtered.count
            isLoading = false

        // People — use selfies album as proxy (iOS face detection)
        case .people:
            let fetch = photoLibrary.fetchResult(for: .selfies)
            fetchResult = fetch
            totalCount = fetch?.count ?? 0
            isLoading = false

        // Vision-backed categories — from persisted tags
        case .documents, .landscapes:
            let found = tagsVM.photosForCategory(category, photoLibrary: photoLibrary)
            assets = found
            totalCount = found.count
            isLoading = false

        case .duplicates, .aiSearch:
            isLoading = false
        }
    }

    // MARK: - AI Search

    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        isSearching = true

        let availableTags = tagsVM.availableTags
        let response = await GrokService.shared.processCommand(
            searchText,
            photoLibrary: photoLibrary,
            availableTags: availableTags
        )

        switch response.action {
        case .searchByTags(let tags):
            assets = tagsVM.search(tags: tags, photoLibrary: photoLibrary)
        default:
            // Direct tag match as fallback
            assets = tagsVM.search(tags: [searchText], photoLibrary: photoLibrary)
        }

        totalCount = assets.count
        isSearching = false
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
