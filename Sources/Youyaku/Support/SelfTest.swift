import AppKit
import Foundation

// 動作検証用: `Youyaku --selftest <ggufパス> [プロンプト]` で内蔵エンジンの推論を実行して終了する
@MainActor
enum SelfTest {
    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--selftest"),
              CommandLine.arguments.count > index + 1 else { return false }
        let modelPath = CommandLine.arguments[index + 1]
        let prompt = CommandLine.arguments.count > index + 2
            ? CommandLine.arguments[index + 2]
            : "えーっと、明日の会議の資料なんだけど、あの、グラフのところ最新の数字に直しといてほしいんだよね"

        Task { @MainActor in
            let (system, user) = Refiner.prompts(
                mode: .command,
                premise: nil,
                transcript: prompt,
                modelHint: (modelPath as NSString).lastPathComponent
            )
            let out = FileHandle.standardOutput
            out.write(Data("[selftest] model: \(modelPath)\n[selftest] input: \(prompt)\n---\n".utf8))
            do {
                let start = Date()
                let stream = LlamaEngine.shared.chatStream(
                    modelPath: modelPath,
                    system: system,
                    user: user,
                    temperature: 0.2,
                    maxTokens: 512
                )
                var count = 0
                for try await piece in stream {
                    out.write(Data(piece.utf8))
                    count += 1
                }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
                out.write(Data("\n---\n[selftest OK] \(count) pieces, \(elapsed)s\n".utf8))
                LlamaEngine.shared.unloadSync()
                exit(0)
            } catch {
                out.write(Data("\n[selftest FAILED] \(error.localizedDescription)\n".utf8))
                LlamaEngine.shared.unloadSync()
                exit(1)
            }
        }
        return true
    }
}
