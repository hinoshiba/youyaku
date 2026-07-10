import Foundation

// アプリにバンドルした第三者ライセンス表記を読み込む。
// mac は Contents/Resources/、iOS はメインバンドル直下に配置される。
enum Licenses {
    static var thirdPartyText: String {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        // フォールバック(バンドル取得に失敗した場合でも必須の帰属は表示する)
        return """
        Youyaku — Third-Party Notices

        This app includes llama.cpp / ggml (MIT License,
        Copyright (c) 2023-2026 The ggml authors).

        The macOS app includes Sparkle (MIT License,
        Copyright (c) 2006-2013 Andy Matuschak and contributors).

        Language models are downloaded by the user from Hugging Face and are
        governed by their own licenses: Qwen3 (Apache-2.0), ELYZA JP 8B
        (Built with Meta Llama 3), Llama 3.2 (Built with Llama),
        Gemma (Gemma Terms of Use).
        """
    }
}
