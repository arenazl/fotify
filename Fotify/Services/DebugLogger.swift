import SwiftUI

@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: String
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

// MARK: - Debug Sheet View

struct DebugSheetView: View {
    @ObservedObject private var debugLog = DebugLogger.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if debugLog.logs.isEmpty {
                    Text("Sin logs todavía...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(debugLog.logs) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.category)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(logColor(entry.category))
                                        .frame(width: 55, alignment: .leading)
                                    Text(entry.message)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.8), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Limpiar") { debugLog.clear() }
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func logColor(_ category: String) -> Color {
        switch category {
        case "INDEX": return .cyan
        case "SEARCH": return .green
        case "GROQ": return .purple
        case "GPS": return .orange
        case "FACE": return .pink
        default: return .white
        }
    }
}

// MARK: - Debug Toolbar Modifier

struct DebugToolbarModifier: ViewModifier {
    @State private var showDebug = false

    func body(content: Content) -> some View {
        if Config.debugMode {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showDebug = true
                        } label: {
                            Image(systemName: "ladybug")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                .sheet(isPresented: $showDebug) {
                    DebugSheetView()
                }
        } else {
            content
        }
    }
}

extension View {
    func debugToolbar() -> some View {
        modifier(DebugToolbarModifier())
    }
}
