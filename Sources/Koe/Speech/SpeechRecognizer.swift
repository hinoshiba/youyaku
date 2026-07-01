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

    enum AutoStopReason {
        case silence              // ユーザー設定の「無音で自動停止」
        case recognitionFailure   // 認識エラーが続き継続できなかった(再開可能)
    }

    var onAutoStop: ((AutoStopReason) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var finishContinuation: CheckedContinuation<String, Never>?
    private var stopFallbackWork: DispatchWorkItem?
    private var bestTranscript = ""
    private var lastVoiceAt = Date()
    private var autoStopTimer: Timer?

    // マイクのタップコールバック(オーディオスレッド)と共有するリクエスト参照。
    // MainActor プロパティを直接読まず、ロック越しに受け渡す
    private let tapLock = NSLock()
    private nonisolated(unsafe) var tapRequest: SFSpeechAudioBufferRecognitionRequest?

    // 長文ディクテーション対応:
    // SFSpeechRecognizer は発話の区切りで文字起こしを確定し、以降の formattedString は
    // 新しい発話だけの内容になる。確定済みを committedText に累積して全文を保持する。
    //
    // 発話の区切りは次の 3 層で検出する(暫定文の内容比較はしない。認識途中の
    // 書き換え(かな→漢字等)を区切りと誤検知すると、同じ文が二重に累積するため):
    //   1. result.isFinal / speechRecognitionMetadata 付きの結果 = OS による発話確定
    //   2. 無音が続いたらこちらから確定して認識タスクを継ぎ直す(能動的な区切り)
    //   3. 保険: 暫定文が突然大幅に短くなったら、通知なしのリセットとみなして退避
    private var activeConfig: Config?
    private var committedText = ""            // 確定済み発話の累積
    private var liveSegment = ""              // 認識中の最新発話(未確定・毎回丸ごと置き換え)
    private var lastCommitted = ""            // 直前に確定した発話の全文(重複通知の除去用)
    private var lastCommittedAt = Date.distantPast  // 除去は確定直後の短時間のみ有効(繰り返し発話を食わないため)
    private var lastPartialChangeAt = Date()  // 暫定文が最後に変化した時刻(無音判定用)
    private var taskGeneration = 0            // 再開前の古いタスクの遅延コールバックを無視するための世代番号
    private var restartsWithoutProgress = 0   // エラー連発時の無限再開を防ぐ
    private var segmentTimer: Timer?          // 無音での能動的区切り + 監視(下記)
    private var taskStartedAt = Date()        // 現在の認識タスクの開始時刻
    private var isReconfiguring = false        // オーディオ再構築中(通知の連鎖を防ぐ)

    private static let segmentSilence: TimeInterval = 1.6
    // 声は入っているのに認識結果が止まっている(タスクの無音死)とみなすまでの時間
    private static let stallTimeout: TimeInterval = 6.0
    // macOS の音声認識はタスクあたり約 1 分の連続認識制限がある(Apple 公式ガイダンス)。
    // 上限に当たって切断される前に、発話の切れ目でタスクを予防的に継ぎ直す
    private static let taskRotateAfter: TimeInterval = 45
    private static let taskHardRotateAfter: TimeInterval = 55
    // 予防交代を語の途中で行わないための最小の無音幅(0.4 秒だと単語を割ることがある)
    private static let softRotateGap: TimeInterval = 0.8

    init() {
        // 入出力デバイスの変更(AirPods 接続等)でオーディオエンジンが停止すると
        // 録音が無言で死ぬため、通知を受けて音声チェーンを組み直して継続する
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleAudioConfigChange() }
        }
    }

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

    /// 録音を開始する。resumingFrom に既存の文字起こしを渡すと、
    /// その続きとして認識を再開する(中断からの再開機能)
    func start(_ config: Config, resumingFrom: String = "") throws {
        guard !isRunning else { return }

        guard let rec = SFSpeechRecognizer(locale: config.locale), rec.isAvailable else {
            throw KoeError(tr("音声認識を利用できません。システム設定 > キーボード > 音声入力 で言語を追加してください。", "Speech recognition is unavailable. Add the language in System Settings > Keyboard > Dictation."))
        }
        recognizer = rec

        activeConfig = config
        // 再開時は既存の文字起こしを確定済みテキストとして引き継ぐ
        committedText = resumingFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        liveSegment = ""
        lastCommitted = ""
        lastCommittedAt = .distantPast
        bestTranscript = committedText
        partial = committedText
        lastVoiceAt = Date()
        lastPartialChangeAt = Date()
        restartsWithoutProgress = 0
        let req = makeRequest(config, recognizer: rec)
        request = req
        setTapRequest(req)

        try startAudio()

        isRunning = true
        startTask()
        startAutoStopTimer(config.autoStopAfter)
        startSegmentTimer()
    }

    // マイク入力のタップを張り、オーディオエンジンを開始する
    private func startAudio() throws {
        #if os(iOS)
        // iOS では録音の前にオーディオセッションを構成する必要がある
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw KoeError(tr("マイク入力を取得できません。入力デバイスを確認してください。", "Could not capture microphone input. Check your input device."))
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.tapLock.lock()
            let req = self.tapRequest
            self.tapLock.unlock()
            req?.append(buffer)
            let rms = Self.rms(buffer)
            Task { @MainActor [weak self] in self?.updateLevel(rms) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw KoeError(tr("オーディオエンジンを開始できません: \(error.localizedDescription)", "Could not start the audio engine: \(error.localizedDescription)"))
        }
    }

    // 入出力デバイスの変更でエンジンが停止した場合、音声チェーンを組み直して録音を継続する
    private func handleAudioConfigChange() {
        // engine.start() 自体がこの通知を再発行し得るため、再構築中は無視して連鎖を防ぐ
        guard isRunning, !isReconfiguring, let config = activeConfig, let rec = recognizer else { return }
        isReconfiguring = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isReconfiguring = false
            }
        }

        commitLiveSegment()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        // 先に新リクエストへ切り替えてからエンジンを再開する
        // (新エンジンの音声が古いリクエストへ流れ込んで取りこぼすのを防ぐ)
        task?.cancel()
        task = nil
        let newRequest = makeRequest(config, recognizer: rec)
        request = newRequest
        setTapRequest(newRequest)
        liveSegment = ""
        lastCommitted = ""
        lastCommittedAt = .distantPast
        lastPartialChangeAt = Date()

        do {
            try startAudio()
            startTask()
        } catch {
            // 新しい入力デバイスが使えない場合はセッションを正常終了して内容を保全する
            onAutoStop?(.recognitionFailure)
        }
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
        taskStartedAt = Date()
        let gen = taskGeneration
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in self?.handle(result, error, generation: gen) }
        }
    }

    private nonisolated func setTapRequest(_ req: SFSpeechAudioBufferRecognitionRequest?) {
        tapLock.lock()
        tapRequest = req
        tapLock.unlock()
    }

    // 確定済みテキストを保ったまま、新しい認識タスクで継続する
    private func restartRecognition() {
        guard isRunning, let config = activeConfig, let rec = recognizer else { return }
        // 先に新リクエストへ切り替えてから旧タスクを止める(バッファの取りこぼし防止)
        let newRequest = makeRequest(config, recognizer: rec)
        request = newRequest
        setTapRequest(newRequest)
        task?.cancel()
        task = nil
        liveSegment = ""            // 新タスクの formattedString は最初から始まる
        lastCommitted = ""          // 新タスクの結果に古い確定文は含まれない
        lastCommittedAt = .distantPast
        lastPartialChangeAt = Date()
        startTask()
    }

    // 定期監視: ①無音での能動的区切り ②認識タスクの無音死からの自動復旧
    // ③OS の連続認識制限(約1分)に達する前の予防的な継ぎ直し
    private func startSegmentTimer() {
        segmentTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                let now = Date()

                // ① 無音での区切り(「マイクレベル」と「暫定文の変化」の両方が止まっている時)
                if !self.liveSegment.isEmpty {
                    let quietFor = now.timeIntervalSince(max(self.lastVoiceAt, self.lastPartialChangeAt))
                    if quietFor > Self.segmentSilence {
                        self.commitLiveSegment()
                        self.restartRecognition()
                        return
                    }
                }

                // ② 声は入り続けているのに認識結果が止まっている = タスクが無言で死んでいる。
                //    ここまでの内容を保持したまま自動で継ぎ直す(ユーザーには中断が見えない)
                let voiceActive = now.timeIntervalSince(self.lastVoiceAt) < 1.0
                if voiceActive, now.timeIntervalSince(self.lastPartialChangeAt) > Self.stallTimeout {
                    self.commitLiveSegment()
                    self.restartRecognition()
                    return
                }

                // ③ 連続認識の上限(約1分)に当たる前に予防交代。
                //    回すべき対象(暫定文または直近の発話)がある時だけ行う。
                //    長い無音中に空タスクを無駄に作り直さない(無用な churn とカウンタ誤累積を防ぐ)
                let taskAge = now.timeIntervalSince(self.taskStartedAt)
                let quiet = now.timeIntervalSince(self.lastVoiceAt)
                let hasContent = !self.liveSegment.isEmpty || quiet < 1.0
                if hasContent,
                   taskAge > Self.taskHardRotateAfter ||
                   (taskAge > Self.taskRotateAfter && quiet > Self.softRotateGap) {
                    // 上限まで生きた=パイプラインは正常。エラーカウンタをクリアして
                    // 無音中のタスクエラー累積による誤停止を防ぐ
                    self.restartsWithoutProgress = 0
                    self.commitLiveSegment()
                    self.restartRecognition()
                }
            }
        }
    }

    private func commitLiveSegment() {
        let text = liveSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        liveSegment = ""
        guard !text.isEmpty else { return }
        committedText = Self.join(committedText, text)
        bestTranscript = committedText
        partial = committedText
    }

    /// 録音を止め、最終確定した文字起こしを返す
    func stop() async -> String {
        guard isRunning else { return bestTranscript }
        isRunning = false
        stopAudio()
        request?.endAudio()

        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            // 最終結果が来ない場合のフォールバック。
            // finish() で必ずキャンセルする(遅れて発火すると次のセッションの
            // request/task を破壊して録音が無音になるため)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.finish(with: self.bestTranscript)
            }
            stopFallbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }

    func cancel() {
        isRunning = false
        taskGeneration += 1   // これ以降の遅延コールバックを無視
        liveSegment = ""
        stopAudio()
        task?.cancel()
        finish(with: bestTranscript)   // stop() 待ちがあれば解決する
        task = nil
        request = nil
        partial = ""
        level = 0
    }

    // MARK: - Private

    private func stopAudio() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        segmentTimer?.invalidate()
        segmentTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        setTapRequest(nil)
        engine.stop()
        level = 0
        #if os(iOS)
        // 他アプリの音声を元に戻すため、録音セッションを解除する
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func handle(_ result: SFSpeechRecognitionResult?, _ error: Error?, generation: Int) {
        // 再開前の古いタスクからの遅延コールバックは無視する
        guard generation == taskGeneration else { return }

        if let result {
            var segment = result.bestTranscription.formattedString

            // 直前に確定した発話がそのまま先頭に含まれて再通知される実装系への保険(重複除去)。
            // 確定直後の短時間に限定する(時間制限なしだと、ユーザーが同じ言葉を
            // 繰り返した発話まで削ってしまう)。累積型ストリームが続く間は窓を延長する。
            if !lastCommitted.isEmpty,
               Date().timeIntervalSince(lastCommittedAt) < 1.0,
               segment.hasPrefix(lastCommitted) {
                segment = String(segment.dropFirst(lastCommitted.count))
                lastCommittedAt = Date()
            }

            // OS による発話確定(タスク終端の isFinal、または発話単位の metadata 付き結果)
            let finalized = result.isFinal || result.speechRecognitionMetadata != nil

            if finalized {
                // この結果自体が確定文。同内容の二重確定は上の重複除去で空になる
                let text = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    committedText = Self.join(committedText, text)
                    lastCommitted = result.bestTranscription.formattedString
                    lastCommittedAt = Date()
                    restartsWithoutProgress = 0
                }
                liveSegment = ""
                bestTranscript = committedText
                partial = committedText
            } else {
                // 暫定文は毎回丸ごと置き換える。内容比較で区切りを推測しない
                // (認識途中の書き換えを区切りと誤検知すると同じ文が二重に累積するため)。
                // 区切りの検出は OS の確定通知と無音タイマーに任せる
                if segment != liveSegment {
                    lastPartialChangeAt = Date()
                }
                liveSegment = segment
                bestTranscript = Self.join(committedText, liveSegment)
                partial = bestTranscript
                if !segment.isEmpty { restartsWithoutProgress = 0 }
            }

            if result.isFinal {
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
                commitLiveSegment()
                // 声が入っているのに失敗する時だけ「進展なし」として数える。
                // 無音中のタスクエラー(no speech detected 等)は正常なので数えず、
                // カウンタを戻す(長い沈黙で録音が勝手に止まるのを防ぐ)
                if Date().timeIntervalSince(lastVoiceAt) < 3.0 {
                    restartsWithoutProgress += 1
                } else {
                    restartsWithoutProgress = 0
                }
                if restartsWithoutProgress > 5 {
                    // 諦めて停止するが、セッションは正常終了ルートに乗せて
                    // ここまでの文字起こしを失わない(UI が録音中のまま固まらないように)
                    onAutoStop?(.recognitionFailure)
                } else {
                    restartRecognition()
                }
            } else {
                // endAudio 後のエラーは「これ以上結果が来ない」印
                finish(with: bestTranscript)
            }
        }
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
        stopFallbackWork?.cancel()
        stopFallbackWork = nil
        guard let continuation = finishContinuation else {
            // 継続待ちがない finish は何もしない(遅延実行された場合に
            // 次のセッションの request/task を破壊しないこと)
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
                    self.onAutoStop?(.silence)
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
