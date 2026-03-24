import SwiftUI
import Photos
import Vision

struct FaceMatchView: View {
    let referenceAsset: PHAsset
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @ObservedObject var tagsVM: TagsViewModel
    @ObservedObject var folderManager: FolderManager
    @Environment(\.dismiss) var dismiss

    @State private var personName: String = ""
    @State private var referenceImage: UIImage?
    @State private var matchedAssets: [PHAsset] = []
    @State private var isSearching = false
    @State private var searchProgress: Double = 0
    @State private var totalCandidates: Int = 0
    @State private var checkedCount: Int = 0
    @State private var debugLog: [String] = []
    @State private var selectedIndex: Int?
    @State private var folderCreated = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Reference photo
                        if let img = referenceImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.purple, lineWidth: 3))
                        }

                        // Name input
                        TextField("Nombre de esta persona", text: $personName)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 20)

                        // Search button
                        if !isSearching && matchedAssets.isEmpty && !folderCreated {
                            Button {
                                Task { await searchForPerson() }
                            } label: {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Buscar esta persona")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 20)
                            }
                            .disabled(personName.isEmpty)
                            .opacity(personName.isEmpty ? 0.5 : 1)
                        }

                        // Progress
                        if isSearching {
                            VStack(spacing: 8) {
                                ProgressView(value: searchProgress)
                                    .tint(.purple)
                                    .padding(.horizontal, 20)
                                Text("Comparando caras... \(checkedCount)/\(totalCandidates)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Results
                        if !matchedAssets.isEmpty {
                            HStack {
                                Text("\(matchedAssets.count) fotos de \(personName)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 20)

                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(0..<matchedAssets.count, id: \.self) { index in
                                    PhotoGridCell(asset: matchedAssets[index])
                                        .onTapGesture { selectedIndex = index }
                                }
                            }
                            .padding(.horizontal, 2)

                            if !folderCreated {
                                Button {
                                    createPersonFolder()
                                } label: {
                                    HStack {
                                        Image(systemName: "folder.badge.plus")
                                        Text("Crear carpeta \"\(personName)\"")
                                    }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal, 20)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Carpeta \"\(personName)\" creada")
                                        .foregroundStyle(.green)
                                }
                                .font(.subheadline.bold())
                            }
                        }

                        // Debug log
                        if !debugLog.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DEBUG")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.yellow)
                                ScrollView(showsIndicators: true) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(0..<debugLog.count, id: \.self) { i in
                                            Text(debugLog[i])
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.6))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                            }
                            .padding(12)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Identificar persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.8), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .fullScreenCover(item: $selectedIndex) { index in
                PhotoViewer(initialIndex: index, fetchResult: nil, assets: matchedAssets)
                    .environmentObject(photoLibrary)
            }
            .task {
                referenceImage = await photoLibrary.thumbnail(for: referenceAsset, size: CGSize(width: 300, height: 300))
            }
        }
    }

    // MARK: - Face Search

    private func searchForPerson() async {
        isSearching = true
        matchedAssets = []
        debugLog = []

        debugLog.append("Buscando fotos con personas en el índice...")

        // Get all photos that have person-related tags
        let personTerms = ["hombre", "mujer", "persona", "niño", "niña", "gente", "grupo", "joven", "adulto", "bebé", "chico", "chica", "nene", "nena"]
        let candidates = tagsVM.searchByTerms(personTerms, photoLibrary: photoLibrary)

        totalCandidates = candidates.count
        debugLog.append("Encontradas \(totalCandidates) fotos con personas")

        guard let refImage = referenceImage,
              let refJpeg = refImage.jpegData(compressionQuality: 0.4) else {
            debugLog.append("ERROR: no se pudo obtener imagen de referencia")
            isSearching = false
            return
        }

        let refBase64 = refJpeg.base64EncodedString()
        debugLog.append("Referencia: \(refBase64.count / 1024)KB")

        // Compare reference against each candidate
        let batchSize = 5
        for batchStart in stride(from: 0, to: candidates.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, candidates.count)

            await withTaskGroup(of: (PHAsset, Bool).self) { group in
                for i in batchStart..<batchEnd {
                    let candidate = candidates[i]
                    if candidate.localIdentifier == referenceAsset.localIdentifier {
                        // Skip reference photo itself
                        group.addTask { return (candidate, true) }
                        continue
                    }

                    group.addTask {
                        guard let candidateImg = await photoLibrary.thumbnail(for: candidate, size: CGSize(width: 200, height: 200)),
                              let candidateJpeg = candidateImg.jpegData(compressionQuality: 0.3) else {
                            return (candidate, false)
                        }
                        let candidateBase64 = candidateJpeg.base64EncodedString()
                        let isMatch = await self.compareFaces(ref: refBase64, candidate: candidateBase64)
                        return (candidate, isMatch)
                    }
                }

                for await (asset, isMatch) in group {
                    checkedCount += 1
                    searchProgress = Double(checkedCount) / Double(totalCandidates)
                    if isMatch {
                        matchedAssets.append(asset)
                        debugLog.append("MATCH #\(matchedAssets.count)")
                    }
                }
            }
        }

        debugLog.append("Terminado: \(matchedAssets.count) matches de \(totalCandidates)")
        isSearching = false
    }

    private func compareFaces(ref: String, candidate: String) async -> Bool {
        let requestBody: [String: Any] = [
            "model": Config.groqVisionModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Son la misma persona en estas dos fotos? Solo responde JSON: {\"match\": true} o {\"match\": false}"],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(ref)"]],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(candidate)"]]
                    ]
                ]
            ],
            "max_tokens": 50,
            "temperature": 0.1
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.groqAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return await compareFaces(ref: ref, candidate: candidate)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let start = cleaned.firstIndex(of: "{"),
                   let end = cleaned.lastIndex(of: "}") {
                    let jsonStr = String(cleaned[start...end])
                    if let jsonData = jsonStr.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let match = parsed["match"] as? Bool {
                        return match
                    }
                }
            }
        } catch {
            return false
        }
        return false
    }

    // MARK: - Create Folder

    private func createPersonFolder() {
        let searchTerms = [personName.lowercased(), "persona", "hombre", "mujer"]
        let folder = CustomFolder(name: personName, searchTerms: searchTerms)
        folderManager.addFolder(folder)
        folderCreated = true
    }
}
