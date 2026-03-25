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
    @State private var debugLog: [String] = []

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

                        // Debug log
                        if !debugLog.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("DEBUG LOG")
                                        .font(.caption2.bold())
                                        .kerning(2)
                                        .foregroundStyle(.yellow)
                                    Spacer()
                                    Button("Copiar") {
                                        UIPasteboard.general.string = debugLog.joined(separator: "\n")
                                    }
                                    .font(.caption2).foregroundStyle(.blue)
                                    Button("Limpiar") { debugLog.removeAll() }
                                        .font(.caption2).foregroundStyle(.red)
                                }
                                ScrollView(showsIndicators: true) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(0..<debugLog.count, id: \.self) { i in
                                            Text(debugLog[i])
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .frame(maxHeight: 300)
                            }
                            .padding(12)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
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
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        debugLog.removeAll()

        if folderName.isEmpty {
            folderName = searchText.capitalized
        }

        debugLog.append("QUERY: \"\(searchText)\"")
        debugLog.append("INDEX: \(tagsVM.scannedCount) fotos indexadas")

        let taggedPersons = folderManager.folders.filter { $0.isPerson }.map { $0.name }
        let response = await GrokService.shared.processCommand(
            searchText,
            photoLibrary: photoLibrary,
            availableTags: tagsVM.availableTags,
            taggedPersons: taggedPersons
        )

        debugLog.append("GROQ ACTION: \(response.message)")

        switch response.action {
        case .searchByTerms(let terms):
            searchTerms = terms
            debugLog.append("SEARCH TERMS: \(terms.prefix(10).joined(separator: ", "))")
            assets = tagsVM.searchByTerms(terms, photoLibrary: photoLibrary)
            debugLog.append("RESULTADOS: \(assets.count) fotos")
            // Log tags of first 5 matches
            for (i, asset) in assets.prefix(5).enumerated() {
                if let tags = tagsVM.tagsForAsset(asset.localIdentifier) {
                    debugLog.append("MATCH \(i+1): \(tags.joined(separator: ", "))")
                }
            }
        case .searchByLocation(let place):
            searchTerms = [place]
            debugLog.append("LOCATION: \"\(place)\"")
            assets = await tagsVM.searchByLocation(place: place, photoLibrary: photoLibrary)
            debugLog.append("GPS RESULTS: \(assets.count) fotos")
        case .personSearch(let person, let contextTags):
            debugLog.append("PERSON: \"\(person)\", contexto: \(contextTags)")
            // Find the person folder
            if let personFolder = folderManager.folders.first(where: { $0.isPerson && $0.name.lowercased() == person.lowercased() }) {
                let personIds = Set(personFolder.matchedAssetIds)
                debugLog.append("PERSON IDs: \(personIds.count) fotos de \(person)")

                if contextTags.isEmpty {
                    // Just show person's photos
                    guard let allPhotos = photoLibrary.allPhotos else { break }
                    for i in 0..<allPhotos.count {
                        let asset = allPhotos.object(at: i)
                        if personIds.contains(asset.localIdentifier) {
                            assets.append(asset)
                        }
                    }
                } else {
                    // Cross: person IDs ∩ context tags
                    let tagResults = tagsVM.searchByTerms(contextTags, photoLibrary: photoLibrary)
                    debugLog.append("TAG RESULTS: \(tagResults.count) fotos con \(contextTags.prefix(3))")
                    assets = tagResults.filter { personIds.contains($0.localIdentifier) }
                    debugLog.append("INTERSECCIÓN: \(assets.count) fotos de \(person) + contexto")

                    // If intersection is small, also search by face in tag results
                    if assets.count < 5 && tagResults.count > 0 && tagResults.count <= 200 {
                        debugLog.append("FACE SEARCH: comparando \(tagResults.count) fotos por cara")
                        // Compare face against tag results that aren't already matched
                        if let refId = personFolder.referenceAssetId {
                            guard let refImg = await photoLibrary.thumbnail(for: findAsset(refId), size: CGSize(width: 200, height: 200)),
                                  let refJpeg = refImg.jpegData(compressionQuality: 0.4) else { break }
                            let refBase64 = refJpeg.base64EncodedString()
                            let existingIds = Set(assets.map { $0.localIdentifier })

                            for candidate in tagResults where !existingIds.contains(candidate.localIdentifier) {
                                if let img = await photoLibrary.thumbnail(for: candidate, size: CGSize(width: 150, height: 150)),
                                   let jpeg = img.jpegData(compressionQuality: 0.3) {
                                    let isMatch = await FaceComparer.compare(ref: refBase64, candidate: jpeg.base64EncodedString())
                                    if isMatch {
                                        assets.append(candidate)
                                        debugLog.append("FACE MATCH en contexto!")
                                    }
                                }
                            }
                        }
                    }
                }
                searchTerms = contextTags
                debugLog.append("TOTAL: \(assets.count) fotos")
            } else {
                debugLog.append("ERROR: persona \"\(person)\" no tagueada")
            }
        default:
            searchTerms = [searchText.lowercased()]
            debugLog.append("FALLBACK: buscando \"\(searchText)\"")
            assets = tagsVM.searchByTerms(searchTerms, photoLibrary: photoLibrary)
            debugLog.append("RESULTADOS: \(assets.count) fotos")
        }

        isSearching = false
    }

    private func findAsset(_ id: String) -> PHAsset {
        guard let all = photoLibrary.allPhotos else { return PHAsset() }
        for i in 0..<all.count {
            let a = all.object(at: i)
            if a.localIdentifier == id { return a }
        }
        return all.firstObject ?? PHAsset()
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
