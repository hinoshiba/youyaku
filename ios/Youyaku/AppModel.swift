import Combine
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

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

    let settings = SettingsStore()
    var config: AppSettings {
        get { settings.value }
        set { settings.value = newValue }
    }

    let history = HistoryStore()
    let speech = SpeechRecognizer()
    let modelStore = ModelStore()
    let llamaEngine = LlamaEngine.shared

    private var refineTask: Task<Void, Never>?
    private var isStopping = false
    private var sessionHistoryID: UUID?
    private var sessionLocaleID = "ja-JP"   // 録音時の認識言語(整形もこの言語で行う)
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        L10n.current = settings.value.uiLanguage
        bridgeChildChanges()
        speech.onAutoStop = { [weak self] reason in
            Task { await self?.finishRecording(autoStopReason: reason) }
        }
        // 音声入力(ディクテーション)がオフ等で認識がそもそも使えない場合は、
        // 無言のまま止めず、原因と対処を明確なエラーとして表示する
        speech.onUnavailable = { [weak self] message in
            guard let self, self.phase == .recording else { return }
            self.refineTask?.cancel()
            self.refineTask = nil
            self.transcript = ""
            self.refined = ""
            self.statusMessage = nil
            self.phase = .error(message)
        }
        modelStore.onInstalled = { [weak self] fileName in
            guard let self else { return }
            self.settings.value.builtinModelFile = fileName
            self.llamaEngine.unload()
        }
        if settings.value.builtinModelFile == nil,
           let best = Self.preferredModel(from: modelStore.installed) {
            settings.value.builtinModelFile = best.fileName
        }
        // iOS では内蔵エンジン固定(Ollama はローカルサーバー前提のため対象外)
        settings.value.engine = .builtin
    }

    private func bridgeChildChanges() {
        for publisher in [
            settings.objectWillChange.eraseToAnyPublisher(),
            history.objectWillChange.eraseToAnyPublisher(),
            speech.objectWillChange.eraseToAnyPublisher(),
            modelStore.objectWillChange.eraseToAnyPublisher(),
        ] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    var hasModel: Bool {
        settings.value.builtinModelFile.map { file in
            modelStore.installed.contains { $0.fileName == file }
        } ?? false
    }

    // MARK: - セッション制御

    func toggle() {
        switch phase {
        case .idle, .result, .empty, .error:
            startRecording()
        case .recording:
            Task { await finishRecording() }
        case .refining:
            cancelRefine()
        }
    }

    func startRecording() {
        guard phase != .recording, phase != .refining else { return }
        statusMessage = nil
        transcript = ""
        refined = ""
        sessionHistoryID = nil
        beginRecording(resumingFrom: "")
    }

    /// ここまでの文字起こしを保持したまま録音を再開する
    func resumeRecording() {
        guard phase == .result, !transcript.isEmpty else { return }
        refineTask?.cancel()
        refineTask = nil
        statusMessage = nil
        refined = ""
        beginRecording(resumingFrom: transcript)
    }

    private func beginRecording(resumingFrom base: String) {
        Task {
            let permission = await Permissions.ensureSpeechAndMic()
            guard permission.ok else {
                phase = .error(permission.message)
                return
            }
            do {
                let s = settings.value
                sessionLocaleID = s.localeID   // この録音で使う言語を固定
                try speech.start(SpeechRecognizer.Config(
                    locale: Locale(identifier: s.localeID),
                    preferOnDevice: s.preferOnDevice,
                    punctuation: s.punctuation,
                    vocabulary: s.vocabularyList,
                    autoStopAfter: s.autoStop ? s.autoStopSeconds : nil
                ), resumingFrom: base)
                phase = .recording
                Haptics.tap()
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private var resumeHintText: String {
        tr("認識が中断されたため、ここまでの内容を確定しました。「続きから再開」で続けられます",
           "Recognition was interrupted; your dictation so far has been kept. Tap Resume to continue.")
    }

    func finishRecording(autoStopReason: SpeechRecognizer.AutoStopReason? = nil, skipRefine: Bool = false) async {
        guard phase == .recording, !isStopping else { return }
        isStopping = true
        defer { isStopping = false }
        Haptics.tap()
        let text = await speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .recording else { return }
        transcript = text

        guard !text.isEmpty else {
            // マイクは正常でも、無言・環境音・ごく短い発話だと結果が空になる。
            // 「設定を見て」ではなく、穏やかに再入力を促す専用状態にする
            phase = .empty
            return
        }

        if let id = sessionHistoryID {
            history.updateRaw(id: id, raw: text)
        } else {
            sessionHistoryID = history.add(raw: text, refined: "", mode: settings.value.refineMode, model: "-")
        }

        let interrupted = autoStopReason == .recognitionFailure

        if settings.value.refineMode == .raw || skipRefine {
            refined = text
            phase = .result
            if skipRefine {
                statusMessage = backgroundCancelText
            } else if interrupted {
                statusMessage = resumeHintText
            }
        } else {
            refine(interrupted: interrupted)
        }
    }

    private func recordRefinedToHistory() {
        guard let id = sessionHistoryID else { return }
        let s = settings.value
        history.updateRefined(id: id, refined: refined, mode: s.refineMode, model: s.activeModelLabel)
    }

    func refine(interrupted: Bool = false) {
        let s = settings.value
        guard let file = s.builtinModelFile,
              let local = modelStore.installed.first(where: { $0.fileName == file }) else {
            refined = transcript
            statusMessage = tr("LLM モデルが未設定のため、認識結果をそのまま表示しています(「モデル」タブからダウンロードできます)",
                               "No LLM model is set, so the raw transcription is shown. (Download one from the Models tab.)")
            phase = .result
            return
        }

        let (system, user) = Refiner.prompts(
            mode: s.refineMode, premise: s.activePremise,
            transcript: transcript, modelHint: file, localeID: sessionLocaleID
        )
        let stream = llamaEngine.chatStream(
            modelPath: local.fileURL.path, system: system, user: user, temperature: s.temperature
        )

        phase = .refining
        refined = ""

        refineTask = Task { [weak self] in
            guard let self else { return }
            do {
                var raw = ""
                for try await token in stream {
                    try Task.checkCancellation()
                    raw += token
                    self.refined = Sanitizer.visible(raw)
                }
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
                if interrupted, self.statusMessage == nil {
                    self.statusMessage = self.resumeHintText
                }
                Haptics.success()
            } catch is CancellationError {
                // dismiss 済み
            } catch {
                guard self.phase == .refining else { return }
                self.refined = self.transcript
                self.statusMessage = tr("整形に失敗したため原文を表示: \(error.localizedDescription)", "Refinement failed; showing the original text: \(error.localizedDescription)")
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

    // MARK: - ライフサイクル(バックグラウンド遷移)

    /// バックグラウンド遷移時の保全処理。録音中はここまでの文字起こしを確定し、
    /// 整形中は中断して原文を残す(Metal 推論はバックグラウンドで実行できないため)
    func enteredBackground() {
        switch phase {
        case .recording:
            // サスペンド前に確定(最大2.5秒)と履歴書き込みを終えられるよう背景実行時間を確保し、
            // バックグラウンドでは Metal 推論を開始できないため整形はスキップして確定だけ行う
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "youyaku.finishRecording")
            Task {
                await finishRecording(skipRefine: true)
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        case .refining:
            cancelRefine()
            statusMessage = backgroundCancelText
        default:
            break
        }
    }

    /// メモリ警告時の退避。整形中ならトークン境界で中断してから、ロード済みモデルを解放する
    /// (unload は生成と同じ直列キューのため、先に中断しないとピーク時に何も解放されない)
    func handleMemoryWarning() {
        if phase == .refining {
            cancelRefine()
            statusMessage = tr("メモリ不足のため整形を中断しました。原文は保持されています(「やり直す」で再整形できます)",
                               "Refinement was interrupted to free memory. The original text is kept (tap Retry to refine again).")
        }
        LlamaEngine.shared.unload()
    }

    private var backgroundCancelText: String {
        tr("バックグラウンドに移ったため整形を中断しました。原文は保持されています(「やり直す」で再整形できます)",
           "Refinement was canceled because the app went to the background. Your original text is kept — tap Retry to refine again.")
    }

    // MARK: - 確定(iOS はコピー)

    func copyResult() {
        guard phase == .result, !refined.isEmpty else { return }
        recordRefinedToHistory()
        Clipboard.copy(refined)
        Haptics.success()
        statusMessage = tr("コピーしました", "Copied")
    }

    func cancelSession() {
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
        phase = .idle
        statusMessage = nil
        transcript = ""
        refined = ""
    }

    // MARK: - Helpers

    private static func preferredModel(from installed: [LocalModel]) -> LocalModel? {
        for entry in BuiltinCatalog.all {
            if let match = installed.first(where: { $0.fileName == entry.fileName }) {
                return match
            }
        }
        return installed.min { $0.size < $1.size }   // iOS は省メモリ優先で最小を既定に
    }
}
