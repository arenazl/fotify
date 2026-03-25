import SwiftUI
import Photos

// MARK: - Face Comparer (shared utility)

enum FaceComparer {
    static func compare(ref: String, candidate: String) async -> Bool {
        let requestBody: [String: Any] = [
            "model": Config.groqVisionModel,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": "Son la misma persona en estas dos fotos? Solo responde JSON: {\"match\": true} o {\"match\": false}"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(ref)"]],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(candidate)"]]
                ]
            ]],
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
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 429 {
                await DebugLogger.shared.log("FACE", "⚠️ Rate limit, esperando 2s...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return await compare(ref: ref, candidate: candidate)
            }
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
                await DebugLogger.shared.log("FACE", "❌ API error: \(httpResp.statusCode)")
                return false
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}") {
                    let jsonStr = String(cleaned[s...e])
                    if let d = jsonStr.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let match = parsed["match"] as? Bool {
                        return match
                    }
                }
            }
        } catch {}
        return false
    }
}

@MainActor
class FolderManager: ObservableObject {
    @Published var folders: [CustomFolder] = []
    @Published var personScanProgress: String = "" // "Lucas: 350/11000"
    @Published var isPersonScanning = false

    private let keychainService = "com.fotify.folders"
    private let keychainAccount = "custom_folders"

    init() {
        load()
    }

    func addFolder(_ folder: CustomFolder) {
        // If a folder with the same name exists, update it instead of duplicating
        if let idx = folders.firstIndex(where: { $0.name.lowercased() == folder.name.lowercased() }) {
            var existing = folders[idx]
            // Merge asset IDs (keep existing + add new)
            let existingIds = Set(existing.matchedAssetIds)
            let newIds = folder.matchedAssetIds.filter { !existingIds.contains($0) }
            existing.matchedAssetIds.append(contentsOf: newIds)
            existing.lastUpdated = Date()
            if existing.referenceAssetId == nil { existing.referenceAssetId = folder.referenceAssetId }
            if !existing.isPerson && folder.isPerson { existing.isPerson = true }
            folders[idx] = existing
        } else {
            folders.append(folder)
        }
        save()
    }

    func removeFolder(id: String) {
        folders.removeAll { $0.id == id }
        save()
    }

    func updateFolder(_ folder: CustomFolder) {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx] = folder
            save()
        }
    }

    /// Refresh tag-based folders with new photos
    func refreshFolders(tagsVM: TagsViewModel, photoLibrary: PhotoLibraryService) {
        for i in 0..<folders.count {
            var folder = folders[i]
            guard !folder.isPerson && !folder.searchTerms.isEmpty else { continue }
            let results = tagsVM.searchByTerms(folder.searchTerms, photoLibrary: photoLibrary)
            let newIds = results.map { $0.localIdentifier }
            let addedIds = newIds.filter { !folder.matchedAssetIds.contains($0) }
            if !addedIds.isEmpty {
                folder.matchedAssetIds.append(contentsOf: addedIds)
                folder.lastUpdated = Date()
                folders[i] = folder
            }
        }
        save()
    }

    /// Full person scan: runs from FaceMatchView, continues even if view closes
    func fullPersonScan(personName: String, referenceAssetId: String, initialMatchIds: [String], photoLibrary: PhotoLibraryService, tagsVM: TagsViewModel) async {
        guard let allPhotos = photoLibrary.allPhotos else { return }

        // Create or update folder
        var folder: CustomFolder
        if let idx = folders.firstIndex(where: { $0.isPerson && $0.name == personName }) {
            folder = folders[idx]
        } else {
            folder = CustomFolder(personName: personName, referenceAssetId: referenceAssetId, matchedIds: initialMatchIds)
            folders.append(folder)
            save()
        }

        guard let refImg = await photoLibrary.thumbnail(
            for: findAsset(id: referenceAssetId, in: allPhotos),
            size: CGSize(width: 200, height: 200)
        ), let refJpeg = refImg.jpegData(compressionQuality: 0.4) else { return }
        let refBase64 = refJpeg.base64EncodedString()

        isPersonScanning = true
        let personTerms = ["hombre", "mujer", "persona", "niño", "niña", "gente", "grupo", "joven", "adulto", "bebé", "chico", "chica", "nene", "nena", "selfie", "retrato"]
        let candidates = tagsVM.searchByTerms(personTerms, photoLibrary: photoLibrary)

        var existingIds = Set(folder.matchedAssetIds)
        let total = candidates.count
        var checked = 0

        DebugLogger.shared.log("FACE", "Full scan \(personName): \(total) candidatas")

        let batchSize = 10
        for batchStart in stride(from: 0, to: candidates.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, candidates.count)

            await withTaskGroup(of: (String, Bool).self) { group in
                for i in batchStart..<batchEnd {
                    let candidate = candidates[i]
                    let candidateId = candidate.localIdentifier
                    if existingIds.contains(candidateId) || candidateId == referenceAssetId {
                        group.addTask { return (candidateId, false) }
                        continue
                    }

                    group.addTask {
                        guard let img = await photoLibrary.thumbnail(for: candidate, size: CGSize(width: 150, height: 150)),
                              let jpeg = img.jpegData(compressionQuality: 0.3) else {
                            await DebugLogger.shared.log("FACE", "❌ Sin thumbnail")
                            return (candidateId, false)
                        }
                        let isMatch = await FaceComparer.compare(ref: refBase64, candidate: jpeg.base64EncodedString())
                        return (candidateId, isMatch)
                    }
                }

                for await (assetId, isMatch) in group {
                    checked += 1
                    if isMatch && !existingIds.contains(assetId) {
                        existingIds.insert(assetId)
                        if let idx = folders.firstIndex(where: { $0.isPerson && $0.name == personName }) {
                            folders[idx].matchedAssetIds.append(assetId)
                        }
                        DebugLogger.shared.log("FACE", "✅ MATCH #\(existingIds.count) (\(checked)/\(total))")
                    } else if checked % 50 == 0 {
                        DebugLogger.shared.log("FACE", "⏳ \(checked)/\(total) - matches: \(existingIds.count)")
                    }
                }
            }

            personScanProgress = "\(personName): \(checked)/\(total)"

            // Save every 50 photos
            if checked % 50 < batchSize { save() }
        }

        // Final save
        if let idx = folders.firstIndex(where: { $0.isPerson && $0.name == personName }) {
            folders[idx].lastUpdated = Date()
            folders[idx].lastScannedIndex = candidates.count
        }
        save()
        isPersonScanning = false
        personScanProgress = ""
        DebugLogger.shared.log("FACE", "Full scan \(personName) completo: \(existingIds.count) matches")
    }

    /// Background scan: compare unscanned photos against person folders
    func backgroundPersonScan(photoLibrary: PhotoLibraryService) async {
        let personFolders = folders.filter { $0.isPerson && $0.referenceAssetId != nil }
        guard !personFolders.isEmpty, let allPhotos = photoLibrary.allPhotos else { return }

        // Get all person-tagged photos (search by person terms in tags)
        // For now, scan ALL photos with faces progressively
        let personTerms = ["hombre", "mujer", "persona", "niño", "niña", "gente", "grupo", "joven", "adulto", "bebé", "chico", "chica", "nene", "nena", "selfie", "retrato"]

        for folderIdx in 0..<folders.count {
            guard folders[folderIdx].isPerson,
                  let refAssetId = folders[folderIdx].referenceAssetId else { continue }

            // Get reference image
            guard let refImage = await photoLibrary.thumbnail(for: findAsset(id: refAssetId, in: allPhotos), size: CGSize(width: 200, height: 200)),
                  let refJpeg = refImage.jpegData(compressionQuality: 0.4) else { continue }
            let refBase64 = refJpeg.base64EncodedString()

            let startIdx = folders[folderIdx].lastScannedIndex
            let existingIds = Set(folders[folderIdx].matchedAssetIds)
            var newMatches: [String] = []
            let batchSize = 10
            var scanned = 0

            // Scan 50 photos per app launch (not all at once)
            let maxPerLaunch = 50

            for i in startIdx..<allPhotos.count {
                let asset = allPhotos.object(at: i)
                if existingIds.contains(asset.localIdentifier) { continue }

                if let img = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 150, height: 150)),
                   let jpeg = img.jpegData(compressionQuality: 0.3) {
                    let candidateBase64 = jpeg.base64EncodedString()
                    let isMatch = await FaceComparer.compare(ref: refBase64, candidate: candidateBase64)
                    if isMatch {
                        newMatches.append(asset.localIdentifier)
                        await DebugLogger.shared.log("FACE", "BG match para \(folders[folderIdx].name)")
                    }
                }

                scanned += 1
                folders[folderIdx].lastScannedIndex = i + 1

                if scanned >= maxPerLaunch { break }
            }

            if !newMatches.isEmpty {
                folders[folderIdx].matchedAssetIds.append(contentsOf: newMatches)
                folders[folderIdx].lastUpdated = Date()
                await DebugLogger.shared.log("FACE", "BG: +\(newMatches.count) fotos de \(folders[folderIdx].name)")
            }
        }
        save()
    }

    private func findAsset(id: String, in fetchResult: PHFetchResult<PHAsset>) -> PHAsset {
        for i in 0..<fetchResult.count {
            let asset = fetchResult.object(at: i)
            if asset.localIdentifier == id { return asset }
        }
        return fetchResult.firstObject!
    }


    // MARK: - Keychain Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func load() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let decoded = try? JSONDecoder().decode([CustomFolder].self, from: data) {
            folders = decoded
        }
    }
}
