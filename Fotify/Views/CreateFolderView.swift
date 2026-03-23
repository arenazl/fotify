import SwiftUI
import Photos
import Speech

struct CreateFolderView: View {
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @ObservedObject var folderManager: FolderManager
    @Environment(\.dismiss) var dismiss

    @State private var searchText: String = ""
    @State private var folderName: String = ""
    @State private var assets: [PHAsset] = []
    @State private var selectedForDeletion: Set<String> = []
    @State private var isSearching = false
    @State private var searchTerms: [String] = []
    @State private var isRecording = false
    @State private var isSelecting = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Search bar with mic
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundStyle(.purple)

                        TextField("Ej: fotos de perros, comida...", text: $searchText)
                            .onSubmit { Task { await performSearch() } }

                        if isSearching {
                            ProgressView().tint(.purple).scaleEffect(0.8)
                        }

                        Button {
                            startDictation()
                        } label: {
                            Image(systemName: isRecording ? "mic.fill" : "mic")
                                .foregroundStyle(isRecording ? .red : .white)
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)

                    // Results info
                    if !assets.isEmpty {
                        HStack {
                            Text("\(assets.count) fotos encontradas")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(isSelecting ? "Listo" : "Seleccionar") {
                                isSelecting.toggle()
                                if !isSelecting { selectedForDeletion.removeAll() }
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.purple)
                        }
                        .padding(.horizontal, 16)

                        if isSelecting && !selectedForDeletion.isEmpty {
                            Button {
                                removeSelected()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Quitar \(selectedForDeletion.count) fotos")
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.red.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                    }

                    // Results grid
                    if assets.isEmpty && !searchText.isEmpty && !isSearching {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Sin resultados")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else if assets.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "plus.rectangle.on.folder")
                                .font(.system(size: 48))
                                .foregroundStyle(.purple.opacity(0.5))
                            Text("Buscá fotos para crear una carpeta")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(0..<assets.count, id: \.self) { index in
                                    let asset = assets[index]
                                    ZStack(alignment: .topTrailing) {
                                        PhotoGridCell(asset: asset)

                                        if isSelecting {
                                            Image(systemName: selectedForDeletion.contains(asset.localIdentifier) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedForDeletion.contains(asset.localIdentifier) ? .red : .white)
                                                .shadow(radius: 2)
                                                .padding(6)
                                        }
                                    }
                                    .onTapGesture {
                                        if isSelecting {
                                            if selectedForDeletion.contains(asset.localIdentifier) {
                                                selectedForDeletion.remove(asset.localIdentifier)
                                            } else {
                                                selectedForDeletion.insert(asset.localIdentifier)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Folder name + create button
                        VStack(spacing: 12) {
                            TextField("Nombre de la carpeta", text: $folderName)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)

                            Button {
                                createFolder()
                            } label: {
                                HStack {
                                    Image(systemName: "folder.badge.plus")
                                    Text("Crear carpeta")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 16)
                            }
                            .disabled(folderName.isEmpty || assets.isEmpty)
                            .opacity(folderName.isEmpty || assets.isEmpty ? 0.5 : 1)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Nueva carpeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.8), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Search

    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        isSearching = true

        // Auto-set folder name from search
        if folderName.isEmpty {
            folderName = searchText.capitalized
        }

        let response = await GrokService.shared.processCommand(
            searchText,
            photoLibrary: photoLibrary,
            availableTags: tagsVM.availableTags
        )

        switch response.action {
        case .searchByTerms(let terms):
            searchTerms = terms
            assets = tagsVM.searchByTerms(terms, photoLibrary: photoLibrary)
        case .searchByLocation(let place):
            searchTerms = [place]
            assets = await tagsVM.searchByLocation(place: place, photoLibrary: photoLibrary)
        default:
            searchTerms = [searchText.lowercased()]
            assets = tagsVM.searchByTerms(searchTerms, photoLibrary: photoLibrary)
        }

        isSearching = false
    }

    // MARK: - Remove selected

    private func removeSelected() {
        assets.removeAll { selectedForDeletion.contains($0.localIdentifier) }
        selectedForDeletion.removeAll()
    }

    // MARK: - Create folder

    private func createFolder() {
        let folder = CustomFolder(name: folderName, searchTerms: searchTerms)
        folderManager.addFolder(folder)
        dismiss()
    }

    // MARK: - Dictation

    private func startDictation() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            // Use iOS keyboard dictation as fallback
            // The TextField already supports dictation via iOS keyboard
        }
    }
}
