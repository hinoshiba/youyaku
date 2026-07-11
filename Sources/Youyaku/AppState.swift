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
        case empty            // 認識は動いたが結果がゼロ文字(マイク不調ではない)
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
    // 直販版のアプリ内アップデート(Sparkle。youyaku.hinoshiba.com の appcast.xml を
    // 1日1回取得し、更新はアプリ内で完結する。設定でオフ可能)
    lazy var updater = Updater(automaticallyChecks: settings.value.checkForUpdates)

    private var refineTask: Task<Void, Never>?
    private var dismissWork: DispatchWorkItem?
    private var isStopping = false
    private var isStartingRecording = false
    private var sessionHistoryID: UUID?   // このセッションの履歴エントリ(音声入力を先に保存)
    private var sessionLocaleID = "ja-JP" // 録音時の認識言語(整形プロンプトの言語をこれに合わせる)
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
            updater.objectWillChange.eraseToAnyPublisher(),
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
        speech.onAutoStop = { [weak self] reason in
            Task { await self?.finishRecording(autoStopReason: reason) }
        }
        // 認識が構成上そもそも使えない(ディクテーションがオフ等)場合は、
        // 無言のまま止めず、原因と対処を明確なエラーとして表示する
        speech.onUnavailable = { [weak self] message in
            guard let self, self.phase == .recording else { return }
            self.refineTask?.cancel()
            self.refineTask = nil
            self.dismissWork?.cancel()
            self.transcript = ""
            self.refined = ""
            self.statusMessage = nil
            self.phase = .error(message)
            self.hud.show()
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
    }

    /// ショートカットを変更する。登録に成功したら true。
    /// 競合などで失敗した場合は設定を元に戻し、既存のショートカットを維持する。
    @discardableResult
    func updateHotkey(_ combo: KeyCombo) -> Bool {
        let ok = HotkeyManager.shared.register(combo)
        if ok {
            settings.value.hotkey = combo
        }
        // 失敗時も旧ショートカットは登録されたまま生きているため、
        // hotkeyActive は「いま有効なショートカットがあるか」を反映させる
        // (ホーム画面の警告バナーの誤表示を防ぐ。失敗の通知は設定画面側で行う)
        hotkeyActive = ok || HotkeyManager.shared.current != nil
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
        case .result, .empty, .error:
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
        sessionHistoryID = nil
        beginRecording(resumingFrom: "")
    }

    /// 確定画面から、ここまでの文字起こしを保持したまま録音を再開する(⌘↩)。
    /// 意図せず中断された長い口述を失わずに続けるための機能
    func resumeRecording() {
        guard phase == .result, !transcript.isEmpty else { return }
        dismissWork?.cancel()
        refineTask?.cancel()
        refineTask = nil
        statusMessage = nil
        refined = ""
        // sessionHistoryID は維持し、finishRecording で同じ履歴エントリを更新する
        beginRecording(resumingFrom: transcript)
    }

    private func beginRecording(resumingFrom base: String) {
        // 権限確認の await 中は phase が変わらないため、フラグで二重進入を防ぐ
        guard !isStartingRecording else { return }
        isStartingRecording = true
        Task {
            defer { isStartingRecording = false }
            let permission = await Permissions.ensureSpeechAndMic()
            guard permission.ok else {
                phase = .error(permission.message)
                hud.show()
                return
            }
            do {
                let s = settings.value
                sessionLocaleID = s.localeID   // この録音で使う言語を固定(整形もこの言語で行う)
                try speech.start(SpeechRecognizer.Config(
                    locale: Locale(identifier: s.localeID),
                    preferOnDevice: s.preferOnDevice,
                    punctuation: s.punctuation,
                    vocabulary: s.vocabularyList,
                    autoStopAfter: s.autoStop ? s.autoStopSeconds : nil,
                    inputDeviceUID: s.inputDeviceUID
                ), resumingFrom: base)
                phase = .recording
                hud.show()
                playSound("Pop")
            } catch {
                phase = .error(error.localizedDescription)
                hud.show()
            }
        }
    }

    // 認識が意図せず中断された時に、確定画面へ出す再開案内
    private var resumeHintText: String {
        tr("認識が中断されたため、ここまでの内容を確定しました。⌘↩ で続きから再開できます",
           "Recognition was interrupted; your dictation so far has been kept. Press ⌘↩ to resume.")
    }

    func finishRecording(autoStopReason: SpeechRecognizer.AutoStopReason? = nil) async {
        // await 中に phase が .recording のままになるため、再入をフラグで防ぐ
        guard phase == .recording, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        playSound("Tink")
        let text = await speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        // await 中に esc 等でセッションが破棄された場合は何もしない
        // (履歴は cancelSession 側で保存済み。二重保存やセッション復活を防ぐ)
        guard phase == .recording else { return }
        transcript = text

        guard !text.isEmpty else {
            // マイクは正常でも、無言・環境音・ごく短い発話だと結果が空になる。
            // 「設定を見て」ではなく、穏やかに再入力を促す専用状態にする
            phase = .empty
            return
        }

        // 変換の成否やキャンセルに関わらず、音声入力そのものを先に履歴へ残す。
        // 再開セッションの場合は同じエントリを更新する(重複エントリを作らない)
        if let id = sessionHistoryID {
            history.updateRaw(id: id, raw: text)
        } else {
            sessionHistoryID = history.add(raw: text, refined: "", mode: settings.value.refineMode, model: "-")
        }

        // 認識が中断された場合は、ユーザーが話し終えたわけではないので
        // 自動貼り付けはせず、確定画面に留めて再開手段を案内する
        let interrupted = autoStopReason == .recognitionFailure

        if settings.value.refineMode == .raw {
            // 変換なしモード: 履歴は音声入力のみのエントリのまま
            refined = text
            phase = .result
            if interrupted {
                statusMessage = resumeHintText
            } else {
                maybeInstantPaste()
            }
        } else {
            refine(interrupted: interrupted)
        }
    }

    // このセッションの履歴エントリに変換結果を反映する(変換が実際に成功した時のみ呼ぶ)
    private func recordRefinedToHistory() {
        guard let id = sessionHistoryID else { return }
        let s = settings.value
        history.updateRefined(
            id: id,
            refined: refined,
            mode: s.refineMode,
            model: s.activeModelLabel
        )
    }

    func refine(interrupted: Bool = false) {
        let s = settings.value

        let stream: AsyncThrowingStream<String, Error>
        let modelLabel = s.activeModelLabel

        switch s.engine {
        case .builtin:
            guard let file = s.builtinModelFile,
                  let local = modelStore.installed.first(where: { $0.fileName == file }) else {
                refined = transcript
                statusMessage = tr("LLM モデルが未設定のため、認識結果をそのまま表示しています(「モデル」画面からダウンロードできます)", "No LLM model is set, so the raw transcription is shown. (You can download one from the Models screen.)")
                phase = .result
                return
            }
            let (system, user) = Refiner.prompts(
                mode: s.refineMode, premise: s.activePremise,
                transcript: transcript, modelHint: file, localeID: sessionLocaleID
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
                statusMessage = tr("Ollama が起動していないため、認識結果をそのまま表示しています", "Ollama is not running, so the raw transcription is shown.")
                phase = .result
                return
            }
            let (system, user) = Refiner.prompts(
                mode: s.refineMode, premise: s.activePremise,
                transcript: transcript, modelHint: s.model, localeID: sessionLocaleID
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
                    self.refined = Sanitizer.visible(raw)
                }
                // キャンセル済み・セッション終了済みなら結果を適用しない(誤貼り付け防止)
                try Task.checkCancellation()
                guard self.phase == .refining else { return }
                // 前置きやラベルの除去は完了後に一度だけ(途中で消すと表示がちらつく)
                self.refined = Sanitizer.clean(raw)
                if self.refined.isEmpty {
                    self.refined = self.transcript
                    self.statusMessage = tr("整形結果が空だったため、認識結果をそのまま表示しています", "The refined result was empty, so the raw transcription is shown.")
                } else {
                    self.recordRefinedToHistory()
                }
                self.phase = .result
                if interrupted {
                    // 中断由来: 自動貼り付けせず再開案内を残す
                    // (整形側で既に別の案内が出ている場合はそちらを優先)
                    if self.statusMessage == nil {
                        self.statusMessage = self.resumeHintText
                    }
                } else {
                    self.maybeInstantPaste()
                }
            } catch is CancellationError {
                // dismiss 済み(音声入力は履歴に保存済み)
            } catch {
                guard self.phase == .refining else { return }
                self.refined = self.transcript
                self.statusMessage = tr("整形に失敗したため原文を表示(\(modelLabel)): \(error.localizedDescription)", "Refinement failed; showing the original text (\(modelLabel)): \(error.localizedDescription)")
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
            statusMessage = tr("整形を中断しました", "Refinement canceled")
            phase = .result
        }
    }

    // MARK: - 確定・キャンセル

    func accept() {
        guard phase == .result, !refined.isEmpty else { return }
        let s = settings.value
        // 履歴は finishRecording(音声入力)と refine 成功時(変換結果)で保存済み

        let result = Paster.deliver(refined, paste: s.autoPaste, keepInClipboard: s.keepInClipboard)

        switch result {
        case .pasted:
            playSound("Bottle")
            dismiss()
        case .copiedOnly where s.autoPaste:
            // 自動貼り付けを試みたがコピーのみになった(セキュア入力中・自アプリが最前面)。
            // 成功と誤認させないよう音を変え、案内を読める長さだけ表示してから閉じる
            playSound("Pop")
            statusMessage = result.message
            dismissAfter(1.5)
        case .copiedOnly:
            // 自動貼り付けオフの設定では、コピーのみが期待どおりの動作
            playSound("Bottle")
            dismiss()
        case .needsAccessibility:
            // 失敗が分かる音を鳴らし、案内を読める長さだけ表示してから閉じる
            playSound("Basso")
            statusMessage = result.message
            dismissAfter(4.0)
        }
    }

    func copyOnly() {
        guard phase == .result else { return }
        _ = Paster.deliver(refined, paste: false, keepInClipboard: true)
        statusMessage = tr("コピーしました", "Copied")
        dismissAfter(1.2)
    }

    func cancelSession() {
        // 録音中のキャンセルでも、聞き取れていた音声入力は履歴に残す
        // (長時間の入力を誤操作で失わないための保全)。
        // 再開セッションなら既存エントリを更新し、重複を作らない
        if phase == .recording {
            let text = speech.partial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if let id = sessionHistoryID {
                    history.updateRaw(id: id, raw: text)
                } else {
                    history.add(raw: text, refined: "", mode: settings.value.refineMode, model: "-")
                }
            }
        }
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
                if event.modifierFlags.contains(.command) {
                    resumeRecording()   // ⌘↩ = 続きから再開
                } else {
                    accept()
                }
            case .empty:
                dismiss()
                startRecording()        // ↩ = もう一度話す
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

}
