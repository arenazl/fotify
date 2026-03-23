import SwiftUI
import Photos

// MARK: - iOS 26 DESIGN SYSTEM

enum FotifyTheme {
    static let meshGradient = MeshGradient(width: 3, height: 3, points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.5, 0.5], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1]
    ], colors: [
        .black, .black, .indigo,
        .black, .purple, .black,
        .blue, .black, .black
    ])

    static let cardBackground = Color.white.opacity(0.03)
    static let cardBorder = Color.white.opacity(0.05)
    static let cardRadius: CGFloat = 40
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(30)
            .background(FotifyTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: FotifyTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FotifyTheme.cardRadius)
                    .stroke(FotifyTheme.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}

// MARK: - MAIN CONTENT VIEW

struct ContentView: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @StateObject private var tagsVM = TagsViewModel()

    var body: some View {
        Group {
            switch photoLibrary.authorizationStatus {
            case .notDetermined:
                PermissionRequestView()
            case .authorized, .limited:
                mainTabView
            case .denied, .restricted:
                PermissionDeniedView()
            @unknown default:
                PermissionRequestView()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await photoLibrary.checkAuthorization()
        }
    }

    // MARK: - Tab View (iOS native bottom tabs)

    private var mainTabView: some View {
        TabView {
            CortexTab(tagsVM: tagsVM)
                .tabItem {
                    Label("Inicio", systemImage: "square.grid.2x2.fill")
                }

            MeshTab()
                .tabItem {
                    Label("Biblioteca", systemImage: "photo.on.rectangle.angled")
                }

            PurgeTab()
                .tabItem {
                    Label("Limpieza", systemImage: "trash.circle")
                }

            SearchTab(tagsVM: tagsVM)
                .tabItem {
                    Label("Buscar", systemImage: "sparkle.magnifyingglass")
                }
        }
        .tint(.purple)
        .task {
            tagsVM.loadPersistedTags()
            await tagsVM.backgroundScan(photoLibrary: photoLibrary)
        }
    }
}

// MARK: - Cortex Tab (Dashboard + Categories)

struct CortexTab: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                FotifyTheme.meshGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        cortexHeader

                        // Categories grid
                        NeuralDashboard { category in }

                        // Scan status
                        if case .scanning(let progress) = tagsVM.state {
                            HStack(spacing: 8) {
                                ProgressView().tint(.purple).scaleEffect(0.8)
                                Text("Indexando fotos... \(Int(progress * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("FOTIFY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: PhotoCategory.self) { category in
                CategoryDetailView(category: category, tagsVM: tagsVM)
            }
        }
    }

    private var cortexHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cortex v.32")
                    .font(.system(size: 28, weight: .thin))
                    .foregroundColor(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("\(photoLibrary.photoCount) fotos")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("\(photoLibrary.screenshotCount) capturas")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Mesh Tab (Photo Library)

struct MeshTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                FotifyTheme.meshGradient
                    .ignoresSafeArea()
                PhotoMeshView()
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

// MARK: - Purge Tab (Cleanup)

struct PurgeTab: View {
    var body: some View {
        NavigationStack {
            ZStack {
                FotifyTheme.meshGradient
                    .ignoresSafeArea()
                CleanupView()
            }
            .navigationTitle("Limpieza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

// MARK: - Search Tab (AI Search)

struct SearchTab: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @State private var searchText: String = ""
    @State private var assets: [PHAsset] = []
    @State private var isSearching = false
    @State private var aiMessage: String = ""
    @State private var debugTags: [String] = []
    @State private var debugMatchedTags: [[String]] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                FotifyTheme.meshGradient
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(.purple)
                        TextField("Buscá: perro, playa, comida...", text: $searchText)
                            .onSubmit { Task { await performSearch() } }
                        if isSearching {
                            ProgressView().tint(.purple).scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                    // Status
                    if case .scanning(let progress) = tagsVM.state {
                        HStack(spacing: 8) {
                            ProgressView().tint(.purple).scaleEffect(0.7)
                            Text("Escaneando... \(Int(progress * 100))%")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else if tagsVM.scannedCount > 0 {
                        Text("\(tagsVM.scannedCount) fotos indexadas")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    if !aiMessage.isEmpty {
                        Text(aiMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                    }

                    // Results
                    if assets.isEmpty && searchText.isEmpty {
                        // Show live indexing feed
                        if !tagsVM.recentDescriptions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("INDEXANDO EN VIVO")
                                    .font(.caption2.bold())
                                    .kerning(2)
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 20)

                                ScrollView(showsIndicators: false) {
                                    VStack(spacing: 8) {
                                        ForEach(0..<tagsVM.recentDescriptions.count, id: \.self) { i in
                                            let (desc, thumb) = tagsVM.recentDescriptions[i]
                                            HStack(spacing: 10) {
                                                if let img = thumb {
                                                    Image(uiImage: img)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 44, height: 44)
                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                Text(desc)
                                                    .font(.caption2)
                                                    .foregroundStyle(.white.opacity(0.8))
                                                    .lineLimit(2)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                }
                            }
                        } else {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.purple.opacity(0.5))
                                Text("Escribí qué querés buscar")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Usa lenguaje natural: \"fotos de comida\", \"playa\", \"mi perro\"")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            Spacer()
                        }
                    } else if assets.isEmpty && !searchText.isEmpty && !isSearching {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Sin resultados para \"\(searchText)\"")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(assets.count) resultados")
                                .font(.caption2).foregroundStyle(.secondary)
                            if !debugTags.isEmpty {
                                Text("Tags buscados: \(debugTags.joined(separator: ", "))")
                                    .font(.caption2).foregroundStyle(.purple)
                            }
                        }
                        .padding(.horizontal, 20)

                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(0..<assets.count, id: \.self) { index in
                                    VStack(spacing: 2) {
                                        CategoryPhotoCell(asset: assets[index])
                                        if index < debugMatchedTags.count {
                                            Text(debugMatchedTags[index].prefix(4).joined(separator: ", "))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.yellow)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Buscar IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        isSearching = true
        aiMessage = ""
        debugTags = []
        debugMatchedTags = []

        let availableTags = tagsVM.availableTags
        let response = await GrokService.shared.processCommand(
            searchText,
            photoLibrary: photoLibrary,
            availableTags: availableTags
        )

        withAnimation { aiMessage = response.message }

        let searchTags: [String]
        switch response.action {
        case .searchByTags(let tags):
            searchTags = tags
        case .createAlbum(let albumName, let tags):
            searchTags = tags
            debugTags = tags
            let result = tagsVM.searchWithDebug(tags: tags, photoLibrary: photoLibrary)
            assets = result.assets
            debugMatchedTags = result.matchedTags
            // Create the album
            if !assets.isEmpty {
                try? await photoLibrary.createAlbum(name: albumName, assets: assets)
                withAnimation { aiMessage = "Álbum \"\(albumName)\" creado con \(assets.count) fotos" }
            }
            isSearching = false
            return
        default:
            searchTags = [searchText]
        }

        debugTags = searchTags
        let result = tagsVM.searchWithDebug(tags: searchTags, photoLibrary: photoLibrary)
        assets = result.assets
        debugMatchedTags = result.matchedTags

        isSearching = false
    }
}

// MARK: - Permission Views

struct PermissionRequestView: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            FotifyTheme.meshGradient
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.1))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulse)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                }

                Text("FOTIFY")
                    .font(.system(size: 14, weight: .black))
                    .kerning(6)
                    .foregroundColor(.blue.opacity(0.8))

                Text("Necesita acceso a tus fotos")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(.white)

                Text("Para organizar, detectar duplicados y etiquetar automáticamente con IA.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Task { await photoLibrary.requestAuthorization() }
                } label: {
                    Text("PERMITIR ACCESO")
                        .font(.system(size: 14, weight: .bold))
                        .kerning(2)
                        .foregroundColor(.black)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 50)
                        .background(.white)
                        .clipShape(Capsule())
                        .shadow(color: .white.opacity(0.3), radius: 20)
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulse = 1.3
            }
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            FotifyTheme.meshGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                Text("Acceso denegado")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(.white)

                Text("Abrí Ajustes → Fotify → Fotos y seleccioná \"Acceso completo\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button("ABRIR AJUSTES") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .kerning(2)
                .foregroundColor(.black)
                .padding(.vertical, 20)
                .padding(.horizontal, 50)
                .background(.white)
                .clipShape(Capsule())

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
