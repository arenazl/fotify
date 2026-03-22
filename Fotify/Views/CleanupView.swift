import SwiftUI
import Photos

struct CleanupView: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @StateObject private var duplicatesVM = DuplicatesViewModel()
    @State var selectedTab: CleanupTab = .screenshots
    @State private var vaporizeProgress: CGFloat = 0.0

    var initialTab: CleanupTab?
    @State private var selectedScreenshots: Set<Int> = []
    @State private var showDeleteConfirmation = false
    @State private var isVaporizing = false

    enum CleanupTab: Hashable {
        case screenshots, duplicates
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                CleanupTabButton(
                    title: "CAPTURAS",
                    count: photoLibrary.screenshotCount,
                    isSelected: selectedTab == .screenshots,
                    color: .orange
                ) {
                    withAnimation { selectedTab = .screenshots }
                }

                CleanupTabButton(
                    title: "DUPLICADOS",
                    count: duplicatesVM.duplicateGroups.flatMap { $0 }.count,
                    isSelected: selectedTab == .duplicates,
                    color: .blue
                ) {
                    withAnimation { selectedTab = .duplicates }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Content
            switch selectedTab {
            case .screenshots:
                screenshotsContent
            case .duplicates:
                duplicatesContent
            }
        }
    }

    // MARK: - Screenshots Content

    private var screenshotsContent: some View {
        VStack(spacing: 20) {
            if photoLibrary.screenshotCount == 0 {
                cleanState(icon: "checkmark.circle", message: "Sin capturas detectadas")
            } else {
                // Vaporize circle
                vaporizeCircle(
                    count: selectedScreenshots.isEmpty ? photoLibrary.screenshotCount : selectedScreenshots.count,
                    label: selectedScreenshots.isEmpty ? "CAPTURAS DETECTADAS" : "SELECCIONADAS"
                )

                // Screenshot grid
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 8
                    ) {
                        if let screenshots = photoLibrary.screenshots {
                            ForEach(0..<screenshots.count, id: \.self) { index in
                                let asset = screenshots.object(at: index)
                                CleanupPhotoCell(
                                    asset: asset,
                                    isSelected: selectedScreenshots.contains(index)
                                )
                                .onTapGesture {
                                    toggleScreenshotSelection(index)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Vaporize button
                vaporizeButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Eliminar \(selectedScreenshots.isEmpty ? photoLibrary.screenshotCount : selectedScreenshots.count) capturas",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Vaporizar", role: .destructive) {
                Task { await vaporizeScreenshots() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("iOS te pedirá confirmación. No se puede deshacer.")
        }
        .onAppear {
            if let initialTab {
                selectedTab = initialTab
            }
        }
    }

    // MARK: - Duplicates Content

    private var duplicatesContent: some View {
        VStack(spacing: 20) {
            switch duplicatesVM.state {
            case .idle:
                vaporizeCircle(count: 0, label: "SIN ESCANEAR")

                Button {
                    Task {
                        await duplicatesVM.scanForDuplicates(photoLibrary: photoLibrary)
                    }
                } label: {
                    Text("ESCANEAR DUPLICADOS")
                        .font(.system(size: 14, weight: .bold))
                        .kerning(2)
                        .foregroundColor(.black)
                        .padding(.vertical, 18)
                        .padding(.horizontal, 40)
                        .background(.white)
                        .clipShape(Capsule())
                        .shadow(color: .white.opacity(0.3), radius: 20)
                }

            case .scanning(let progress):
                vaporizeCircle(
                    count: Int(progress * Double(photoLibrary.photoCount)),
                    label: "ANALIZANDO...",
                    progress: progress
                )

            case .done:
                if duplicatesVM.duplicateGroups.isEmpty {
                    cleanState(icon: "checkmark.circle", message: "Sin duplicados encontrados")
                } else {
                    vaporizeCircle(
                        count: duplicatesVM.duplicateGroups.flatMap { $0 }.count - duplicatesVM.duplicateGroups.count,
                        label: "DUPLICADOS ELIMINABLES"
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(Array(duplicatesVM.duplicateGroups.enumerated()), id: \.offset) { groupIdx, group in
                                DuplicateGroupCard(group: group, groupIndex: groupIdx)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private func vaporizeCircle(count: Int, label: String, progress: Double? = nil) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 2)
                .frame(width: 200, height: 200)

            Circle()
                .trim(from: 0, to: progress ?? vaporizeProgress)
                .stroke(
                    AngularGradient(
                        colors: [.blue, .purple, .blue],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if progress == nil {
                withAnimation(.spring(duration: 1.5)) {
                    vaporizeProgress = count > 0 ? min(CGFloat(count) / CGFloat(max(photoLibrary.photoCount, 1)), 1.0) : 0
                }
            }
        }
    }

    private func vaporizeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isVaporizing {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("VAPORIZAR")
                    .font(.system(size: 14, weight: .bold))
                    .kerning(2)
            }
            .foregroundColor(.black)
            .padding(.vertical, 18)
            .padding(.horizontal, 40)
            .background(.white)
            .clipShape(Capsule())
            .shadow(color: .white.opacity(0.3), radius: 20)
        }
        .disabled(isVaporizing)
        .padding(.bottom, 10)
    }

    private func cleanState(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func toggleScreenshotSelection(_ index: Int) {
        if selectedScreenshots.contains(index) {
            selectedScreenshots.remove(index)
        } else {
            selectedScreenshots.insert(index)
        }
    }

    private func vaporizeScreenshots() async {
        guard let screenshots = photoLibrary.screenshots else { return }
        isVaporizing = true

        let assetsToDelete: [PHAsset]
        if selectedScreenshots.isEmpty {
            // Delete all
            assetsToDelete = (0..<screenshots.count).map { screenshots.object(at: $0) }
        } else {
            assetsToDelete = selectedScreenshots.map { screenshots.object(at: $0) }
        }

        try? await photoLibrary.deleteAssets(assetsToDelete)
        selectedScreenshots.removeAll()
        vaporizeProgress = 0
        isVaporizing = false
    }
}

// MARK: - Cleanup Photo Cell

struct CleanupPhotoCell: View {
    let asset: PHAsset
    let isSelected: Bool
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? .blue : .white.opacity(0.05), lineWidth: isSelected ? 2 : 0.5)
            )

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(isSelected ? .blue : .white.opacity(0.5))
                .padding(6)
        }
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 150, height: 150))
        }
    }
}

// MARK: - Duplicate Group Card

struct DuplicateGroupCard: View {
    let group: [PHAsset]
    let groupIndex: Int
    @EnvironmentObject var photoLibrary: PhotoLibraryService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GRUPO \(groupIndex + 1)")
                    .font(.caption2.bold())
                    .kerning(1)
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(group.count) copias")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<group.count, id: \.self) { index in
                        MeshPhotoCell(asset: group[index])
                            .frame(width: 100, height: 100)
                    }
                }
            }
        }
        .padding(20)
        .background(FotifyTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(FotifyTheme.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Tab Button

struct CleanupTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
                .foregroundStyle(isSelected ? .white : .secondary)

                Rectangle()
                    .fill(isSelected ? color : .clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
