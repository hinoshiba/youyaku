import Foundation
import llama

// LlamaEngine.buildPrompt がどの分岐に落ちるかを実測する診断用。
// 使うのは LlamaEngine と同じ公開 C API なので、結果は本番と一致する。
enum Inspect {
    static func run(modelPath: String, system: String, user: String) {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        defer { llama_backend_free() }

        var mp = llama_model_default_params()
        mp.n_gpu_layers = 0
        mp.vocab_only = true
        guard let model = llama_model_load_from_file(modelPath, mp) else {
            print("!! load failed: \(modelPath)")
            return
        }
        defer { llama_model_free(model) }

        let file = (modelPath as NSString).lastPathComponent
        print("================ \(file)")

        guard let tmpl = llama_model_chat_template(model, nil) else {
            print("chat_template: <none>  -> LlamaEngine は ChatML フォールバック(分岐3)")
            return
        }

        let sysUser = apply(tmpl, [("system", system), ("user", user)])
        if let sysUser {
            print("分岐1 (system + user) 成功")
            print("--- 実際にモデルへ渡る文字列 ---")
            print(sysUser)
        } else {
            print("分岐1 (system + user) 失敗 -> 分岐2 へ")
            let merged = "\(system)\n\n---\n\n\(user)"
            if let m = apply(tmpl, [("user", merged)]) {
                print("分岐2 (system を user に統合) 成功")
                print("--- 実際にモデルへ渡る文字列 ---")
                print(m)
            } else {
                print("分岐2 も失敗 -> ChatML フォールバック(分岐3)")
            }
        }
    }

    private static func apply(_ tmpl: UnsafePointer<CChar>, _ messages: [(String, String)]) -> String? {
        var cMessages: [llama_chat_message] = messages.map {
            llama_chat_message(role: strdup($0.0), content: strdup($0.1))
        }
        defer {
            for m in cMessages {
                free(UnsafeMutableRawPointer(mutating: m.role))
                free(UnsafeMutableRawPointer(mutating: m.content))
            }
        }
        let total = messages.reduce(0) { $0 + $1.1.utf8.count }
        var buf = [CChar](repeating: 0, count: max(2048, total * 2 + 1024))
        var n = llama_chat_apply_template(tmpl, &cMessages, cMessages.count, true, &buf, Int32(buf.count))
        if n > Int32(buf.count) {
            buf = [CChar](repeating: 0, count: Int(n) + 64)
            n = llama_chat_apply_template(tmpl, &cMessages, cMessages.count, true, &buf, Int32(buf.count))
        }
        guard n > 0 else { return nil }
        return String(decoding: buf[0..<Int(n)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
