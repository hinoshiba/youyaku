import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    @State private var shareText: String?
    @State private var editMode: EditMode = .inactive   // 複数選択モードの状態
    @State private var selection: Set<UUID> = []         // 選択中のエントリ ID
    @State private var pendingDelete: PendingDelete?     // 削除確認の対象。nil なら非表示

    // 削除確認の対象種別。1 つのダイアログで単一・複数・全部を扱う
    private enum PendingDelete {
        case single(HistoryEntry)
        case selected(Set<UUID>)
        case all
    }

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
                    List(selection: $selection) {
                        ForEach(filtered) { entry in
                            row(entry)
                        }
                        .onDelete { indexSet in
                            // スワイプ削除でも確認を挟むため、その場では消さず対象を控える
                            if let i = indexSet.first {
                                pendingDelete = .single(filtered[i])
                            }
                        }
                    }
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle(tr("履歴", "History"))
            .searchable(text: $query, prompt: tr("履歴を検索", "Search history"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode.isEditing {
                        Button(tr("完了", "Done")) { exitEditMode() }
                    } else if !app.history.entries.isEmpty {
                        Menu {
                            Button {
                                selection = []
                                editMode = .active
                            } label: {
                                Label(tr("選択", "Select"), systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                pendingDelete = .all
                            } label: {
                                Label(tr("すべて削除", "Delete All"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if editMode.isEditing {
                        Button(role: .destructive) {
                            pendingDelete = .selected(selection)
                        } label: {
                            Label(
                                selection.isEmpty
                                    ? tr("選択を削除", "Delete Selected")
                                    : tr("\(selection.count) 件を削除", "Delete \(selection.count)"),
                                systemImage: "trash"
                            )
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog(
                tr("履歴を削除しますか?", "Delete history?"),
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
        .tag(entry.id)   // List(selection:) が UUID で選択を追跡できるようにする
    }

    // MARK: - 選択・削除の処理

    private func exitEditMode() {
        editMode = .inactive
        selection = []
    }

    private func perform(_ pending: PendingDelete) {
        switch pending {
        case .single(let entry):
            app.history.delete(entry)
        case .selected(let ids):
            app.history.delete(ids: ids)
            exitEditMode()
        case .all:
            app.history.clear()
            exitEditMode()
        }
    }

    // MARK: - 確認ダイアログの文言

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
