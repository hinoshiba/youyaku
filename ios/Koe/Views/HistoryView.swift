import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    @State private var shareText: String?

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return app.history.entries }
        return app.history.entries.filter {
            $0.raw.localizedCaseInsensitiveContains(query) ||
            $0.refined.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filtered) { entry in
                            row(entry)
                        }
                        .onDelete { indexSet in
                            for i in indexSet { app.history.delete(filtered[i]) }
                        }
                    }
                }
            }
            .navigationTitle(tr("履歴", "History"))
            .searchable(text: $query, prompt: tr("履歴を検索", "Search history"))
            .toolbar {
                if !app.history.entries.isEmpty {
                    Button(role: .destructive) {
                        app.history.clear()
                    } label: { Image(systemName: "trash") }
                }
            }
            .sheet(item: Binding(
                get: { shareText.map { SharePayload(text: $0) } },
                set: { shareText = $0?.text }
            )) { payload in
                ShareSheet(items: [payload.text])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? tr("まだ履歴がありません", "No history yet")
                               : tr("一致する履歴はありません", "No matching history"))
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let hasRefined = !entry.refined.isEmpty
        let mainText = hasRefined ? entry.refined : entry.raw
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                if hasRefined {
                    Chip(text: entry.mode.label, icon: entry.mode.icon, tint: Brand.secondary)
                } else {
                    Chip(text: tr("音声のみ", "Voice only"), icon: "mic", tint: .orange)
                }
                Spacer()
            }
            Text(mainText)
                .font(.system(size: 14))
                .textSelection(.enabled)
            if hasRefined, entry.raw != entry.refined {
                Text(entry.raw)
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
            HStack(spacing: 16) {
                Button {
                    Clipboard.copy(mainText)
                    Haptics.tap()
                } label: { Label(tr("コピー", "Copy"), systemImage: "doc.on.doc").font(.system(size: 11)) }
                Button {
                    shareText = mainText
                } label: { Label(tr("共有", "Share"), systemImage: "square.and.arrow.up").font(.system(size: 11)) }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
