import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var raw: String
    var refined: String
    var mode: RefineMode
    var model: String
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private static var fileURL: URL {
        SettingsStore.directory.appendingPathComponent("history.json")
    }

    private static let cap = 300

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    func add(raw: String, refined: String, mode: RefineMode, model: String) {
        entries.insert(HistoryEntry(raw: raw, refined: refined, mode: mode, model: model), at: 0)
        if entries.count > Self.cap {
            entries.removeLast(entries.count - Self.cap)
        }
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
