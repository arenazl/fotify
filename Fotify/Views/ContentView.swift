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
    @StateObject private var folderManager = FolderManager()

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
            CortexTab(tagsVM: tagsVM, folderManager: folderManager)
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

            SettingsTab(tagsVM: tagsVM)
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape")
                }
        }
        .tint(.purple)
        .task {
            // Log device state
            DebugLogger.shared.log("APP", "=== FOTIFY v1.7.9 INICIO ===")
            DebugLogger.shared.log("APP", "Total fotos: \(photoLibrary.photoCount)")
            DebugLogger.shared.log("APP", "Capturas: \(photoLibrary.screenshotCount)")
            DebugLogger.shared.log("APP", "Favoritos: \(photoLibrary.favoritesCount)")
            DebugLogger.shared.log("APP", "Videos: \(photoLibrary.videosCount)")
            DebugLogger.shared.log("APP", "Selfies: \(photoLibrary.selfiesCount)")
            DebugLogger.shared.log("APP", "Live Photos: \(photoLibrary.livePhotosCount)")

            tagsVM.loadPersistedTags()
            DebugLogger.shared.log("APP", "Tags cargados: \(tagsVM.scannedCount)")
            DebugLogger.shared.log("APP", "Schema: \(TagsViewModel.schemaVersion)")
            DebugLogger.shared.log("APP", "Carpetas: \(folderManager.folders.count)")
            folderManager.folders.forEach { f in
                DebugLogger.shared.log("APP", "  📁 \(f.name) (\(f.searchTerms.joined(separator: ", ")))")
            }

            // Refresh dynamic folders
            folderManager.refreshFolders(tagsVM: tagsVM, photoLibrary: photoLibrary)
            DebugLogger.shared.log("APP", "Carpetas actualizadas")

            // Continue indexing
            DebugLogger.shared.log("APP", "Iniciando scan background...")
            await tagsVM.backgroundScan(photoLibrary: photoLibrary)
            DebugLogger.shared.log("APP", "Scan completo. Indexadas: \(tagsVM.scannedCount)")

            // Refresh again
            folderManager.refreshFolders(tagsVM: tagsVM, photoLibrary: photoLibrary)
        }
    }
}

// MARK: - Cortex Tab (Dashboard + Categories)

struct CortexTab: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @ObservedObject var folderManager: FolderManager
    @State private var showCreateFolder = false

    var body: some View {
        NavigationStack {
            ZStack {
                FotifyTheme.meshGradient
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        cortexHeader

                        NeuralDashboard(folderManager: folderManager, showCreateFolder: $showCreateFolder)

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
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .debugToolbar()
            .navigationDestination(for: PhotoCategory.self) { category in
                CategoryDetailView(category: category, tagsVM: tagsVM, folderManager: folderManager)
            }
            .navigationDestination(for: CustomFolder.self) { folder in
                CustomFolderDetailView(folder: folder, tagsVM: tagsVM)
            }
            .sheet(isPresented: $showCreateFolder) {
                CreateFolderView(tagsVM: tagsVM, folderManager: folderManager)
            }
        }
    }

    private var cortexHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.aperture")
                .font(.title2)
                .foregroundStyle(.purple)

            Text("Fotify")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)

            Text("v1.7.9")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.secondary)

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
            .debugToolbar()
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
            .debugToolbar()
        }
    }
}

// MARK: - Search Tab (AI Search)

// MARK: - Custom Folder Detail View

struct CustomFolderDetailView: View {
    let folder: CustomFolder
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @State private var assets: [PHAsset] = []
    @State private var isLoading = true
    @State private var selectedIndex: Int?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Cargando...").tint(.white)
            } else if assets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Sin fotos en esta carpeta")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(0..<assets.count, id: \.self) { index in
                            PhotoGridCell(asset: assets[index])
                                .onTapGesture { selectedIndex = index }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.8), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.subheadline).foregroundStyle(.purple)
                    Text(folder.name).font(.headline)
                    if !assets.isEmpty {
                        Text("\(assets.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedIndex) { index in
            PhotoViewer(initialIndex: index, fetchResult: nil, assets: assets)
                .environmentObject(photoLibrary)
        }
        .task {
            if !folder.matchedAssetIds.isEmpty {
                // Face match folders: use saved asset IDs directly
                guard let allPhotos = photoLibrary.allPhotos else { isLoading = false; return }
                let idSet = Set(folder.matchedAssetIds)
                for i in 0..<allPhotos.count {
                    let asset = allPhotos.object(at: i)
                    if idSet.contains(asset.localIdentifier) {
                        assets.append(asset)
                    }
                }
            } else if !folder.searchTerms.isEmpty {
                // Search-based folders: use tag search
                assets = tagsVM.searchByTerms(folder.searchTerms, photoLibrary: photoLibrary)
            }
            isLoading = false
        }
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
                            Text("Fotify v1.7.9 (build 8)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("IA: Llama 4 Scout via Groq")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("Schema: \(TagsViewModel.schemaVersion)")
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
