import Foundation

struct BuiltinModel: Identifiable {
    let fileName: String       // ローカル保存名(リモートと同名)
    let displayName: String
    let vendor: String
    let quant: String
    let sizeBytes: Int64
    let url: URL
    let description: String
    let japaneseStars: Int
    let tag: String?           // 「おすすめ」「日本語特化」など

    var id: String { fileName }
    var sizeLabel: String { Format.bytes(sizeBytes) }
    var isRecommended: Bool { tag == tr("おすすめ", "Recommended") }
}

// 認証不要で直接ダウンロードできることを検証済みの GGUF カタログ(2026-07 時点)
enum BuiltinCatalog {
    static var all: [BuiltinModel] { [
        BuiltinModel(
            fileName: "Qwen3-4B-Q4_K_M.gguf",
            displayName: "Qwen3 4B",
            vendor: tr("Alibaba(公式)", "Alibaba (Official)"),
            quant: "Q4_K_M",
            sizeBytes: 2_497_280_256,
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!,
            description: tr("日本語性能と速度のバランスが最良。迷ったらこれ。", "Best balance of Japanese quality and speed. A safe default."),
            japaneseStars: 5,
            tag: tr("おすすめ", "Recommended")
        ),
        BuiltinModel(
            fileName: "Llama-3-ELYZA-JP-8B-q4_k_m.gguf",
            displayName: "ELYZA JP 8B",
            vendor: tr("ELYZA(公式)", "ELYZA (Official)"),
            quant: "Q4_K_M",
            sizeBytes: 4_920_733_984,
            url: URL(string: "https://huggingface.co/elyza/Llama-3-ELYZA-JP-8B-GGUF/resolve/main/Llama-3-ELYZA-JP-8B-q4_k_m.gguf")!,
            description: tr("日本語特化チューニング。自然で丁寧な整形。メモリ 16GB 以上推奨。", "Tuned specifically for Japanese. Natural, polished output. 16 GB+ RAM recommended."),
            japaneseStars: 5,
            tag: tr("日本語特化", "Japanese-tuned")
        ),
        BuiltinModel(
            fileName: "gemma-3-4b-it-Q4_K_M.gguf",
            displayName: "Gemma 3 4B",
            vendor: "Google / ggml-org",
            quant: "Q4_K_M",
            sizeBytes: 2_489_757_856,
            url: URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!,
            description: tr("Google 製。多言語で堅実、動作も軽快。", "By Google. Solid across languages and light on resources."),
            japaneseStars: 4,
            tag: nil
        ),
        BuiltinModel(
            fileName: "Qwen3-1.7B-Q8_0.gguf",
            displayName: "Qwen3 1.7B",
            vendor: tr("Alibaba(公式)", "Alibaba (Official)"),
            quant: "Q8_0",
            sizeBytes: 1_834_426_016,
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf")!,
            description: tr("軽量・高速。省メモリ環境や応答速度重視の方に。", "Light and fast. Great for low-memory setups or quick responses."),
            japaneseStars: 4,
            tag: tr("軽量", "Lightweight")
        ),
        BuiltinModel(
            fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            displayName: "Llama 3.2 3B",
            vendor: "Meta / bartowski",
            quant: "Q4_K_M",
            sizeBytes: 2_019_377_696,
            url: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            description: tr("英語の指示整形に強い。日本語はやや簡素。", "Strong at refining English prompts. Japanese output is fairly plain."),
            japaneseStars: 3,
            tag: nil
        ),
        BuiltinModel(
            fileName: "Qwen3-0.6B-Q8_0.gguf",
            displayName: "Qwen3 0.6B",
            vendor: tr("Alibaba(公式)", "Alibaba (Official)"),
            quant: "Q8_0",
            sizeBytes: 639_446_688,
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf")!,
            description: tr("1〜2 分でダウンロードできる超軽量。まず動きを試したい方に。", "Ultra-light — downloads in a minute or two. Great for a first test run."),
            japaneseStars: 2,
            tag: tr("お試し", "Starter")
        ),
    ] }
}
