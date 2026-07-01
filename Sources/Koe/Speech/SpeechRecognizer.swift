import AVFoundation
import Speech

struct KoeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var partial: String = ""
    private(set) var isRunning = false

    var onAutoStop: (() -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var finishContinuation: CheckedContinuation<String, Never>?
    private var bestTranscript = ""
    private var lastVoiceAt = Date()
    private var autoStopTimer: Timer?

    // 長文ディクテーション対応:
    // SFSpeechRecognizer は無音やセグメント上限で認識を確定(isFinal)し、
    // その後の formattedString は新しいセグメントだけの内容にリセットされる。
    // そのままだと段落が変わるたびに前の文字起こしが消えるため、
    // 確定済みセグメントを committedText に累積し、認識タスクを継ぎ直す。
    private var activeConfig: Config?
    private var committedText = ""            // 確定済みセグメントの累積
    private var liveSegment = ""             // 認識中の最新セグメント(未確定)
    private var taskGeneration = 0            // 再開前の古いタスクの遅延コールバックを無視するための世代番号
    private var restartsWithoutProgress = 0   // エラー連発時の無限再開を防ぐ

    struct Config {
        var locale: Locale
        var preferOnDevice: Bool
        var punctuation: Bool
        var vocabulary: [String]
        var autoStopAfter: TimeInterval?
    }

    var supportsOnDevice: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    // スナップショット/プレビュー用
    func setPartialForPreview(_ text: String) {
        partial = text
    }

    func start(_ config: Config) throws {
        guard !isRunning else { return }

        guard let rec = SFSpeechRecognizer(locale: config.locale), rec.isAvailable else {
            throw KoeError("音声認識を利用できません。システム設定 > キーボード > 音声入力 で言語を追加してください。")
        }
        recognizer = rec

        activeConfig = config
        committedText = ""
        liveSegment = ""
        bestTranscript = ""
        partial = ""
        lastVoiceAt = Date()
        restartsWithoutProgress = 0
        request = makeRequest(config, recognizer: rec)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw KoeError("マイク入力を取得できません。入力デバイスを確認してください。")
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            let rms = Self.rms(buffer)
            Task { @MainActor [weak self] in self?.updateLevel(rms) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw KoeError("オーディオエンジンを開始できません: \(error.localizedDescription)")
        }

        isRunning = true
        startTask()
        startAutoStopTimer(config.autoStopAfter)
    }

    private func makeRequest(_ config: Config, recognizer rec: SFSpeechRecognizer) -> SFSpeechAudioBufferRecognitionRequest {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.addsPunctuation = config.punctuation
        if rec.supportsOnDeviceRecognition && config.preferOnDevice {
            req.requiresOnDeviceRecognition = true
        }
        if !config.vocabulary.isEmpty {
            req.contextualStrings = config.vocabulary
        }
        return req
    }

    private func startTask() {
        guard let rec = recognizer, let req = request else { return }
        taskGeneration += 1
        let gen = taskGeneration
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in self?.handle(result, error, generation: gen) }
        }
    }

    // 確定済みセグメントを保ったまま、新しい認識タスクで継続する
    private func restartRecognition() {
        guard isRunning, let config = activeConfig, let rec = recognizer else { return }
        task?.cancel()
        task = nil
        liveSegment = ""            // 新タスクの formattedString は最初から始まる
        request = makeRequest(config, recognizer: rec)
        startTask()
    }

    /// 録音を止め、最終確定した文字起こしを返す
    func stop() async -> String {
        guard isRunning else { return bestTranscript }
        isRunning = false
        stopAudio()
        request?.endAudio()

        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            // 最終結果が来ない場合のフォールバック
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }
                self.finish(with: self.bestTranscript)
            }
        }
    }

    func cancel() {
        isRunning = false
        taskGeneration += 1   // これ以降の遅延コールバックを無視
        liveSegment = ""
        stopAudio()
        task?.cancel()
        finish(with: bestTranscript)
        partial = ""
        level = 0
    }

    // MARK: - Private

    private func stopAudio() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
    }

    private func handle(_ result: SFSpeechRecognitionResult?, _ error: Error?, generation: Int) {
        // 再開前の古いタスクからの遅延コールバックは無視する
        guard generation == taskGeneration else { return }

        if let result {
            let segment = result.bestTranscription.formattedString

            // 同じタスク内でも formattedString が新しい発話にリセットされることがある
            // (特にオンデバイス認識)。前のセグメントの継続でなければ、確定として累積する。
            if Self.isNewSegment(previous: liveSegment, current: segment) {
                committedText = Self.join(committedText, liveSegment)
                liveSegment = ""
            }
            liveSegment = segment
            bestTranscript = Self.join(committedText, liveSegment)
            partial = bestTranscript
            if !segment.isEmpty { restartsWithoutProgress = 0 }

            if result.isFinal {
                // セグメント確定。累積して live をクリア。
                committedText = Self.join(committedText, liveSegment)
                liveSegment = ""
                bestTranscript = committedText
                partial = committedText
                if isRunning {
                    // 録音は継続中なので、新しいタスクで認識を続ける(前の内容は保持)
                    restartRecognition()
                } else {
                    // stop() 後の最終結果
                    finish(with: bestTranscript)
                }
            }
        }

        if error != nil {
            if isRunning {
                // 録音中のエラー(セグメント上限など)は再開して継続。
                // ただし全く進展しないエラーが続く場合は無限ループを避けて停止。
                restartsWithoutProgress += 1
                if restartsWithoutProgress > 5 {
                    isRunning = false
                    stopAudio()
                    finish(with: bestTranscript)
                } else {
                    committedText = Self.join(committedText, liveSegment)
                    liveSegment = ""
                    restartRecognition()
                }
            } else {
                // endAudio 後のエラーは「これ以上結果が来ない」印
                finish(with: bestTranscript)
            }
        }
    }

    // current が previous の継続(前方一致・小さな修正を含む)かどうかを判定し、
    // そうでなければ新しいセグメントの開始とみなす。
    private static func isNewSegment(previous: String, current: String) -> Bool {
        guard !previous.isEmpty else { return false }
        if current.hasPrefix(previous) { return false }        // 明確な継続(伸長)
        // 認識のわずかな揺れ(末尾の言い直し等)を許容するため、先頭の一致で継続判定
        let headLen = max(4, previous.count / 3)
        let head = String(previous.prefix(headLen))
        if current.hasPrefix(head) { return false }
        return true
    }

    // 確定済みテキストと現在のセグメントを結合する。
    // 空白区切りにしておき、細かな整形は LLM 側(整文/AI命令化)に任せる。
    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    private func finish(with text: String) {
        guard let continuation = finishContinuation else {
            task = nil
            request = nil
            return
        }
        finishContinuation = nil
        task = nil
        request = nil
        continuation.resume(returning: text)
    }

    private func updateLevel(_ rms: Float) {
        guard isRunning else { return }
        let db = 20 * log10(max(rms, 0.000_01))
        let norm = CGFloat(min(max((db + 55) / 55, 0), 1))
        level = level * 0.6 + norm * 0.4
        if norm > 0.3 {
            lastVoiceAt = Date()
        }
    }

    private func startAutoStopTimer(_ after: TimeInterval?) {
        guard let after, after > 0 else { return }
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                if !self.bestTranscript.isEmpty, Date().timeIntervalSince(self.lastVoiceAt) > after {
                    self.autoStopTimer?.invalidate()
                    self.autoStopTimer = nil
                    self.onAutoStop?()
                }
            }
        }
    }

    private nonisolated static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            sum += data[i] * data[i]
        }
        return sqrt(sum / Float(n))
    }
}
