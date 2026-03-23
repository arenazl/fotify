import SwiftUI

@MainActor
class FolderManager: ObservableObject {
    @Published var folders: [CustomFolder] = []

    private let keychainService = "com.fotify.folders"
    private let keychainAccount = "custom_folders"

    init() {
        load()
    }

    func addFolder(_ folder: CustomFolder) {
        folders.append(folder)
        save()
    }

    func removeFolder(id: String) {
        folders.removeAll { $0.id == id }
        save()
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
