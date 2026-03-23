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

            SettingsTab(tagsVM: tagsVM)
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape")
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
                        NeuralDashboard()

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
    @State private var selectedSearchIndex: Int?

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
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                ProgressView().tint(.purple).scaleEffect(0.7)
                                Text("Escaneando... \(Int(progress * 100))% (\(tagsVM.scannedCount)/\(tagsVM.totalCount))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Text("\(tagsVM.recentDescriptions.count) descripciones recientes")
                                .font(.system(size: 9)).foregroundStyle(.purple.opacity(0.5))
                        }
                    } else if tagsVM.scannedCount > 0 {
                        HStack(spacing: 6) {
                            Text("\(tagsVM.scannedCount) fotos indexadas")
                                .font(.caption2).foregroundStyle(.secondary)
                            if tagsVM.scannedCount < tagsVM.totalCount {
                                Text("· indexando en background...")
                                    .font(.caption2).foregroundStyle(.purple.opacity(0.6))
                            }
                        }
                    }

                    if !aiMessage.isEmpty {
                        Text(aiMessage)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                    }

                    // Results
                    if assets.isEmpty && searchText.isEmpty {
                        // Live indexing feed — always show when scanning
                        if case .scanning = tagsVM.state {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("INDEXANDO EN VIVO")
                                    .font(.caption2.bold())
                                    .kerning(2)
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 20)

                                if tagsVM.recentDescriptions.isEmpty {
                                    Text("Esperando primeras descripciones...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                } else {
                                    ScrollView(showsIndicators: false) {
                                        VStack(spacing: 10) {
                                            ForEach(0..<tagsVM.recentDescriptions.count, id: \.self) { i in
                                                let (desc, thumb) = tagsVM.recentDescriptions[i]
                                                HStack(spacing: 10) {
                                                    if let img = thumb {
                                                        Image(uiImage: img)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 50, height: 50)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    }
                                                    Text(desc)
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.9))
                                                        .lineLimit(3)
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 20)
                                            }
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
                        Text("\(assets.count) resultados")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 1) {
                                ForEach(0..<assets.count, id: \.self) { index in
                                    PhotoGridCell(asset: assets[index])
                                        .onTapGesture { selectedSearchIndex = index }
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
            .fullScreenCover(item: $selectedSearchIndex) { index in
                PhotoViewer(
                    initialIndex: index,
                    fetchResult: nil,
                    assets: assets
                )
                .environmentObject(photoLibrary)
            }
        }
    }

    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        isSearching = true
        aiMessage = ""

        let availableTags = tagsVM.availableTags
        let response = await GrokService.shared.processCommand(
            searchText,
            photoLibrary: photoLibrary,
            availableTags: availableTags
        )

        withAnimation { aiMessage = response.message }

        switch response.action {
        case .searchByTags(let tags):
            assets = tagsVM.search(tags: tags, photoLibrary: photoLibrary)
        case .searchByLocation(let place):
            assets = await tagsVM.searchByLocation(place: place, photoLibrary: photoLibrary)
        case .createAlbum(let albumName, let tags):
            assets = tagsVM.search(tags: tags, photoLibrary: photoLibrary)
            if !assets.isEmpty {
                try? await photoLibrary.createAlbum(name: albumName, assets: assets)
                withAnimation { aiMessage = "Álbum \"\(albumName)\" creado con \(assets.count) fotos" }
            }
        default:
            assets = tagsVM.search(tags: [searchText], photoLibrary: photoLibrary)
        }

        isSearching = false
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @ObservedObject private var debugLog = DebugLogger.shared

    private var indexProgress: Double {
        guard tagsVM.totalCount > 0 else { return 0 }
        return Double(tagsVM.scannedCount) / Double(tagsVM.totalCount)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FotifyTheme.meshGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // Indexing status card
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "brain")
                                    .font(.title2)
                                    .foregroundStyle(.purple)
                                Text("Indexación IA")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                statusBadge
                            }

                            // Progress bar
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: indexProgress)
                                    .tint(.purple)

                                HStack {
                                    Text("\(tagsVM.scannedCount) / \(tagsVM.totalCount) fotos")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(indexProgress * 100))%")
                                        .font(.caption.bold()).foregroundStyle(.purple)
                                }
                            }

                            // Stats grid
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                statCard(label: "Indexadas", value: "\(tagsVM.scannedCount)", icon: "checkmark.circle", color: .green)
                                statCard(label: "Pendientes", value: "\(max(0, tagsVM.totalCount - tagsVM.scannedCount))", icon: "clock", color: .orange)
                                statCard(label: "Total fotos", value: "\(photoLibrary.photoCount)", icon: "photo", color: .blue)
                                statCard(label: "Modelo IA", value: "Llama 4 Scout", icon: "sparkles", color: .purple)
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)

                        // Library stats card
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                Text("Biblioteca")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                statCard(label: "Fotos", value: "\(photoLibrary.photoCount)", icon: "photo", color: .blue)
                                statCard(label: "Capturas", value: "\(photoLibrary.screenshotCount)", icon: "rectangle.dashed", color: .orange)
                                statCard(label: "Videos", value: "\(photoLibrary.videosCount)", icon: "video", color: .cyan)
                                statCard(label: "Favoritos", value: "\(photoLibrary.favoritesCount)", icon: "heart.fill", color: .red)
                                statCard(label: "Selfies", value: "\(photoLibrary.selfiesCount)", icon: "person.crop.square", color: .indigo)
                                statCard(label: "Live Photos", value: "\(photoLibrary.livePhotosCount)", icon: "camera.viewfinder", color: .mint)
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)

                        // Recent descriptions
                        if !tagsVM.recentDescriptions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "text.bubble")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                    Text("Últimas descripciones")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Spacer()
                                }

                                ForEach(0..<tagsVM.recentDescriptions.count, id: \.self) { i in
                                    let (desc, thumb) = tagsVM.recentDescriptions[i]
                                    HStack(spacing: 12) {
                                        if let img = thumb {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 50, height: 50)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.8))
                                            .lineLimit(3)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .padding(.horizontal, 16)
                        }

                        // Debug Console
                        if Config.debugMode {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "terminal")
                                        .font(.title2)
                                        .foregroundStyle(.yellow)
                                    Text("Consola Debug")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Button("Limpiar") {
                                        DebugLogger.shared.clear()
                                    }
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                                }

                                if DebugLogger.shared.logs.isEmpty {
                                    Text("Sin logs todavía...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(DebugLogger.shared.logs) { entry in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(entry.category)
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundStyle(logColor(entry.category))
                                                .frame(width: 50, alignment: .leading)
                                            Text(entry.message)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .lineLimit(4)
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .padding(.horizontal, 16)
                        }

                        // App info
                        VStack(spacing: 8) {
                            Text("Fotify v1.6")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("IA: Llama 4 Scout via Groq")
                                .font(.caption2).foregroundStyle(.secondary)
                            if Config.debugMode {
                                Text("DEBUG MODE")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    private var statusBadge: some View {
        Group {
            if case .scanning = tagsVM.state {
                HStack(spacing: 4) {
                    ProgressView().tint(.purple).scaleEffect(0.6)
                    Text("Indexando")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.purple.opacity(0.2))
                .clipShape(Capsule())
                .foregroundStyle(.purple)
            } else if tagsVM.scannedCount >= tagsVM.totalCount && tagsVM.totalCount > 0 {
                Text("Completo")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.green)
            } else if tagsVM.scannedCount > 0 {
                Text("Parcial")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func logColor(_ category: String) -> Color {
        switch category {
        case "INDEX": return .cyan
        case "SEARCH": return .green
        case "GROQ": return .purple
        case "GPS": return .orange
        default: return .white
        }
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
