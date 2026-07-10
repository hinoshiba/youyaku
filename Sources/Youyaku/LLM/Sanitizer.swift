import Foundation

// LLM 出力から本文以外の付随物を取り除く。
// プロンプトで前置きを禁じても小型モデルは 1 割ほど混ぜてくるため、最後にここで落とす。
enum Sanitizer {
    /// ストリーミング中の表示用。<think> ブロックだけを隠す(閉じるまでは以降を出さない)
    static func visible(_ raw: String) -> String {
        guard let open = raw.range(of: "<think>") else { return raw }
        let head = String(raw[raw.startIndex..<open.lowerBound])
        guard let close = raw.range(of: "</think>", range: open.upperBound..<raw.endIndex) else {
            return head
        }
        return head + visible(String(raw[close.upperBound...]))
    }

    /// 生成完了後の仕上げ。取り切れなかった前置き・ラベル・囲みを落とす
    static func clean(_ raw: String) -> String {
        var s = visible(raw)
        s = s.replacingOccurrences(of: "<transcript>", with: "")
        s = s.replacingOccurrences(of: "</transcript>", with: "")
        s = afterLastOutputLabel(s)
        s = stripLeadingMeta(s)
        s = unwrapFence(s)
        s = unwrapQuotes(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 個別処理

    // few-shot 形式を再生産して「入力: …/出力: …」と書くモデルがいる。最後の「出力:」以降を採る
    private static func afterLastOutputLabel(_ s: String) -> String {
        let pattern = "(?m)^[ \t]*(?:\\*\\*)?(?:出力|Output)(?:\\*\\*)?[ \t]*[:：][ \t]*"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return s }
        return ns.substring(from: last.range.location + last.range.length)
    }

    // 先頭の相槌・ラベル・「〜を指示文に変換します」といったメタ文を、1 文ずつ剥がす
    private static func stripLeadingMeta(_ s: String) -> String {
        var out = s
        for _ in 0..<4 {
            let before = out
            for p in leadingMetaPatterns {
                out = replaceFirst(out, pattern: p, with: "")
            }
            out = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if out == before { break }
        }
        return out
    }

    private static let leadingMetaPatterns = [
        // 相槌のみの行
        "\\A[ \t]*(?:はい|承知しました|承知いたしました|了解しました|了解です|了解|わかりました|分かりました|かしこまりました)[、,。.!！:：]?[ \t]*(?:\\n|\\z)",
        "\\A[ \t]*(?:Sure|Certainly|Of course|Okay|OK|Got it)[,.!]?[ \t]*(?:\\n|\\z)",
        "\\A[ \t]*(?:Here(?:'s| is| are)|Below is)[^\\n]*\\n",
        // 「以下が変換後の指示文です:」のような行
        "\\A[ \t]*以下[^\\n。]{0,30}?(?:です|になります|とおりです|通りです)[：:。]?[ \t]*(?:\\n|\\z)",
        // 「出力:」「変換後の指示文:」などのラベル
        "\\A[ \t]*(?:\\*\\*)?(?:変換後の指示文|変換後の文章|変換後|書き換え後の指示文|書き換え指示文|書き換え後|整形後の本文|整形後|変換結果|整形結果|出力|結果|指示文|Output|Result)(?:\\*\\*)?[ \t]*[:：][ \t]*",
        // 「書き換えました。」「整形しました。」だけの行
        "\\A[ \t]*(?:書き換え|変換|整形)(?:し)?(?:ました|ます)[。.]?[ \t]*(?:\\n|\\z)",
        // 「〜を指示文に変換します。」「〜書き換えました。」などのメタ文
        "\\A[ \t]*[^\\n。]{0,80}?を(?:指示文|プロンプト)に(?:変換|書き換え)(?:します|しました|してください)[。.]?[ \t]*",
        "\\A[ \t]*[^\\n。]{0,80}?書き起こし[^\\n。]{0,40}?(?:変換|書き換え)(?:します|しました|ました)[。.]?[ \t]*",
        "\\A[ \t]*(?:書き換えた)?指示文だけを出力(?:します|してください)[。.]?[ \t]*",
    ]

    private static func unwrapFence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```"), t.hasSuffix("```"), t.count > 6 else { return s }
        guard let firstNL = t.firstIndex(of: "\n") else { return s }
        let body = t[t.index(after: firstNL)...].dropLast(3)
        return String(body)
    }

    private static func unwrapQuotes(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("「", "」"), ("\"", "\""), ("”", "”"), ("'", "'")]
        for (open, close) in pairs where t.count > 2 && t.first == open && t.last == close {
            let inner = t.dropFirst().dropLast()
            // 途中で閉じている場合(「A」と「B」)は囲みではないので触らない
            if !inner.contains(close) { return String(inner) }
        }
        return s
    }

    private static func replaceFirst(_ s: String, pattern: String, with repl: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return s }
        return ns.replacingCharacters(in: m.range, with: repl)
    }
}
