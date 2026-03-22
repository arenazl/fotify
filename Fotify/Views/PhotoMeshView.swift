import SwiftUI
import Photos

struct PhotoMeshView: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @StateObject private var tagsVM = TagsViewModel()
    @State private var groupedByMonth: [(String, [PHAsset])] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 30) {
                if isLoading {
                    ProgressView("Organizando fotos...")
                        .tint(.white)
                        .padding(.top, 40)
                } else if groupedByMonth.isEmpty {
                    emptyState
                } else {
                    // Tags quick filter (if classified)
                    if !tagsVM.tagGroups.isEmpty {
                        tagFilterBar
                    }

                    // Photo groups by month
                    ForEach(groupedByMonth, id: \.0) { month, assets in
                        monthSection(month: month, assets: assets)
                    }
                }
            }
            .padding(.top, 10)
        }
        .task {
            await groupPhotos()
        }
    }

    // MARK: - Tag Filter

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tagsVM.sortedTags.prefix(10), id: \.key) { tag, photos in
                    HStack(spacing: 6) {
                        Text(tag)
                            .font(.caption2.bold())
                        Text("\(photos.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.purple.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Month Section

    private func monthSection(month: String, assets: [PHAsset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(month.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                    .kerning(2)
                Spacer()
                Text("\(assets.count) fotos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if assets.count > 3 {
                    Text("IA: agrupar")
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.purple.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 24)

            // Horizontal gallery
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<min(assets.count, 20), id: \.self) { index in
                        MeshPhotoCell(asset: assets[index])
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 8)
        .background(FotifyTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(FotifyTheme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sin fotos disponibles")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }

    // MARK: - Group Logic

    private func groupPhotos() async {
        guard let allPhotos = photoLibrary.allPhotos else {
            isLoading = false
            return
        }

        var groups: [String: [PHAsset]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "es_AR")

        for i in 0..<allPhotos.count {
            let asset = allPhotos.object(at: i)
            let key = asset.creationDate.map { formatter.string(from: $0) } ?? "Sin fecha"
            groups[key, default: []].append(asset)
        }

        // Sort by most recent first
        let sorted = groups.sorted { pair1, pair2 in
            let date1 = pair1.value.first?.creationDate ?? .distantPast
            let date2 = pair2.value.first?.creationDate ?? .distantPast
            return date1 > date2
        }

        groupedByMonth = sorted
        isLoading = false
    }
}

// MARK: - Mesh Photo Cell

struct MeshPhotoCell: View {
    let asset: PHAsset
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.white.opacity(0.2))
                        }
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )

            // Badge for screenshots
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                Image(systemName: "rectangle.dashed")
                    .font(.caption2)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(8)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 300, height: 300))
        }
    }
}
