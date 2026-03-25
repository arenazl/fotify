import SwiftUI
import Photos

struct NeuralDashboard: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var folderManager: FolderManager
    @ObservedObject var tagsVM: TagsViewModel
    @Binding var showCreateFolder: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(spacing: 24) {
            categoriesGrid

            if !folderManager.folders.isEmpty {
                dynamicFoldersSection
            }
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
                // Fixed categories
                ForEach(PhotoCategory.allCases) { category in
                    NavigationLink(value: category) {
                        CategoryCardView(
                            icon: category.icon,
                            label: category.label,
                            count: photoLibrary.count(for: category),
                            color: category.color
                        )
                    }
                    .buttonStyle(.plain)
                }

                // IA button (always last)
                Menu {
                    Button {
                        showCreateFolder = true
                    } label: {
                        Label("Buscar fotos", systemImage: "magnifyingglass")
                    }

                    Button {
                        showCreateFolder = true
                    } label: {
                        Label("Crear carpeta", systemImage: "folder.badge.plus")
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        Text("IA")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .background(
                        LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.purple.opacity(0.4), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Dynamic Folders Section

    private var dynamicFoldersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MIS CARPETAS")
                .font(.caption2.bold())
                .kerning(2)
                .foregroundStyle(.purple)
                .padding(.leading, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(folderManager.folders) { folder in
                        NavigationLink(value: folder) {
                            FolderThumbnailView(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                refreshingFolderId = folder.id
                                Task {
                                    folderManager.refreshFolders(tagsVM: tagsVM, photoLibrary: photoLibrary)
                                    refreshingFolderId = nil
                                }
                            } label: {
                                Label("Actualizar", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                folderManager.removeFolder(id: folder.id)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @State private var refreshingFolderId: String?
}

// MARK: - Folder Thumbnail

struct FolderThumbnailView: View {
    let folder: CustomFolder
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var thumbnail: UIImage?

    private var assetId: String? {
        folder.referenceAssetId ?? folder.matchedAssetIds.first
    }

    var body: some View {
        VStack(spacing: 8) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(.purple.opacity(0.5), lineWidth: 2)
                    )
            } else {
                Circle()
                    .fill(.purple.opacity(0.15))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: folder.isPerson ? "person.fill" : "folder.fill")
                            .font(.title3)
                            .foregroundStyle(.purple)
                    )
            }

            Text(folder.name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 70)

            Text("\(folder.matchedAssetIds.count)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .task {
            guard let id = assetId,
                  let allPhotos = photoLibrary.allPhotos else { return }
            for i in 0..<allPhotos.count {
                let asset = allPhotos.object(at: i)
                if asset.localIdentifier == id {
                    thumbnail = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 150, height: 150))
                    break
                }
            }
        }
    }
}

// MARK: - Category Card

struct CategoryCardView: View {
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
