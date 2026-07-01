import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable {
        case idle
        case recording
        case refining
        case result
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var transcript = ""
    @Published var refined = ""
    @Published var statusMessage: String?
    @Published var hotkeyActive = true   // ショートカットの登録に成功しているか

    let settings = SettingsStore()

    // SwiftUI から `$app.config.xxx` で設定への Binding を作るための窓口
    var config: AppSettings {
        get { settings.value }
        set { settings.value = newValue }
    }

    let history = HistoryStore()
    let speech = SpeechRecognizer()
    let modelStore = ModelStore()
    let llamaEngine = LlamaEngine.shared
    lazy var ollama = OllamaClient(settings: settings)
    lazy var hud = HUDController(appState: self)

    private var refineTask: Task<Void, Never>?
    private var dismissWork: DispatchWorkItem?
    private var isStopping = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    // 子ストアの変更を自身の変更として再発行し、AppState を観測する
    // ビュー(メニューバー・HUD 等)を確実に再描画させる
    private func bridgeChildChanges() {
        for publisher in [
            settings.objectWillChange.eraseToAnyPublisher(),
            history.objectWillChange.eraseToAnyPublisher(),
            speech.objectWillChange.eraseToAnyPublisher(),
            ollama.objectWillChange.eraseToAnyPublisher(),
            modelStore.objectWillChange.eraseToAnyPublisher(),
        ] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: - 起動処理

    func bootstrap() {
        bridgeChildChanges()
        HotkeyManager.shared.onHotkey = { [weak self] in self?.toggle() }
        hotkeyActive = HotkeyManager.shared.register(settings.value.hotkey)
        speech.onAutoStop = { [weak self] in
            Task { await self?.finishRecording() }
        }
        // ダウンロード=そのモデルを使いたいという意思表示なので、完了時に自動で切り替える
        modelStore.onInstalled = { [weak self] fileName in
            guard let self else { return }
            self.settings.value.builtinModelFile = fileName
            self.llamaEngine.unload()
        }
        // 未選択でモデルがある場合はカタログの推奨順に選ぶ(手動配置・再インストール対応)
        if settings.value.builtinModelFile == nil,
           let best = Self.preferredModel(from: modelStore.installed) {
            settings.value.builtinModelFile = best.fileName
        }
        if settings.value.engine == .ollama {
            Task { await ollama.refresh() }
        }

        if !settings.value.onboarded {
            settings.value.onboarded = true
            WindowManager.shared.show(tab: .home)
        }
    }

    /// ショートカットを変更する。登録に成功したら true。
    /// 競合などで失敗した場合は設定を元に戻し、既存のショートカットを維持する。
    @discardableResult
    func updateHotkey(_ combo: KeyCombo) -> Bool {
        let ok = HotkeyManager.shared.register(combo)
        if ok {
            settings.value.hotkey = combo
        }
        hotkeyActive = ok
        return ok
    }

    // MARK: - セッション制御

    func toggle() {
        switch phase {
        case .idle:
            startRecording()
        case .recording:
            Task { await finishRecording() }
        case .refining:
            cancelRefine()
        case .result, .error:
            dismiss()
            startRecording()
        }
    }

    func startRecording() {
        guard phase == .idle else { return }
        dismissWork?.cancel()
        statusMessage = nil
        transcript = ""
        refined = ""

        Task {
            let permission = await Permissions.ensureSpeechAndMic()
            guard permission.ok else {
                phase = .error(permission.message)
                hud.show()
                return
            }
            do {
                let s = settings.value
                try speech.start(SpeechRecognizer.Config(
                    locale: Locale(identifier: s.localeID),
                    preferOnDevice: s.preferOnDevice,
                    punctuation: s.punctuation,
                    vocabulary: s.vocabularyList,
                    autoStopAfter: s.autoStop ? s.autoStopSeconds : nil
                ))
                phase = .recording
                hud.show()
                playSound("Pop")
            } catch {
                phase = .error(error.localizedDescription)
                hud.show()
            }
        }
    }

    func finishRecording() async {
        // await 中に phase が .recording のままになるため、再入をフラグで防ぐ
        guard phase == .recording, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        playSound("Tink")
        let text = await speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = text

        guard !text.isEmpty else {
            phase = .error("音声を聞き取れませんでした。もう一度お試しください。")
            return
        }

        if settings.value.refineMode == .raw {
            refined = text
            phase = .result
            maybeInstantPaste()
        } else {
            refine()
        }
    }

    func refine() {
        let s = settings.value

        let stream: AsyncThrowingStream<String, Error>
        let modelLabel = s.activeModelLabel

        switch s.engine {
        case .builtin:
            guard let file = s.builtinModelFile,
                  let local = modelStore.installed.first(where: { $0.fileName == file }) else {
                refined = transcript
                statusMessage = "LLM モデルが未設定のため、認識結果をそのまま表示しています(「モデル」画面からダウンロードできます)"
                phase = .result
                return
            }
            let (system, user) = Refiner.prompts(
                mode: s.refineMode, premise: s.activePremise,
                transcript: transcript, modelHint: file
            )
            stream = llamaEngine.chatStream(
                modelPath: local.fileURL.path,
                system: system,
                user: user,
                temperature: s.temperature
            )
        case .ollama:
            guard ollama.status.isRunning else {
                refined = transcript
                statusMessage = "Ollama が起動していないため、認識結果をそのまま表示しています"
                phase = .result
                return
            }
            let (system, user) = Refiner.prompts(
                mode: s.refineMode, premise: s.activePremise,
                transcript: transcript, modelHint: s.model
            )
            stream = ollama.chatStream(
                model: s.model,
                system: system,
                prompt: user,
                temperature: s.temperature
            )
        }

        dismissWork?.cancel()   // 予約済みの自動クローズが整形中に発火しないように
        phase = .refining
        refined = ""

        refineTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 思考モデル(qwen3 等)の <think> ブロックはストリーミング中も隠す
                var raw = ""
                for try await token in stream {
                    try Task.checkCancellation()
                    raw += token
                    self.refined = Self.visibleText(raw)
                }
                // キャンセル済み・セッション終了済みなら結果を適用しない(誤貼り付け防止)
                try Task.checkCancellation()
                guard self.phase == .refining else { return }
                self.refined = Self.visibleText(raw)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if self.refined.isEmpty {
                    self.refined = self.transcript
                    self.statusMessage = "整形結果が空だったため、認識結果をそのまま表示しています"
                }
                self.phase = .result
                self.maybeInstantPaste()
            } catch is CancellationError {
                // dismiss 済み
            } catch {
                guard self.phase == .refining else { return }
                self.refined = self.transcript
                self.statusMessage = "整形に失敗したため原文を表示(\(modelLabel)): \(error.localizedDescription)"
                self.phase = .result
            }
        }
    }

    func retryRefine() {
        guard phase == .result, settings.value.refineMode != .raw else { return }
        refine()
    }

    private func cancelRefine() {
        refineTask?.cancel()
        refineTask = nil
        if phase == .refining {
            refined = transcript
            statusMessage = "整形を中断しました"
            phase = .result
        }
    }

    // MARK: - 確定・キャンセル

    func accept() {
        guard phase == .result, !refined.isEmpty else { return }
        let s = settings.value
        history.add(raw: transcript, refined: refined, mode: s.refineMode, model: s.refineMode == .raw ? "-" : s.activeModelLabel)

        let result = Paster.deliver(refined, paste: s.autoPaste, keepInClipboard: s.keepInClipboard)
        playSound("Bottle")

        switch result {
        case .pasted, .copiedOnly:
            dismiss()
        case .needsAccessibility:
            statusMessage = result.message
            dismissAfter(2.2)
        }
    }

    func copyOnly() {
        guard phase == .result else { return }
        _ = Paster.deliver(refined, paste: false, keepInClipboard: true)
        statusMessage = "コピーしました"
        dismissAfter(1.2)
    }

    func cancelSession() {
        speech.cancel()
        refineTask?.cancel()
        refineTask = nil
        dismiss()
    }

    func dismiss() {
        dismissWork?.cancel()
        refineTask?.cancel()
        refineTask = nil
        phase = .idle
        statusMessage = nil
        hud.hide()
    }

    private func dismissAfter(_ delay: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func maybeInstantPaste() {
        if settings.value.instantPaste {
            accept()
        }
    }

    // MARK: - HUD キー操作

    func handleHUDKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // esc
            cancelSession()
            return true
        case 36, 76: // return / enter
            switch phase {
            case .recording:
                Task { await finishRecording() }
            case .result:
                accept()
            case .error:
                cancelSession()
            default:
                break
            }
            return true
        default:
            if event.modifierFlags.contains(.command),
               let ch = event.charactersIgnoringModifiers?.lowercased() {
                if ch == "c", phase == .result {
                    copyOnly()
                    return true
                }
                if ch == "r", phase == .result {
                    retryRefine()
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Helpers

    // カタログ掲載順(=推奨順)で最良のインストール済みモデルを返す
    private static func preferredModel(from installed: [LocalModel]) -> LocalModel? {
        for entry in BuiltinCatalog.all {
            if let match = installed.first(where: { $0.fileName == entry.fileName }) {
                return match
            }
        }
        return installed.max { $0.size < $1.size }
    }

    private func playSound(_ name: String) {
        guard settings.value.sounds else { return }
        guard let sound = NSSound(named: name) else { return }
        sound.volume = 0.35
        sound.play()
    }

    // qwen3 などの思考モデルが出力する <think> ブロックを隠す。
    // 閉じタグ前は空文字(HUD はプレースホルダー表示)、閉じたら本文のみ返す
    private static func visibleText(_ raw: String) -> String {
        let trimmed = raw.drop(while: { $0.isWhitespace })
        guard trimmed.hasPrefix("<think>") else { return raw }
        guard let range = trimmed.range(of: "</think>") else { return "" }
        return String(trimmed[range.upperBound...])
    }
}
