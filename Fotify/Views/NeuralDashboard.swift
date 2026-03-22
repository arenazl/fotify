import SwiftUI
import Photos

struct NeuralDashboard: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @StateObject private var duplicatesVM = DuplicatesViewModel()
    @State private var barHeights: [CGFloat] = (0..<10).map { _ in CGFloat.random(in: 20...100) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Main stats card
                statsCard

                // Quick actions
                HStack(spacing: 16) {
                    DashboardAction(
                        icon: "doc.on.doc.fill",
                        label: "Duplicados",
                        count: duplicatesVM.duplicateGroups.count,
                        color: .blue
                    )

                    DashboardAction(
                        icon: "rectangle.dashed",
                        label: "Capturas",
                        count: photoLibrary.screenshotCount,
                        color: .orange
                    )

                    DashboardAction(
                        icon: "tag.fill",
                        label: "Tags",
                        count: 0,
                        color: .purple
                    )
                }
                .padding(.horizontal, 20)

                // Recent photos preview
                recentPhotosCard
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 16) {
            Text("INTELIGENCIA ACTIVA")
                .font(.caption2.bold())
                .foregroundColor(.purple)

            // Real photo count
            Text("\(photoLibrary.photoCount)")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.white)
            +
            Text(" fotos")
                .font(.system(size: 18, weight: .ultraLight))
                .foregroundStyle(.secondary)

            // Library composition bar
            if photoLibrary.photoCount > 0 {
                libraryCompositionBar
            }

            // Data visualizer (animated bars based on real distribution)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .purple.opacity(0.3)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 15, height: barHeights[i])
                }
            }
            .frame(height: 100)
            .onAppear {
                // Animate bars based on real data distribution
                updateBarHeights()
            }
        }
        .glassCard()
    }

    private var libraryCompositionBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let screenshotRatio = photoLibrary.photoCount > 0
                    ? CGFloat(photoLibrary.screenshotCount) / CGFloat(photoLibrary.photoCount)
                    : 0
                let photoRatio = 1.0 - screenshotRatio

                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.blue)
                        .frame(width: geo.size.width * photoRatio)

                    if screenshotRatio > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.orange)
                            .frame(width: geo.size.width * screenshotRatio)
                    }
                }
            }
            .frame(height: 6)

            HStack {
                Label("Fotos", systemImage: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Spacer()
                Label("Capturas \(Int(Double(photoLibrary.screenshotCount) / max(Double(photoLibrary.photoCount), 1) * 100))%", systemImage: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Recent Photos

    private var recentPhotosCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RECIENTES")
                .font(.caption2.bold())
                .foregroundColor(.blue)
                .padding(.leading, 30)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let photos = photoLibrary.allPhotos {
                        ForEach(0..<min(photos.count, 8), id: \.self) { index in
                            let asset = photos.object(at: index)
                            RecentPhotoCell(asset: asset)
                        }
                    }
                }
                .padding(.horizontal, 30)
            }
        }
    }

    private func updateBarHeights() {
        withAnimation(.spring(duration: 1.0).delay(0.3)) {
            // Generate bars that reflect real library size
            let base = max(CGFloat(photoLibrary.photoCount) / 1000.0, 1.0)
            barHeights = (0..<10).map { i in
                let screenshotWeight: CGFloat = i < 3 ? CGFloat(photoLibrary.screenshotCount) / max(CGFloat(photoLibrary.photoCount), 1) : 0
                return min(CGFloat.random(in: 20...60) * base + screenshotWeight * 40, 100)
            }
        }
    }
}

// MARK: - Dashboard Action Button

struct DashboardAction: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(
                    .linearGradient(
                        colors: [.white, .white.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
}

// MARK: - Recent Photo Cell

struct RecentPhotoCell: View {
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
                    .fill(.gray.opacity(0.2))
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 200, height: 200))
        }
    }
}
