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
        request = req

        bestTranscript = ""
        partial = ""
        lastVoiceAt = Date()

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

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in self?.handle(result, error) }
        }

        isRunning = true
        startAutoStopTimer(config.autoStopAfter)
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

    private func handle(_ result: SFSpeechRecognitionResult?, _ error: Error?) {
        if let result {
            bestTranscript = result.bestTranscription.formattedString
            partial = bestTranscript
            if result.isFinal {
                finish(with: bestTranscript)
            }
        }
        if error != nil, !isRunning {
            // endAudio 後のエラーは「これ以上結果が来ない」印
            finish(with: bestTranscript)
        }
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
