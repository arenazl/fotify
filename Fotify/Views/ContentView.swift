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

// MARK: - Glass Card Modifier

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
    @State private var neuralPulse: CGFloat = 1.0
    @State private var selectedModule: AppModule = .dashboard
    @State private var aiCommand: String = ""
    @State private var isProcessingCommand = false

    enum AppModule: Int, CaseIterable {
        case dashboard = 0
        case photos = 1
        case cleanup = 2
    }

    var body: some View {
        Group {
            switch photoLibrary.authorizationStatus {
            case .notDetermined:
                PermissionRequestView()
            case .authorized, .limited:
                mainAppView
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

    // MARK: - Main App

    private var mainAppView: some View {
        ZStack {
            FotifyTheme.meshGradient
                .ignoresSafeArea()
                .hueRotation(.degrees(neuralPulse * 10))

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 20)

                Spacer()

                // Dynamic Module
                ZStack {
                    switch selectedModule {
                    case .dashboard:
                        NeuralDashboard()
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    case .photos:
                        PhotoMeshView()
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    case .cleanup:
                        CleanupView()
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .animation(.spring(duration: 0.5), value: selectedModule)

                Spacer()

                neuralOrbView
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                neuralPulse = 1.5
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("FOTIFY")
                    .font(.system(size: 12, weight: .black))
                    .kerning(4)
                    .foregroundColor(Color.blue.opacity(0.8))
                Text("Cortex v.26")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(.white)
            }
            Spacer()

            // Real stats
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("\(photoLibrary.photoCount) fotos")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("\(photoLibrary.screenshotCount) capturas")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.title2)
                .symbolEffect(.variableColor.iterative.reversing)
                .padding(.leading, 12)
        }
        .padding(.horizontal, 30)
    }

    // MARK: - Neural Orb (Grok Input)

    private var neuralOrbView: some View {
        VStack(spacing: 25) {
            // Module selector pills
            HStack(spacing: 12) {
                ForEach(AppModule.allCases, id: \.rawValue) { module in
                    Button {
                        withAnimation(.spring(duration: 0.4)) {
                            selectedModule = module
                        }
                    } label: {
                        Text(moduleName(module))
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedModule == module ? .white.opacity(0.15) : .clear)
                            .clipShape(Capsule())
                            .foregroundStyle(selectedModule == module ? .white : .secondary)
                    }
                }
            }

            // Grok command input
            HStack {
                TextField("Hablá con Grok...", text: $aiCommand)
                    .padding(.horizontal, 25)
                    .frame(height: 60)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                    .onSubmit {
                        Task { await processGrokCommand() }
                    }

                Button(action: { Task { await processGrokCommand() } }) {
                    ZStack {
                        Circle()
                            .fill(.linearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 60, height: 60)
                            .shadow(color: .purple.opacity(0.5), radius: 20)

                        if isProcessingCommand {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(aiCommand.isEmpty || isProcessingCommand)
            }
            .padding(.horizontal, 30)

            // Pulse indicator
            Circle()
                .fill(.blue)
                .frame(width: 4, height: 4)
                .shadow(color: .blue, radius: 10)
                .scaleEffect(neuralPulse)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Helpers

    private func moduleName(_ module: AppModule) -> String {
        switch module {
        case .dashboard: "CORTEX"
        case .photos: "MESH"
        case .cleanup: "PURGE"
        }
    }

    private func processGrokCommand() async {
        guard !aiCommand.isEmpty else { return }
        isProcessingCommand = true
        let command = aiCommand
        aiCommand = ""

        // Send to Grok for interpretation
        let response = await GrokService.shared.processCommand(command, photoLibrary: photoLibrary)

        // Handle Grok's response
        switch response.action {
        case .showScreenshots, .showDuplicates:
            withAnimation { selectedModule = .cleanup }
        case .showPhotos:
            withAnimation { selectedModule = .photos }
        case .tagPhotos:
            withAnimation { selectedModule = .dashboard }
        case .chat, .none:
            break
        }

        isProcessingCommand = false
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
