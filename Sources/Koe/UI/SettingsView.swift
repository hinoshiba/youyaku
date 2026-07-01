import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

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
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("ショートカット", "どのアプリからでも音声入力を呼び出せます")
            settingRow("音声入力の開始 / 停止") {
                HotkeyRecorderView(combo: app.settings.value.hotkey) { newCombo in
                    app.updateHotkey(newCombo)
                }
            }
        }
        .padding(18)
        .card()
    }

    // MARK: - 前提プリセット

    private var premiseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "前提プリセット",
                "命令を整理するときに考慮させる背景情報です。プロジェクトや用途ごとに切り替えられます。"
            )
            PremiseEditorView()
        }
        .padding(18)
        .card()
    }

    // MARK: - 整形

    private var refineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("整形", "音声認識の結果をローカルLLMでどう処理するか")

            settingRow("既定のモード") {
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

            settingRow("創造性(temperature)", help: "低いほど忠実、高いほど言い換えが大胆になります") {
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
            sectionHeader("音声認識", "認識は macOS 内蔵エンジンでデバイス上で行われます")

            settingRow("言語") {
                Picker("", selection: $app.config.localeID) {
                    Text("日本語").tag("ja-JP")
                    Text("English (US)").tag("en-US")
                    Text("中文(简体)").tag("zh-CN")
                    Text("한국어").tag("ko-KR")
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            settingRow("オンデバイス認識を優先", help: "ネットワークに音声を送らず、Mac 内で処理します") {
                Toggle("", isOn: $app.config.preferOnDevice)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow("句読点を自動挿入") {
                Toggle("", isOn: $app.config.punctuation)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow("無音で自動停止", help: "話し終えると自動的に録音を止めます") {
                HStack(spacing: 10) {
                    if app.settings.value.autoStop {
                        Picker("", selection: $app.config.autoStopSeconds) {
                            Text("1.5 秒").tag(1.5)
                            Text("2 秒").tag(2.0)
                            Text("3 秒").tag(3.0)
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
                Text("認識辞書(専門用語)")
                    .font(.system(size: 12.5))
                Text("固有名詞や専門用語をカンマ区切りで登録すると、認識精度が上がります。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                TextField("例: Kubernetes, リファクタリング, PostgreSQL", text: $app.config.vocabulary, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.system(size: 12))
            }
            .padding(.vertical, 6)
        }
        .padding(18)
        .card()
    }

    // MARK: - 出力

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("出力")

            settingRow("確定時にカーソル位置へ自動貼り付け", help: "アクセシビリティ権限が必要です") {
                Toggle("", isOn: $app.config.autoPaste)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow("クリップボードに残す", help: "オフにすると貼り付け後に元のクリップボード内容を復元します") {
                Toggle("", isOn: $app.config.keepInClipboard)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow("整形後すぐに確定", help: "確認パネルを表示せず、整形が終わり次第すぐ貼り付けます") {
                Toggle("", isOn: $app.config.instantPaste)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            settingRow("効果音") {
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
            sectionHeader("一般")

            settingRow("ログイン時に起動") {
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
                            loginItemError = "設定に失敗しました: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            settingRow("Ollama ホスト", help: "通常は変更不要です") {
                TextField("", text: $app.config.ollamaHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 220)
                    .onSubmit {
                        Task { await app.ollama.refresh() }
                    }
            }
        }
        .padding(18)
        .card()
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
                            Text(preset.name.isEmpty ? "名称未設定" : preset.name)
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
                        var preset = PremisePreset(name: "新しいプリセット", text: "")
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
                    TextField("プリセット名", text: $app.config.premises[index].name)
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
                        Text("例: 使用技術、対象読者、出力形式の指定など")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if app.settings.value.activePremiseID != app.settings.value.premises[index].id {
                            Button("このプリセットを使用") {
                                app.settings.value.activePremiseID = app.settings.value.premises[index].id
                            }
                            .controlSize(.small)
                        } else {
                            Label("使用中", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.primary)
                        }
                    }
                } else {
                    Spacer()
                    Text("左の一覧からプリセットを選択してください")
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

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            Text(recording ? "キーを入力…(修飾キー必須)" : combo.display)
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
