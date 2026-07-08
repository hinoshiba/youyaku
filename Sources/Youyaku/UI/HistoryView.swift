import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var expandedIDs: Set<UUID> = []
    // 選択モードと選択中の ID。まとめて削除に使う
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    // 削除確認ダイアログの対象(単一 / 複数選択 / 全部)。nil なら非表示
    @State private var pendingDelete: PendingDelete?

    // 削除確認の対象種別。1 つのダイアログで単一・複数・全部を扱う
    private enum PendingDelete {
        case single(HistoryEntry)
        case selected(Set<UUID>)
        case all

        var count: Int {
            switch self {
            case .single: return 1
            case .selected(let ids): return ids.count
            case .all: return 0   // 件数は呼び出し側で補完
            }
        }
    }

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

                toolbar
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
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { pending in
            Button(confirmActionLabel(pending), role: .destructive) {
                perform(pending)
            }
            Button(tr("キャンセル", "Cancel"), role: .cancel) {}
        } message: { pending in
            Text(confirmMessage(pending))
        }
    }

    // MARK: - ツールバー(選択モードで内容が切り替わる)

    @ViewBuilder
    private var toolbar: some View {
        if selectionMode {
            Text(tr("\(selectedIDs.count) 件選択中", "\(selectedIDs.count) selected"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                pendingDelete = .selected(selectedIDs)
            } label: {
                Label(tr("選択を削除", "Delete Selected"), systemImage: "trash")
                    .font(.system(size: 12))
            }
            .disabled(selectedIDs.isEmpty)

            Button {
                exitSelectionMode()
            } label: {
                Text(tr("完了", "Done"))
                    .font(.system(size: 12))
            }
        } else if !app.history.entries.isEmpty {
            Button {
                selectionMode = true
                selectedIDs = []
            } label: {
                Label(tr("選択", "Select"), systemImage: "checkmark.circle")
                    .font(.system(size: 12))
            }

            Button(role: .destructive) {
                pendingDelete = .all
            } label: {
                Label(tr("すべて削除", "Delete All"), systemImage: "trash")
                    .font(.system(size: 12))
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
        let isSelected = selectedIDs.contains(entry.id)
        // 本文は 6 行(約 360 字)、併記の音声入力は 2 行(約 120 字)で切り詰められる
        let isLong = Self.isClipped(mainText, lineLimit: 6, charBudget: 360)
            || (showsRaw && Self.isClipped(entry.raw, lineLimit: 2, charBudget: 120))

        return HStack(alignment: .top, spacing: 10) {
            // 選択モードのときだけ、行の先頭にチェックマークを出す
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Brand.secondary : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
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
                    // 選択モード中は行ごとの操作ボタンを隠す(タップは選択トグルに専念)
                    if !selectionMode {
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
                            pendingDelete = .single(entry)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(tr("削除", "Delete"))
                    }
                }

                Text(mainText)
                    .font(.system(size: 13))
                    .lineLimit(expanded ? nil : 6)
                    .textSelectionEnabled(!selectionMode)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 変換済みの場合は、元の音声入力も併記(コピー可)
                if showsRaw {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tr("音声入力", "Dictation"))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            if !selectionMode {
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
                        }
                        Text(entry.raw)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(expanded ? nil : 2)
                            .textSelectionEnabled(!selectionMode)
                    }
                }

                if isLong && !selectionMode {
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
        }
        .padding(14)
        .card(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Brand.secondary, lineWidth: isSelected ? 1.5 : 0)
        )
        // 選択モードでは行全体を選択トグルにする
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectionMode else { return }
            toggleSelection(entry.id)
        }
    }

    // MARK: - 選択・削除の処理

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func exitSelectionMode() {
        selectionMode = false
        selectedIDs = []
    }

    private func perform(_ pending: PendingDelete) {
        switch pending {
        case .single(let entry):
            app.history.delete(entry)
        case .selected(let ids):
            app.history.delete(ids: ids)
            exitSelectionMode()
        case .all:
            app.history.clear()
            exitSelectionMode()
        }
    }

    // MARK: - 確認ダイアログの文言

    private var confirmTitle: String {
        tr("履歴を削除しますか?", "Delete history?")
    }

    private func confirmActionLabel(_ pending: PendingDelete) -> String {
        switch pending {
        case .single:
            return tr("削除", "Delete")
        case .selected(let ids):
            return tr("\(ids.count) 件を削除", "Delete \(ids.count)")
        case .all:
            return tr("すべて削除", "Delete All")
        }
    }

    private func confirmMessage(_ pending: PendingDelete) -> String {
        switch pending {
        case .single:
            return tr("この履歴を削除します。この操作は取り消せません。",
                      "This entry will be deleted. This cannot be undone.")
        case .selected(let ids):
            return tr("\(ids.count) 件の履歴が削除されます。この操作は取り消せません。",
                      "This will delete \(ids.count) entries. This cannot be undone.")
        case .all:
            return tr("\(app.history.entries.count) 件の履歴が削除されます。この操作は取り消せません。",
                      "This will delete \(app.history.entries.count) entries. This cannot be undone.")
        }
    }
}

private extension View {
    /// テキスト選択の可否を Bool で切り替える。選択モード中は無効化して、
    /// 行タップ(選択トグル)がテキスト選択に奪われないようにする
    @ViewBuilder
    func textSelectionEnabled(_ enabled: Bool) -> some View {
        if enabled {
            textSelection(.enabled)
        } else {
            textSelection(.disabled)
        }
    }
}
