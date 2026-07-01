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

    // MARK: - ヒーロー

    private var hero: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("声で、AIに指示を。")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("どのアプリでも \(app.settings.value.hotkey.display) を押すだけ。話した内容をローカルLLMが整った指示文に変換します。")
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
                .help(app.phase == .recording ? "停止" : "音声入力を開始")
            }

            HStack(spacing: 8) {
                Chip(
                    text: "モード: \(app.settings.value.refineMode.label)",
                    icon: app.settings.value.refineMode.icon,
                    tint: .white
                )
                Chip(text: "モデル: \(app.settings.value.activeModelLabel)", icon: "cpu", tint: .white)
                if let premise = app.settings.value.activePremise, !premise.text.isEmpty {
                    Chip(text: "前提: \(premise.name)", icon: "doc.text", tint: .white)
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
            Text("セットアップ")
                .font(.system(size: 14, weight: .semibold))
                .padding(.bottom, 8)

            checklistRow(
                ok: micState == .granted,
                title: "マイク",
                detail: micState == .granted ? "許可済み" : "音声の取り込みに必要です",
                actionLabel: micState == .notDetermined ? "許可する" : "設定を開く"
            ) {
                if micState == .notDetermined {
                    Task { _ = await Permissions.ensureSpeechAndMic() }
                } else {
                    Permissions.openMicrophoneSettings()
                }
            }

            checklistRow(
                ok: speechState == .granted,
                title: "音声認識",
                detail: speechState == .granted ? "許可済み(オンデバイス処理)" : "音声をテキストに変換するために必要です",
                actionLabel: speechState == .notDetermined ? "許可する" : "設定を開く"
            ) {
                if speechState == .notDetermined {
                    Task { _ = await Permissions.ensureSpeechAndMic() }
                } else {
                    Permissions.openSpeechSettings()
                }
            }

            checklistRow(
                ok: axTrusted,
                title: "アクセシビリティ",
                detail: axTrusted
                    ? "許可済み"
                    : "自動貼り付けに必要です(任意)。許可しても反映されない場合は、システム設定の一覧から Koe を −(マイナス)で削除してから許可し直してください",
                actionLabel: "許可する"
            ) {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
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
            title: "Ollama(ローカルLLM実行環境)",
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
        if startingServer { return "起動中…" }
        switch app.ollama.status {
        case .running(let version): return "稼働中(v\(version))"
        case .installedNotRunning: return "インストール済みですが起動していません"
        case .notInstalled: return "無料の LLM 実行環境です。インストール後、このアプリからモデルを管理できます"
        case .unknown: return "確認中…"
        }
    }

    private var ollamaActionLabel: String {
        switch app.ollama.status {
        case .running: return "再確認"
        case .installedNotRunning: return "起動する"
        default: return "入手する"
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
                ? "使用中: \(app.settings.value.activeModelLabel)"
                : "整形に使うモデルをダウンロードしてください(推奨: Qwen3 4B)。追加のアプリは不要です"
        } else {
            ready = !app.ollama.installed.isEmpty
            detail = ready
                ? "\(app.ollama.installed.count) 個のモデルをインストール済み"
                : "整形に使うモデルをダウンロードしてください"
        }
        return checklistRow(
            ok: ready,
            title: "LLM モデル",
            detail: detail,
            actionLabel: ready ? "管理" : "ダウンロード"
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
            if !ok || actionLabel == "管理" || actionLabel == "再確認" {
                Button(actionLabel, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: - ガイド

    private var quickGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使い方")
                .font(.system(size: 14, weight: .semibold))

            HStack(alignment: .top, spacing: 14) {
                guideStep(
                    number: "1",
                    icon: "keyboard",
                    title: "呼び出す",
                    text: "どのアプリでも \(app.settings.value.hotkey.display) を押すと入力パネルが開き、すぐに聞き取りが始まります。"
                )
                guideStep(
                    number: "2",
                    icon: "waveform",
                    title: "話す",
                    text: "伝えたいことを自然に話すだけ。フィラーや言い直しは後で自動的に取り除かれます。"
                )
                guideStep(
                    number: "3",
                    icon: "sparkles",
                    title: "確定する",
                    text: "↩ でローカルLLMが指示文に整形。もう一度 ↩ でカーソル位置に貼り付きます。"
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
