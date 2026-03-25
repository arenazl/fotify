import SwiftUI
import Photos

enum GridSize: String, CaseIterable {
    case small, medium, large

    var columnCount: Int {
        switch self {
        case .small: 5
        case .medium: 3
        case .large: 2
        }
    }

    var label: String {
        switch self {
        case .small: "Chico"
        case .medium: "Medio"
        case .large: "Grande"
        }
    }

    var icon: String {
        switch self {
        case .small: "square.grid.4x3.fill"
        case .medium: "square.grid.3x3.fill"
        case .large: "square.grid.2x2.fill"
        }
    }
}

enum GroupBy: String, CaseIterable {
    case none, week, month

    var label: String {
        switch self {
        case .none: "Todas"
        case .week: "Semana"
        case .month: "Mes"
        }
    }
}

struct CategoryDetailView: View {
    let category: PhotoCategory
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @State private var assets: [PHAsset] = []
    @State private var fetchResult: PHFetchResult<PHAsset>?
    @State private var totalCount: Int = 0
    @State private var isLoading = true
    @State private var selectedIndex: Int?
    @State private var gridSize: GridSize = .medium
    @State private var groupBy: GroupBy = .none
    @State private var faceMatchAsset: PHAsset?
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirmation = false
    var folderManager: FolderManager?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1), count: gridSize.columnCount)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        .toolbarBackground(.black.opacity(0.8), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: category.icon)
                        .font(.subheadline)
                        .foregroundStyle(category.color)
                    Text(category.label)
                        .font(.headline)
                    Text("\(totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if isSelecting {
                        Button {
                            // Select all
                            if let fetch = fetchResult {
                                for i in 0..<fetch.count { selectedIds.insert(fetch.object(at: i).localIdentifier) }
                            } else {
                                assets.forEach { selectedIds.insert($0.localIdentifier) }
                            }
                        } label: {
                            Text("Todo")
                                .font(.caption.bold())
                        }

                        if !selectedIds.isEmpty {
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                    Text("\(selectedIds.count)")
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            }
                        }

                        Button {
                            isSelecting = false
                            selectedIds.removeAll()
                        } label: {
                            Text("Listo")
                                .font(.caption.bold())
                        }
                    } else {
                        Button {
                            isSelecting = true
                        } label: {
                            Text("Seleccionar")
                                .font(.caption.bold())
                        }

                        Menu {
                            Section("Tamaño") {
                                ForEach(GridSize.allCases, id: \.self) { size in
                                    Button {
                                        withAnimation(.spring(duration: 0.3)) { gridSize = size }
                                    } label: {
                                        Label(size.label, systemImage: size.icon)
                                        if gridSize == size { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                            Section("Agrupar por") {
                                ForEach(GroupBy.allCases, id: \.self) { group in
                                    Button {
                                        withAnimation(.spring(duration: 0.3)) { groupBy = group }
                                    } label: {
                                        Label(group.label, systemImage: group == .none ? "square.grid.3x3" : group == .week ? "calendar" : "calendar.badge.clock")
                                        if groupBy == group { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedIndex) { index in
            PhotoViewer(
                initialIndex: index,
                fetchResult: fetchResult,
                assets: assets
            )
            .environmentObject(photoLibrary)
        }
        .confirmationDialog(
            "Eliminar \(selectedIds.count) fotos",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                Task {
                    guard let allPhotos = photoLibrary.allPhotos else { return }
                    var toDelete: [PHAsset] = []
                    for i in 0..<allPhotos.count {
                        let a = allPhotos.object(at: i)
                        if selectedIds.contains(a.localIdentifier) { toDelete.append(a) }
                    }
                    try? await photoLibrary.deleteAssets(toDelete)
                    selectedIds.removeAll()
                    isSelecting = false
                    await loadContent()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("iOS te pedirá confirmación. No se puede deshacer.")
        }
        .sheet(item: $faceMatchAsset) { asset in
            FaceMatchView(
                referenceAsset: asset,
                tagsVM: tagsVM,
                folderManager: folderManager ?? FolderManager()
            )
            .environmentObject(photoLibrary)
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

    // MARK: - Photo Grid (iOS Photos style)

    private var photoGrid: some View {
        ScrollView(showsIndicators: false) {
            if groupBy == .none {
                flatGrid
            } else {
                groupedGrid
            }
        }
    }

    private var flatGrid: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            if let fetch = fetchResult {
                ForEach(0..<min(fetch.count, 5000), id: \.self) { index in
                    let asset = fetch.object(at: index)
                    selectableCell(asset: asset, index: index)
                }
            } else {
                ForEach(0..<assets.count, id: \.self) { index in
                    let asset = assets[index]
                    selectableCell(asset: asset, index: index)
                }
            }
        }
    }

    private func selectableCell(asset: PHAsset, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoGridCell(asset: asset)

            if isSelecting {
                Image(systemName: selectedIds.contains(asset.localIdentifier) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIds.contains(asset.localIdentifier) ? .blue : .white.opacity(0.5))
                    .shadow(radius: 3)
                    .padding(4)
            }
        }
        .onTapGesture {
            if isSelecting {
                if selectedIds.contains(asset.localIdentifier) {
                    selectedIds.remove(asset.localIdentifier)
                } else {
                    selectedIds.insert(asset.localIdentifier)
                }
            } else if category == .people {
                faceMatchAsset = asset
            } else {
                selectedIndex = index
            }
        }
    }

    private var groupedGrid: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            let grouped = groupPhotos()
            ForEach(grouped, id: \.title) { group in
                Section {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(0..<group.assets.count, id: \.self) { i in
                            PhotoGridCell(asset: group.assets[i])
                                .onTapGesture {
                                    // Find global index for viewer
                                    selectedIndex = group.globalIndices[i]
                                }
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
            }
        }
    }

    private struct PhotoGroup: Hashable {
        let title: String
        let assets: [PHAsset]
        let globalIndices: [Int]

        func hash(into hasher: inout Hasher) { hasher.combine(title) }
        static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool { lhs.title == rhs.title }
    }

    private func groupPhotos() -> [PhotoGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")

        if groupBy == .month {
            formatter.dateFormat = "MMMM yyyy"
        } else {
            formatter.dateFormat = "'Semana del' d MMM"
        }

        var groups: [String: (assets: [PHAsset], indices: [Int])] = [:]
        var order: [String] = []

        let count: Int
        let assetAt: (Int) -> PHAsset

        if let fetch = fetchResult {
            count = min(fetch.count, 5000)
            assetAt = { fetch.object(at: $0) }
        } else {
            count = assets.count
            assetAt = { assets[$0] }
        }

        for i in 0..<count {
            let asset = assetAt(i)
            guard let date = asset.creationDate else { continue }

            let key: String
            if groupBy == .month {
                key = formatter.string(from: date)
            } else {
                let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
                key = formatter.string(from: weekStart)
            }

            if groups[key] == nil {
                groups[key] = ([], [])
                order.append(key)
            }
            groups[key]?.assets.append(asset)
            groups[key]?.indices.append(i)
        }

        return order.compactMap { key in
            guard let group = groups[key] else { return nil }
            return PhotoGroup(title: key.capitalized, assets: group.assets, globalIndices: group.indices)
        }
    }

    // MARK: - Load Content

    private func loadContent() async {
        switch category {
        case .recents, .screenshots, .favorites, .videos, .selfies:
            let fetch = photoLibrary.fetchResult(for: category)
            fetchResult = fetch
            totalCount = fetch?.count ?? 0

        case .places:
            let filtered = await photoLibrary.filteredAssets(for: category, limit: 300)
            assets = filtered
            totalCount = filtered.count

        case .people:
            let found = tagsVM.photosForPeople(photoLibrary: photoLibrary)
            assets = found
            totalCount = found.count

        case .documents, .landscapes:
            let found = tagsVM.photosForCategory(category, photoLibrary: photoLibrary)
            assets = found
            totalCount = found.count

        case .personal:
            // Show all photos from tagged persons
            if let fm = folderManager {
                let personFolders = fm.folders.filter { $0.isPerson }
                let allIds = Set(personFolders.flatMap { $0.matchedAssetIds })
                if let allPhotos = photoLibrary.allPhotos {
                    for i in 0..<allPhotos.count {
                        let asset = allPhotos.object(at: i)
                        if allIds.contains(asset.localIdentifier) {
                            assets.append(asset)
                        }
                    }
                }
                totalCount = assets.count
            }

        case .duplicates:
            break
        }

        isLoading = false
    }
}

// MARK: - Int Identifiable for fullScreenCover

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

// MARK: - Photo Grid Cell (iOS Photos style)

struct PhotoGridCell: View {
    let asset: PHAsset
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.1))
                }

                // Video indicator
                if asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text(asset.duration.formatted)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                    }
                }

                // Live Photo indicator
                if asset.mediaSubtypes.contains(.photoLive) {
                    VStack {
                        HStack {
                            Image(systemName: "livephoto")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                            Spacer()
                        }
                        .padding(4)
                        Spacer()
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 200, height: 200))
        }
    }
}

// MARK: - Duration Formatter

extension TimeInterval {
    var formatted: String {
        let mins = Int(self) / 60
        let secs = Int(self) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Photo Viewer (fullscreen with swipe)

struct PhotoViewer: View {
    let initialIndex: Int
    let fetchResult: PHFetchResult<PHAsset>?
    let assets: [PHAsset]
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int = 0
    @State private var fullImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    private var totalPhotos: Int {
        fetchResult?.count ?? assets.count
    }

    private func asset(at index: Int) -> PHAsset {
        if let fetch = fetchResult {
            return fetch.object(at: index)
        }
        return assets[index]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(0..<min(totalPhotos, 5000), id: \.self) { index in
                    FullPhotoView(asset: asset(at: index))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("\(currentIndex + 1) / \(totalPhotos)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    // Share button
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 50)
                Spacer()
            }
        }
        .onAppear {
            currentIndex = initialIndex
        }
    }
}

// MARK: - Full Photo View (single photo in viewer)

struct FullPhotoView: View {
    let asset: PHAsset
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation(.spring(duration: 0.3)) {
                                        scale = 1.0
                                        lastScale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                            } else {
                                scale = 3.0
                                lastScale = 3.0
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.fullImage(for: asset)
        }
    }
}
