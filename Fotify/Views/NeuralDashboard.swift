import SwiftUI
import Photos

struct NeuralDashboard: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var folderManager: FolderManager
    @Binding var showCreateFolder: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(spacing: 24) {
            categoriesGrid
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

                // Custom folders
                ForEach(folderManager.folders) { folder in
                    NavigationLink(value: folder) {
                        CategoryCardView(
                            icon: "folder.fill",
                            label: folder.name,
                            count: nil,
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            folderManager.removeFolder(id: folder.id)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }

                // Add button (always last)
                Button {
                    showCreateFolder = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        Text("Agregar")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .background(.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.purple.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
            }
            .padding(.horizontal, 20)
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

}
