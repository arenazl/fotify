import SwiftUI

@main
struct FotifyApp: App {
    @StateObject private var photoLibrary = PhotoLibraryService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(photoLibrary)
        }
    }
}
