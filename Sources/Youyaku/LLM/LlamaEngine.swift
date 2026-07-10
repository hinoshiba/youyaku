import Foundation
import llama

// llama.cpp(公式xcframework)による内蔵推論エンジン。
// モデルは読み込んだままキャッシュし、コンテキストは生成ごとに作り直す。
final class LlamaEngine: @unchecked Sendable {
    static let shared = LlamaEngine()

    // リクエストごとのキャンセルフラグ(共有フラグだと連続リクエスト間で競合する)
    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    private let queue = DispatchQueue(label: "youyaku.llama.engine", qos: .userInitiated)
    private var model: OpaquePointer?
    private var loadedPath: String?
    private var lastUsed = Date.distantPast

    // アプリ終了時に立てる全体フラグ。生成ループはトークンごとにこれも確認するため、
    // unloadSync() の queue.sync が生成完了まで(数十秒)ブロックすることがない
    private let terminating = CancelFlag()

    private init() {
        // ログを抑制(モデル読み込み失敗などは戻り値で検知する)
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()

        // 15 分使われなければモデルをメモリから解放する
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.queue.async { self?.unloadIfIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Public

    func chatStream(
        modelPath: String,
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int = 1536
    ) -> AsyncThrowingStream<String, Error> {
        let cancel = CancelFlag()
        return AsyncThrowingStream { continuation in
            self.queue.async {
                do {
                    try self.generate(
                        modelPath: modelPath,
                        system: system,
                        user: user,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        isCancelled: { cancel.isSet || self.terminating.isSet }
                    ) { piece in
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 正常終了時にも呼ばれるが、その時点で generate は完了済みなので無害
            continuation.onTermination = { _ in cancel.set() }
        }
    }

    func unload() {
        queue.async {
            if let model = self.model {
                llama_model_free(model)
                self.model = nil
                self.loadedPath = nil
            }
        }
    }

    // プロセス終了前に必ず呼ぶ。モデルを載せたまま exit すると
    // ggml-metal の残留リソースアサーションでクラッシュする
    func unloadSync() {
        // 生成中でも次のトークン境界でループを抜けさせる(終了のハング防止)
        terminating.set()
        queue.sync {
            if let model = self.model {
                llama_model_free(model)
                self.model = nil
                self.loadedPath = nil
            }
        }
    }

    // MARK: - Core(すべて queue 上で実行)

    private func unloadIfIdle() {
        guard let model, Date().timeIntervalSince(lastUsed) > 900 else { return }
        llama_model_free(model)
        self.model = nil
        self.loadedPath = nil
    }

    private func ensureModel(at path: String) throws -> OpaquePointer {
        if let model, loadedPath == path {
            return model
        }
        if let model {
            llama_model_free(model)
            self.model = nil
            self.loadedPath = nil
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw YouyakuError(tr("モデルファイルが見つかりません: \(path)", "Model file not found: \(path)"))
        }
        var params = llama_model_default_params()
        // 既定は全レイヤーを GPU(Metal)へ。GPU 非搭載環境(CI ランナー等)や
        // 切り分け用に YOUYAKU_GPU_LAYERS で上書きできる(0 = CPU のみ)。
        // アプリの通常動作では未設定なので従来どおり -1。
        if let ov = ProcessInfo.processInfo.environment["YOUYAKU_GPU_LAYERS"], let n = Int32(ov) {
            params.n_gpu_layers = n
        } else {
            params.n_gpu_layers = -1
        }
        guard let loaded = llama_model_load_from_file(path, params) else {
            throw YouyakuError(tr("モデルの読み込みに失敗しました。ファイルが壊れている可能性があります。", "Failed to load the model. The file may be corrupted."))
        }
        model = loaded
        loadedPath = path
        return loaded
    }

    private func generate(
        modelPath: String,
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        isCancelled: () -> Bool,
        emit: (String) -> Void
    ) throws {
        lastUsed = Date()
        let model = try ensureModel(at: modelPath)
        guard let vocab = llama_model_get_vocab(model) else {
            throw YouyakuError(tr("モデルの語彙を取得できません", "Could not read the model vocabulary"))
        }

        let prompt = buildPrompt(model: model, system: system, user: user)

        // トークナイズ
        let promptBytes = Array(prompt.utf8)
        var tokens = [llama_token](repeating: 0, count: promptBytes.count + 16)
        let nTokens = prompt.withCString { cstr in
            llama_tokenize(vocab, cstr, Int32(promptBytes.count), &tokens, Int32(tokens.count), true, true)
        }
        guard nTokens > 0 else {
            throw YouyakuError(tr("プロンプトのトークナイズに失敗しました", "Failed to tokenize the prompt"))
        }
        tokens.removeLast(tokens.count - Int(nTokens))

        let nCtx: UInt32 = 4096
        guard Int(nTokens) < Int(nCtx) - 256 else {
            throw YouyakuError(tr("前提や入力が長すぎます。前提プリセットを短くしてください。", "The context or input is too long. Try shortening your context preset."))
        }

        // コンテキスト(生成ごとに作成・破棄)
        var cparams = llama_context_default_params()
        cparams.n_ctx = nCtx
        cparams.n_batch = UInt32(max(1024, Int(nTokens) + 16))
        let cores = ProcessInfo.processInfo.activeProcessorCount
        cparams.n_threads = Int32(max(4, cores - 2))
        cparams.n_threads_batch = Int32(cores)
        guard let ctx = llama_init_from_model(model, cparams) else {
            throw YouyakuError(tr("推論コンテキストの作成に失敗しました(メモリ不足の可能性)", "Failed to create the inference context (possibly out of memory)"))
        }
        defer { llama_free(ctx) }

        // サンプラー
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        if temperature <= 0.01 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
        }

        // プロンプト評価
        let promptOK = tokens.withUnsafeMutableBufferPointer { buf -> Bool in
            let batch = llama_batch_get_one(buf.baseAddress, Int32(buf.count))
            return llama_decode(ctx, batch) == 0
        }
        guard promptOK else {
            throw YouyakuError(tr("プロンプトの評価に失敗しました", "Failed to evaluate the prompt"))
        }

        // 生成ループ(KV キャッシュの残り容量を超えないよう上限をクランプ)
        var pendingBytes: [UInt8] = []
        var pieceBuf = [CChar](repeating: 0, count: 512)
        var current = [llama_token](repeating: 0, count: 1)
        var generated = 0
        let tokenBudget = min(maxTokens, Int(nCtx) - Int(nTokens) - 1)

        while generated < tokenBudget {
            if isCancelled() { break }

            let token = llama_sampler_sample(chain, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            let len = llama_token_to_piece(vocab, token, &pieceBuf, Int32(pieceBuf.count), 0, true)
            if len > 0 {
                pendingBytes.append(contentsOf: pieceBuf[0..<Int(len)].map { UInt8(bitPattern: $0) })
                // マルチバイト文字がトークン境界で分割されるため、完全な UTF-8 部分だけ出す
                let valid = Self.validUTF8PrefixLength(pendingBytes)
                if valid > 0 {
                    emit(String(decoding: pendingBytes[0..<valid], as: UTF8.self))
                    pendingBytes.removeFirst(valid)
                }
            }

            let decodeOK = current.withUnsafeMutableBufferPointer { buf -> Bool in
                buf[0] = token
                let batch = llama_batch_get_one(buf.baseAddress, 1)
                return llama_decode(ctx, batch) == 0
            }
            guard decodeOK else {
                throw YouyakuError(tr("生成中にデコードエラーが発生しました", "A decoding error occurred during generation"))
            }
            generated += 1
        }

        if !pendingBytes.isEmpty {
            emit(String(decoding: pendingBytes, as: UTF8.self))
        }
        lastUsed = Date()
    }

    // モデル内蔵のチャットテンプレートを適用。失敗時は段階的にフォールバック
    private func buildPrompt(model: OpaquePointer, system: String, user: String) -> String {
        let tmpl = llama_model_chat_template(model, nil)

        if let tmpl {
            // 1) system + user
            if !system.isEmpty,
               let p = applyTemplate(tmpl, messages: [("system", system), ("user", user)]) {
                return p
            }
            // 2) テンプレートが system 非対応(Gemma 等)→ user に統合
            let merged = system.isEmpty ? user : "\(system)\n\n---\n\n\(user)"
            if let p = applyTemplate(tmpl, messages: [("user", merged)]) {
                return p
            }
        }
        // 3) ChatML 形式にフォールバック
        var out = ""
        if !system.isEmpty {
            out += "<|im_start|>system\n\(system)<|im_end|>\n"
        }
        out += "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        return out
    }

    private func applyTemplate(_ tmpl: UnsafePointer<CChar>, messages: [(String, String)]) -> String? {
        var cMessages: [llama_chat_message] = messages.map {
            llama_chat_message(role: strdup($0.0), content: strdup($0.1))
        }
        defer {
            for m in cMessages {
                free(UnsafeMutableRawPointer(mutating: m.role))
                free(UnsafeMutableRawPointer(mutating: m.content))
            }
        }

        let totalChars = messages.reduce(0) { $0 + $1.1.utf8.count }
        var buf = [CChar](repeating: 0, count: max(2048, totalChars * 2 + 1024))
        var n = llama_chat_apply_template(tmpl, &cMessages, cMessages.count, true, &buf, Int32(buf.count))
        if n > Int32(buf.count) {
            buf = [CChar](repeating: 0, count: Int(n) + 64)
            n = llama_chat_apply_template(tmpl, &cMessages, cMessages.count, true, &buf, Int32(buf.count))
        }
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<Int(n)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func validUTF8PrefixLength(_ bytes: [UInt8]) -> Int {
        var i = 0
        var lastValid = 0
        while i < bytes.count {
            let b = bytes[i]
            let len: Int
            if b & 0x80 == 0 { len = 1 }
            else if b & 0xE0 == 0xC0 { len = 2 }
            else if b & 0xF0 == 0xE0 { len = 3 }
            else if b & 0xF8 == 0xF0 { len = 4 }
            else { len = 1 } // 不正な先頭バイトは読み捨てて詰まりを防ぐ
            if i + len > bytes.count { break }
            i += len
            lastValid = i
        }
        return lastValid
    }
}
