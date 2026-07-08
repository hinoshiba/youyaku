import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @State private var showLicenses = false
    @State private var hotkeyRejection: String?   // レコーダーが拒否した組み合わせの理由表示

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                shortcutSection
                premiseSection
                refineSection
                speechSection
                outputSection
                generalSection
            }
            .padding(24)
        }
    }

    private func sectionHeader(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func settingRow<Content: View>(_ label: String, help: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5))
                if let help {
                    Text(help)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            content()
        }
        .padding(.vertical, 6)
    }

    // MARK: - ショートカット

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(tr("ショートカット", "Shortcut"), tr("どのアプリからでも音声入力を呼び出せます", "Start dictation from any app"))

            settingRow(tr("音声入力の開始 / 停止", "Start / Stop Dictation"), help: tr("枠をクリックして好きなキーを入力(修飾キー、またはF1〜F20)", "Click the field, then press a key (modifier combo, or F1–F20)")) {
                HStack(spacing: 8) {
                    HotkeyRecorderView(combo: app.settings.value.hotkey, onChange: { newCombo in
                        hotkeyRejection = nil
                        app.updateHotkey(newCombo)
                    }, onReject: { reason in
                        hotkeyRejection = reason
                    })
                    if app.settings.value.hotkey != .default {
                        Button {
                            hotkeyRejection = nil
                            app.updateHotkey(.default)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("デフォルト(⌥Space)に戻す", "Reset to default (⌥Space)"))
                    }
                }
            }

            if !app.hotkeyActive {
                Label(tr("この組み合わせは他のアプリやシステムと競合しているため登録できませんでした。別のキーをお試しください(直前のショートカットは有効なままです)。",
                         "This combination conflicts with another app or the system and couldn't be registered. Please try a different key (your previous shortcut is still active)."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hotkeyRejection {
                Label(hotkeyRejection, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(tr("候補:", "Suggestions:"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(Self.presets, id: \.display) { preset in
                    let isCurrent = app.settings.value.hotkey == preset
                    Button {
                        hotkeyRejection = nil
                        app.updateHotkey(preset)
                    } label: {
                        Text(preset.display)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(isCurrent ? Brand.primary.opacity(0.18) : Color.primary.opacity(0.06))
                            )
                            .overlay(
                                Capsule().strokeBorder(isCurrent ? Brand.primary.opacity(0.5) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(18)
        .card()
    }

    // よく使う競合しにくい候補
    private static let presets: [KeyCombo] = [
        .default,                                                              // ⌥Space
        KeyCombo(keyCode: 49, carbonModifiers: 4096 | 2048),                   // ⌃⌥Space
        KeyCombo(keyCode: 49, carbonModifiers: 512 | 2048),                   // ⇧⌥Space
        KeyCombo(keyCode: 96, carbonModifiers: 0),                            // F5
    ]

    // MARK: - 前提プリセット

    private var premiseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                tr("前提プリセット", "Context Presets"),
                tr("命令を整理するときに考慮させる背景情報です。プロジェクトや用途ごとに切り替えられます。",
                   "Background information considered when refining your prompt. Switch between presets per project or use case.")
            )
            PremiseEditorView()
        }
        .padding(18)
        .card()
    }

    // MARK: - 整形

    private var refineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(tr("整形", "Refinement"), tr("音声認識の結果をローカルLLMでどう処理するか", "How the local LLM processes speech recognition results"))

            settingRow(tr("既定のモード", "Default Mode")) {
                Picker("", selection: $app.config.refineMode) {
                    ForEach(RefineMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }
            Text(app.settings.value.refineMode.help)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 6)

            settingRow(tr("創造性(temperature)", "Creativity (Temperature)"), help: tr("低いほど忠実、高いほど言い換えが大胆になります", "Lower stays faithful to your words; higher allows bolder rewording")) {
                HStack(spacing: 8) {
                    Slider(value: $app.config.temperature, in: 0...1, step: 0.05)
                        .frame(width: 160)
                    Text(String(format: "%.2f", app.settings.value.temperature))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34)
                }
            }
        }
        .padding(18)
        .card()
    }

    // MARK: - 音声認識

    private var speechSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(tr("音声認識", "Speech Recognition"), tr("macOS 内蔵エンジンを使用します。既定ではこの Mac 上で認識されます", "Uses the built-in macOS engine. By default, recognition runs on this Mac."))

            settingRow(tr("言語", "Language")) {
                Picker("", selection: $app.config.localeID) {
                    ForEach(AppSettings.speechLocales) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            settingRow(tr("マイク", "Microphone"), help: tr("録音に使う入力デバイスを選べます。次回の録音から反映されます", "Choose the input device for recording. Applies to your next recording.")) {
                MicrophonePicker()
            }

            settingRow(tr("オンデバイス認識を優先", "Prefer On-Device Recognition"), help: tr("既定(ON)ではネットワークに音声を送らず、この Mac 上だけで処理します。オンデバイス非対応の言語ではエラーになります", "By default (on), audio never leaves this Mac. Languages without on-device support will show an error.")) {
                Toggle("", isOn: $app.config.preferOnDevice)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if !app.settings.value.preferOnDevice {
                Label(tr("オフにすると、音声認識に Apple のサーバーが使用され、音声がネットワークに送信されます。",
                         "When this is off, Apple's server-based recognition is used and your audio is sent over the network."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingRow(tr("句読点を自動挿入", "Auto-Insert Punctuation")) {
                Toggle("", isOn: $app.config.punctuation)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow(tr("無音で自動停止", "Auto-Stop on Silence"), help: tr("話し終えると自動的に録音を止めます", "Stops recording automatically when you finish speaking")) {
                HStack(spacing: 10) {
                    if app.settings.value.autoStop {
                        Picker("", selection: $app.config.autoStopSeconds) {
                            Text(tr("1.5 秒", "1.5 sec")).tag(1.5)
                            Text(tr("2 秒", "2 sec")).tag(2.0)
                            Text(tr("3 秒", "3 sec")).tag(3.0)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    Toggle("", isOn: $app.config.autoStop)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Divider().padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("認識辞書(固有名詞・専門用語)", "Vocabulary (Proper Nouns & Technical Terms)"))
                        .font(.system(size: 12.5))
                    Spacer()
                    Text(tr("\(app.settings.value.vocabularyList.count) 語", "\(app.settings.value.vocabularyList.count) terms"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Text(tr("登録した用語は認識時に優先され、固有名詞の誤変換が減ります。",
                        "Registered terms are prioritized during recognition, reducing misrecognition of proper nouns."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                VocabularyEditorView()
            }
            .padding(.vertical, 6)
        }
        .padding(18)
        .card()
    }

    // MARK: - 出力

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(tr("出力", "Output"))

            settingRow(tr("確定時にカーソル位置へ自動貼り付け", "Paste at Cursor on Confirm"), help: tr("アクセシビリティ権限が必要です", "Requires Accessibility permission")) {
                Toggle("", isOn: $app.config.autoPaste)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow(tr("クリップボードに残す", "Keep in Clipboard"), help: tr("オフにすると貼り付け後に元のクリップボード内容を復元します", "When off, the previous clipboard contents are restored after pasting")) {
                Toggle("", isOn: $app.config.keepInClipboard)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow(tr("整形後すぐに確定", "Confirm Right After Refining"), help: tr("確認パネルを表示せず、整形が終わり次第すぐ貼り付けます", "Skips the confirmation panel and pastes as soon as refining finishes")) {
                Toggle("", isOn: $app.config.instantPaste)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow(tr("効果音", "Sound Effects")) {
                Toggle("", isOn: $app.config.sounds)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .padding(18)
        .card()
    }

    // MARK: - 一般

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(tr("一般", "General"))

            settingRow(tr("表示言語", "App Language"),
                       help: tr("メニューや画面の表示言語です。整形結果の言語は「音声認識 > 言語」に追従します",
                                "Language for menus and screens. The output language follows Speech Recognition > Language")) {
                Picker("", selection: $app.config.uiLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            settingRow(tr("ログイン時に起動", "Launch at Login")) {
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = tr("設定に失敗しました: \(error.localizedDescription)", "Failed to change setting: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            settingRow(tr("アップデートを自動確認", "Check for Updates Automatically"),
                       help: tr("1日1回、youyaku.hinoshiba.com から最新バージョン番号のみを取得します。それ以外の情報は送信しません。",
                                "Fetches only the latest version number from youyaku.hinoshiba.com once a day. No other information is sent.")) {
                Toggle("", isOn: $app.config.checkForUpdates)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow(tr("Ollama ホスト", "Ollama Host"), help: tr("通常は変更不要です", "Usually doesn't need to be changed")) {
                TextField("", text: $app.config.ollamaHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 220)
                    .onSubmit {
                        Task { await app.ollama.refresh() }
                    }
            }
            Label(tr("外部ホストを指定すると、整形対象のテキストがそのホストへ送信されます(http の場合は暗号化されません)。",
                     "If you point this to an external host, the text being refined is sent to that host (unencrypted over http)."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 6)

            settingRow(tr("プライバシーポリシー・利用規約", "Privacy Policy & Terms"),
                       help: tr("収集しない情報・外部通信の内容・利用条件の説明", "What we don't collect, what network access occurs, and the terms of use")) {
                HStack(spacing: 12) {
                    Link(tr("プライバシー", "Privacy"), destination: URL(string: "https://youyaku.hinoshiba.com/privacy.html")!)
                    Link(tr("利用規約", "Terms"), destination: URL(string: "https://youyaku.hinoshiba.com/terms.html")!)
                }
                .font(.system(size: 12))
            }

            settingRow(tr("オープンソースライセンス", "Open-Source Licenses"),
                       help: tr("本アプリが利用する第三者ソフトウェア・モデルの表示", "Third-party software and models used by this app")) {
                Button(tr("表示", "Show")) { showLicenses = true }
                    .controlSize(.small)
            }
        }
        .padding(18)
        .card()
        .sheet(isPresented: $showLicenses) {
            LicenseSheet(isPresented: $showLicenses)
        }
    }
}

// MARK: - ライセンス表示

struct LicenseSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("ライセンス", "Licenses"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(tr("閉じる", "Close")) { isPresented = false }
            }
            .padding(16)
            Divider()
            ScrollView {
                Text(Licenses.thirdPartyText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - 認識辞書エディタ

struct VocabularyEditorView: View {
    @EnvironmentObject var app: AppState
    @State private var newTerm = ""

    var body: some View {
        VStack(spacing: 0) {
            if app.settings.value.vocabularyTerms.isEmpty {
                Text(tr("まだ用語がありません。下の欄から追加してください。",
                        "No terms yet. Add one below."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(app.settings.value.vocabularyTerms.enumerated()), id: \.offset) { index, term in
                            HStack(spacing: 8) {
                                Image(systemName: "character.book.closed")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(term)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    app.config.vocabularyTerms.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(tr("削除", "Remove"))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            if index < app.settings.value.vocabularyTerms.count - 1 {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            Divider()

            HStack(spacing: 8) {
                TextField(tr("新しい用語(例: Kubernetes)。カンマ・改行区切りで一括追加も可",
                             "New term (e.g. Kubernetes). Paste comma/newline-separated for bulk add"),
                          text: $newTerm)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { addTerms() }
                Button {
                    addTerms()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(newTerm.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Brand.primary)
                }
                .buttonStyle(.plain)
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(tr("追加", "Add"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    // 入力を用語に分解して追加(重複は除外)。カンマ・読点・改行での一括貼り付けに対応
    private func addTerms() {
        let terms = AppSettings.splitTerms(newTerm)
        guard !terms.isEmpty else { return }
        var existing = Set(app.settings.value.vocabularyTerms)
        for term in terms where !existing.contains(term) {
            app.config.vocabularyTerms.append(term)
            existing.insert(term)
        }
        newTerm = ""
    }
}

// MARK: - 前提プリセットエディタ

struct PremiseEditorView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedID: UUID?

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return app.settings.value.premises.firstIndex { $0.id == selectedID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左: プリセット一覧
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(app.settings.value.premises) { preset in
                        HStack(spacing: 6) {
                            Image(systemName: preset.id == app.settings.value.activePremiseID
                                  ? "checkmark.circle.fill" : "doc.text")
                                .font(.system(size: 11))
                                .foregroundStyle(preset.id == app.settings.value.activePremiseID
                                                 ? Brand.primary : .secondary)
                            Text(preset.name.isEmpty ? tr("名称未設定", "Untitled") : preset.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .tag(preset.id)
                    }
                }
                .listStyle(.plain)
                .frame(height: 180)

                Divider()

                HStack(spacing: 2) {
                    Button {
                        var preset = PremisePreset(name: tr("新しいプリセット", "New Preset"), text: "")
                        preset.id = UUID()
                        app.settings.value.premises.append(preset)
                        selectedID = preset.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        if let index = selectedIndex {
                            let removed = app.settings.value.premises.remove(at: index)
                            if app.settings.value.activePremiseID == removed.id {
                                app.settings.value.activePremiseID = app.settings.value.premises.first?.id
                            }
                            selectedID = app.settings.value.premises.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedIndex == nil || app.settings.value.premises.count <= 1)

                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 190)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08))
            )

            // 右: 編集
            VStack(alignment: .leading, spacing: 10) {
                if let index = selectedIndex {
                    TextField(tr("プリセット名", "Preset Name"), text: $app.config.premises[index].name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))

                    TextEditor(text: $app.config.premises[index].text)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 140)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.08))
                        )

                    HStack {
                        Text(tr("例: 使用技術、対象読者、出力形式の指定など", "e.g. tech stack, target audience, output format"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if app.settings.value.activePremiseID != app.settings.value.premises[index].id {
                            Button(tr("このプリセットを使用", "Use This Preset")) {
                                app.settings.value.activePremiseID = app.settings.value.premises[index].id
                            }
                            .controlSize(.small)
                        } else {
                            Label(tr("使用中", "Active"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.primary)
                        }
                    }
                } else {
                    Spacer()
                    Text(tr("左の一覧からプリセットを選択してください", "Select a preset from the list on the left"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
            }
            .padding(.leading, 14)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            selectedID = app.settings.value.activePremiseID ?? app.settings.value.premises.first?.id
        }
    }
}

// MARK: - ホットキーレコーダー

struct HotkeyRecorderView: View {
    var combo: KeyCombo
    var onChange: (KeyCombo) -> Void
    var onReject: ((String) -> Void)? = nil   // 拒否した組み合わせの理由通知(表示は呼び出し側)

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            Text(recording ? tr("キーを入力…", "Press a key…") : combo.display)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(recording ? Color.orange : Color.primary)
                .frame(minWidth: 130)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(recording ? Color.orange : Color.primary.opacity(0.15))
                        )
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc でキャンセル
                stopRecording()
                return nil
            }
            if let newCombo = KeyCombo.from(event: event) {
                // ⌘Q・⌘V などのシステム基本ショートカットは登録させない
                if newCombo.isSystemReserved {
                    onReject?(tr("\(newCombo.display) はシステムの基本ショートカットのため使用できません。別の組み合わせをお試しください。",
                                 "\(newCombo.display) is a basic system shortcut and can't be used. Please try a different combination."))
                    stopRecording()
                    return nil
                }
                onChange(newCombo)
                stopRecording()
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

// MARK: - マイク選択

struct MicrophonePicker: View {
    @EnvironmentObject var app: AppState
    @State private var devices: [MicDevice] = []

    var body: some View {
        Picker("", selection: $app.config.inputDeviceUID) {
            Text(tr("システム標準", "System Default")).tag(String?.none)
            // 保存済みだが現在は見つからないデバイス(未接続)も選択肢として残す
            if let uid = app.settings.value.inputDeviceUID,
               !devices.contains(where: { $0.uid == uid }) {
                Text(tr("\(AudioDevices.name(forUID: uid) ?? "未接続のマイク")(未接続)",
                        "\(AudioDevices.name(forUID: uid) ?? "Disconnected mic") (unavailable)"))
                    .tag(String?.some(uid))
            }
            ForEach(devices) { device in
                Text(device.name).tag(String?.some(device.uid))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
        .onAppear { devices = AudioDevices.inputDevices() }
    }
}
