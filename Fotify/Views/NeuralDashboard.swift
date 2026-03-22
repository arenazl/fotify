import SwiftUI
import Photos

struct NeuralDashboard: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Categories grid
                categoriesGrid

                // Timeline preview
                timelinePreview
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Categories Grid

    private var categoriesGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EXPLORAR")
                .font(.caption2.bold())
                .kerning(2)
                .foregroundStyle(.blue)
                .padding(.leading, 24)

            LazyVGrid(columns: columns, spacing: 14) {
                CategoryCard(
                    icon: "clock.arrow.circlepath",
                    label: "Timeline",
                    count: photoLibrary.photoCount,
                    color: .blue
                )

                CategoryCard(
                    icon: "map",
                    label: "Lugares",
                    count: nil,
                    color: .green
                )

                CategoryCard(
                    icon: "person.2.fill",
                    label: "Personas",
                    count: nil,
                    color: .pink
                )

                CategoryCard(
                    icon: "rectangle.dashed",
                    label: "Capturas",
                    count: photoLibrary.screenshotCount,
                    color: .orange
                )

                CategoryCard(
                    icon: "doc.on.doc.fill",
                    label: "Duplicados",
                    count: nil,
                    color: .purple
                )

                CategoryCard(
                    icon: "heart.fill",
                    label: "Favoritos",
                    count: nil,
                    color: .red
                )

                CategoryCard(
                    icon: "video.fill",
                    label: "Videos",
                    count: nil,
                    color: .cyan
                )

                CategoryCard(
                    icon: "person.crop.square",
                    label: "Selfies",
                    count: nil,
                    color: .indigo
                )

                CategoryCard(
                    icon: "camera.viewfinder",
                    label: "Live Photos",
                    count: nil,
                    color: .mint
                )

                CategoryCard(
                    icon: "doc.text.viewfinder",
                    label: "Documentos",
                    count: nil,
                    color: .brown
                )

                CategoryCard(
                    icon: "moon.stars.fill",
                    label: "Noche",
                    count: nil,
                    color: .indigo
                )

                CategoryCard(
                    icon: "tag.fill",
                    label: "Tags IA",
                    count: nil,
                    color: .purple
                )
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Timeline Preview

    private var timelinePreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TIMELINE")
                    .font(.caption2.bold())
                    .kerning(2)
                    .foregroundStyle(.blue)
                Spacer()
                Text("Ver todo →")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            if let photos = photoLibrary.allPhotos, photos.count > 0 {
                // Today
                timelineSection(title: "Hoy", assets: recentPhotos(from: photos, daysAgo: 0))

                // Yesterday
                timelineSection(title: "Ayer", assets: recentPhotos(from: photos, daysAgo: 1))

                // This week
                timelineSection(title: "Esta semana", assets: recentPhotos(from: photos, daysAgo: 7))
            }
        }
    }

    private func timelineSection(title: String, assets: [PHAsset]) -> some View {
        Group {
            if !assets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(title)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text("\(assets.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<min(assets.count, 10), id: \.self) { index in
                                TimelineThumbnail(asset: assets[index])
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
        }
    }

    private func recentPhotos(from fetchResult: PHFetchResult<PHAsset>, daysAgo: Int) -> [PHAsset] {
        let calendar = Calendar.current
        let now = Date()
        var result: [PHAsset] = []

        for i in 0..<min(fetchResult.count, 500) {
            let asset = fetchResult.object(at: i)
            guard let date = asset.creationDate else { continue }

            let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0

            if daysAgo == 0 && daysDiff == 0 {
                result.append(asset)
            } else if daysAgo == 1 && daysDiff == 1 {
                result.append(asset)
            } else if daysAgo == 7 && daysDiff >= 2 && daysDiff <= 7 {
                result.append(asset)
            }

            if result.count >= 20 { break }
        }
        return result
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let icon: String
    let label: String
    let count: Int?
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 90)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Timeline Thumbnail

struct TimelineThumbnail: View {
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
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 160, height: 160))
        }
    }
}
