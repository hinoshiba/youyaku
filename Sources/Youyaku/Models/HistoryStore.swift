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

    /// 履歴に追加してエントリ ID を返す。refined は空でもよい(音声入力のみの保全)
    @discardableResult
    func add(raw: String, refined: String, mode: RefineMode, model: String) -> UUID {
        let entry = HistoryEntry(raw: raw, refined: refined, mode: mode, model: model)
        entries.insert(entry, at: 0)
        if entries.count > Self.cap {
            entries.removeLast(entries.count - Self.cap)
        }
        save()
        return entry.id
    }

    /// 変換完了時に、先に保存しておいた音声入力エントリへ変換結果を書き込む
    func updateRefined(id: UUID, refined: String, mode: RefineMode, model: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].refined = refined
        entries[index].mode = mode
        entries[index].model = model
        save()
    }

    /// 再開セッションの終了時に、同じエントリの音声入力を延長後の内容へ更新する。
    /// 日付を更新するので、新しい順の並びを保つため先頭へ移動する
    func updateRaw(id: UUID, raw: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.raw = raw
        entry.date = Date()
        entries.insert(entry, at: 0)
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
