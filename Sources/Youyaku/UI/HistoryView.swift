import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var expandedIDs: Set<UUID> = []

    // 表示が切り詰められる可能性があるか(行数指定の lineLimit に合わせ、
    // 文字量と改行数の両方で判定する)
    private static func isClipped(_ text: String, lineLimit: Int, charBudget: Int) -> Bool {
        if text.count > charBudget { return true }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return lines > lineLimit
    }

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return app.history.entries }
        return app.history.entries.filter {
            $0.raw.localizedCaseInsensitiveContains(query) ||
            $0.refined.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        // 検索フィルタは 1 レンダーにつき 1 回だけ評価する
        let list = filtered
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(tr("履歴を検索", "Search history"), text: $query)
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
                        Label(tr("すべて削除", "Delete All"), systemImage: "trash")
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if list.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(list) { entry in
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
            Text(query.isEmpty ? tr("まだ履歴がありません", "No history yet") : tr("「\(query)」に一致する履歴はありません", "No history matching \"\(query)\""))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text(tr("\(app.settings.value.hotkey.display) で音声入力を始めましょう", "Press \(app.settings.value.hotkey.display) to start dictating"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        // 変換前(音声入力)と変換後の両方を保持。未変換なら音声入力を本文として表示
        let hasRefined = !entry.refined.isEmpty
        let mainText = hasRefined ? entry.refined : entry.raw
        let expanded = expandedIDs.contains(entry.id)
        let showsRaw = hasRefined && entry.raw != entry.refined
        // 本文は 6 行(約 360 字)、併記の音声入力は 2 行(約 120 字)で切り詰められる
        let isLong = Self.isClipped(mainText, lineLimit: 6, charBudget: 360)
            || (showsRaw && Self.isClipped(entry.raw, lineLimit: 2, charBudget: 120))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                if hasRefined {
                    Chip(text: entry.mode.label, icon: entry.mode.icon, tint: Brand.secondary)
                } else {
                    Chip(text: tr("音声のみ", "Voice Only"), icon: "mic", tint: .orange)
                }
                if entry.model != "-" {
                    Chip(text: entry.model, icon: "cpu", tint: .secondary)
                }
                Spacer()
                Button {
                    _ = Paster.deliver(mainText, paste: false, keepInClipboard: true)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    Label(copiedID == entry.id ? tr("コピーしました", "Copied") : tr("コピー", "Copy"),
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
                .help(tr("削除", "Delete"))
            }

            Text(mainText)
                .font(.system(size: 13))
                .lineLimit(expanded ? nil : 6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 変換済みの場合は、元の音声入力も併記(コピー可)
            if showsRaw {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(tr("音声入力", "Dictation"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Button {
                            _ = Paster.deliver(entry.raw, paste: false, keepInClipboard: true)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help(tr("音声入力をコピー", "Copy Dictation"))
                    }
                    Text(entry.raw)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(expanded ? nil : 2)
                        .textSelection(.enabled)
                }
            }

            if isLong {
                Button {
                    if expanded {
                        expandedIDs.remove(entry.id)
                    } else {
                        expandedIDs.insert(entry.id)
                    }
                } label: {
                    Label(expanded ? tr("折りたたむ", "Collapse") : tr("すべて表示", "Show All"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .card(cornerRadius: 12)
    }
}
