import SwiftUI

@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: String  // "INDEX", "SEARCH", "GROQ", "GPS"
        let message: String
    }

    @Published var logs: [LogEntry] = []

    func log(_ category: String, _ message: String) {
        guard Config.debugMode else { return }
        let entry = LogEntry(timestamp: Date(), category: category, message: message)
        logs.insert(entry, at: 0)
        if logs.count > 200 { logs.removeLast() }
    }

    func clear() {
        logs.removeAll()
    }
}
