import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var windowManager: WindowManager
    @State private var micState = Permissions.microphone
    @State private var speechState = Permissions.speech
    @State private var axTrusted = Permissions.accessibility
    @State private var startingServer = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let version = app.updater.availableVersion {
                    updateBanner(version)
                }
                if !app.hotkeyActive {
                    hotkeyBanner
                }
                hero
                setupChecklist
                quickGuide
            }
            .padding(24)
        }
        .onReceive(refreshTimer) { _ in
            micState = Permissions.microphone
            speechState = Permissions.speech
            axTrusted = Permissions.accessibility
        }
        .task {
            await app.ollama.refresh()
        }
    }

    // MARK: - バナー

    // 新バージョンの案内(直販版のアプリ内アップデート。設定でオフ可能)
    private func updateBanner(_ version: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Brand.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("新しいバージョン v\(version) があります", "Version \(version) is available"))
                    .font(.system(size: 13, weight: .medium))
                Text(tr("このままアプリ内でアップデートできます(完了後に自動で再起動します)",
                        "You can update right here; Youyaku restarts when it's done"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("アップデート", "Update")) {
                app.updater.checkForUpdates()
            }
            .controlSize(.small)
        }
        .padding(14)
        .card()
    }

    // ショートカット登録失敗の警告(他アプリとの競合など)
    private var hotkeyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("ショートカット \(app.settings.value.hotkey.display) を登録できませんでした",
                        "Couldn't register the \(app.settings.value.hotkey.display) shortcut"))
                    .font(.system(size: 13, weight: .medium))
                Text(tr("他のアプリやシステムと競合している可能性があります。設定で別のキーに変更してください。",
                        "It may conflict with another app or the system. Please choose a different key in Settings."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("設定を開く", "Open Settings")) {
                windowManager.tab = .settings
            }
            .controlSize(.small)
        }
        .padding(14)
        .card()
    }

    // MARK: - ヒーロー

    private var hero: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("声で、AIに指示を。", "Give AI instructions with your voice."))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(tr("どのアプリでも \(app.settings.value.hotkey.display) を押すだけ。話した内容をローカルLLMが整った指示文に変換します。", "Just press \(app.settings.value.hotkey.display) in any app. A local LLM turns what you say into a polished prompt."))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    app.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(.white)
                            .frame(width: 60, height: 60)
                        Image(systemName: app.phase == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Brand.primary)
                    }
                }
                .buttonStyle(.plain)
                .help(app.phase == .recording ? tr("停止", "Stop") : tr("音声入力を開始", "Start Dictation"))
            }

            HStack(spacing: 8) {
                Chip(
                    text: tr("モード: \(app.settings.value.refineMode.label)", "Mode: \(app.settings.value.refineMode.label)"),
                    icon: app.settings.value.refineMode.icon,
                    tint: .white
                )
                Chip(text: tr("モデル: \(app.settings.value.activeModelLabel)", "Model: \(app.settings.value.activeModelLabel)"), icon: "cpu", tint: .white)
                if app.settings.value.refineMode == .template,
                   let template = app.settings.value.activeTemplate {
                    Chip(text: tr("テンプレート: \(template.name)", "Template: \(template.name)"), icon: "list.bullet.rectangle", tint: .white)
                }
                if let premise = app.settings.value.activePremise, !premise.text.isEmpty {
                    Chip(text: tr("前提: \(premise.name)", "Context: \(premise.name)"), icon: "doc.text", tint: .white)
                }
                Spacer()
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Brand.gradient)
                .shadow(color: Brand.primary.opacity(0.35), radius: 18, y: 8)
        )
    }

    // MARK: - セットアップ

    private var setupChecklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("セットアップ", "Setup"))
                .font(.system(size: 14, weight: .semibold))
                .padding(.bottom, 8)

            checklistRow(
                ok: micState == .granted,
                title: tr("マイク", "Microphone"),
                detail: micState == .granted ? tr("許可済み", "Granted") : tr("音声の取り込みに必要です", "Required to capture audio"),
                actionLabel: micState == .notDetermined ? tr("許可する", "Allow") : tr("設定を開く", "Open Settings")
            ) {
                if micState == .notDetermined {
                    Task { _ = await Permissions.ensureSpeechAndMic() }
                } else {
                    Permissions.openMicrophoneSettings()
                }
            }

            checklistRow(
                ok: speechState == .granted,
                title: tr("音声認識", "Speech Recognition"),
                detail: speechState == .granted ? tr("許可済み(オンデバイス処理)", "Granted (processed on-device)") : tr("音声をテキストに変換するために必要です", "Required to convert speech to text"),
                actionLabel: speechState == .notDetermined ? tr("許可する", "Allow") : tr("設定を開く", "Open Settings")
            ) {
                if speechState == .notDetermined {
                    Task { _ = await Permissions.ensureSpeechAndMic() }
                } else {
                    Permissions.openSpeechSettings()
                }
            }

            checklistRow(
                ok: axTrusted,
                title: tr("アクセシビリティ", "Accessibility"),
                detail: axTrusted
                    ? tr("許可済み", "Granted")
                    : tr("自動貼り付けに必要です(任意)。ボタンを押すと古い登録を自動でリセットしてから許可を求めます", "Required for auto-paste (optional). Pressing the button clears any stale registration before requesting access."),
                actionLabel: tr("許可する", "Allow")
            ) {
                // 再ビルド等で無効化された古い登録が残っていると、システム設定の
                // トグルが ON でも実際には許可されない。先にリセットして自己修復する
                Permissions.resetAccessibilityRegistration()
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }

            // 登録に成功している間は表示しない(失敗時だけ気付けるようにする)
            if !app.hotkeyActive {
                checklistRow(
                    ok: false,
                    title: tr("ショートカット", "Shortcut"),
                    detail: tr("\(app.settings.value.hotkey.display) を登録できませんでした(他アプリと競合)。別のキーに変更してください",
                               "Couldn't register \(app.settings.value.hotkey.display) (conflicts with another app). Please choose a different key."),
                    actionLabel: tr("設定を開く", "Open Settings")
                ) {
                    windowManager.tab = .settings
                }
            }

            if app.settings.value.engine == .ollama {
                ollamaRow
            }

            modelRow
        }
        .padding(20)
        .card()
    }

    @ViewBuilder
    private var ollamaRow: some View {
        let running = app.ollama.status.isRunning
        checklistRow(
            ok: running,
            title: tr("Ollama(ローカルLLM実行環境)", "Ollama (Local LLM Runtime)"),
            detail: ollamaDetail,
            actionLabel: ollamaActionLabel
        ) {
            switch app.ollama.status {
            case .notInstalled:
                NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
            case .installedNotRunning:
                startingServer = true
                Task {
                    _ = await app.ollama.startServer()
                    startingServer = false
                }
            default:
                Task { await app.ollama.refresh() }
            }
        }
    }

    private var ollamaDetail: String {
        if startingServer { return tr("起動中…", "Starting…") }
        switch app.ollama.status {
        case .running(let version): return tr("稼働中(v\(version))", "Running (v\(version))")
        case .installedNotRunning: return tr("インストール済みですが起動していません", "Installed but not running")
        case .notInstalled: return tr("無料の LLM 実行環境です。インストール後、このアプリからモデルを管理できます", "A free LLM runtime. After installing, you can manage models from this app.")
        case .unknown: return tr("確認中…", "Checking…")
        }
    }

    private var ollamaActionLabel: String {
        switch app.ollama.status {
        case .running: return tr("再確認", "Recheck")
        case .installedNotRunning: return tr("起動する", "Start")
        default: return tr("入手する", "Get")
        }
    }

    private var modelRow: some View {
        let ready: Bool
        let detail: String
        if app.settings.value.engine == .builtin {
            ready = app.settings.value.builtinModelFile.map { file in
                app.modelStore.installed.contains { $0.fileName == file }
            } ?? false
            detail = ready
                ? tr("使用中: \(app.settings.value.activeModelLabel)", "In use: \(app.settings.value.activeModelLabel)")
                : tr("整形に使うモデルをダウンロードしてください(推奨: Qwen3 4B)。追加のアプリは不要です", "Download a model for refining (recommended: Qwen3 4B). No extra apps needed.")
        } else {
            ready = !app.ollama.installed.isEmpty
            detail = ready
                ? tr("\(app.ollama.installed.count) 個のモデルをインストール済み", "\(app.ollama.installed.count) models installed")
                : tr("整形に使うモデルをダウンロードしてください", "Download a model for refining")
        }
        return checklistRow(
            ok: ready,
            title: tr("LLM モデル", "LLM Model"),
            detail: detail,
            actionLabel: ready ? tr("管理", "Manage") : tr("ダウンロード", "Download")
        ) {
            windowManager.tab = .models
        }
    }

    private func checklistRow(ok: Bool, title: String, detail: String, actionLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(ok ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !ok || actionLabel == tr("管理", "Manage") || actionLabel == tr("再確認", "Recheck") {
                Button(actionLabel, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: - ガイド

    private var quickGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("使い方", "How It Works"))
                .font(.system(size: 14, weight: .semibold))

            HStack(alignment: .top, spacing: 14) {
                guideStep(
                    number: "1",
                    icon: "keyboard",
                    title: tr("呼び出す", "Invoke"),
                    text: tr("どのアプリでも \(app.settings.value.hotkey.display) を押すと入力パネルが開き、すぐに聞き取りが始まります。", "Press \(app.settings.value.hotkey.display) in any app to open the input panel and start listening right away.")
                )
                guideStep(
                    number: "2",
                    icon: "waveform",
                    title: tr("話す", "Speak"),
                    text: tr("伝えたいことを自然に話すだけ。フィラーや言い直しは後で自動的に取り除かれます。", "Just say what you mean, naturally. Filler words and false starts are removed automatically.")
                )
                guideStep(
                    number: "3",
                    icon: "sparkles",
                    title: tr("確定する", "Confirm"),
                    text: tr("↩ でローカルLLMが指示文に整形。もう一度 ↩ でカーソル位置に貼り付きます。", "Press ↩ to let the local LLM refine your prompt, then ↩ again to paste it at the cursor.")
                )
            }
        }
        .padding(20)
        .card()
    }

    private func guideStep(number: String, icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Brand.gradient))
                Image(systemName: icon)
                    .foregroundStyle(Brand.primary)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
