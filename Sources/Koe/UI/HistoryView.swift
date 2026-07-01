import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var copiedID: UUID?

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return app.history.entries }
        return app.history.entries.filter {
            $0.raw.localizedCaseInsensitiveContains(query) ||
            $0.refined.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("履歴を検索", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .card(cornerRadius: 8)

                Spacer()

                if !app.history.entries.isEmpty {
                    Button(role: .destructive) {
                        app.history.clear()
                    } label: {
                        Label("すべて削除", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { entry in
                            row(entry)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "まだ履歴がありません" : "「\(query)」に一致する履歴はありません")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("\(app.settings.value.hotkey.display) で音声入力を始めましょう")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Chip(text: entry.mode.label, icon: entry.mode.icon, tint: Brand.secondary)
                if entry.model != "-" {
                    Chip(text: entry.model, icon: "cpu", tint: .secondary)
                }
                Spacer()
                Button {
                    _ = Paster.deliver(entry.refined, paste: false, keepInClipboard: true)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Label(copiedID == entry.id ? "コピーしました" : "コピー",
                          systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)

                Button {
                    app.history.delete(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("削除")
            }

            Text(entry.refined)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.raw != entry.refined {
                Text(entry.raw)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .card(cornerRadius: 12)
    }
}
