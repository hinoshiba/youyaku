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
}

// 認証不要で直接ダウンロードできることを検証済みの GGUF カタログ(2026-07 時点)
enum BuiltinCatalog {
    static let all: [BuiltinModel] = [
        BuiltinModel(
            fileName: "Qwen3-4B-Q4_K_M.gguf",
            displayName: "Qwen3 4B",
            vendor: "Alibaba(公式)",
            quant: "Q4_K_M",
            sizeBytes: 2_497_280_256,
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!,
            description: "日本語性能と速度のバランスが最良。迷ったらこれ。",
            japaneseStars: 5,
            tag: "おすすめ"
        ),
        BuiltinModel(
            fileName: "Llama-3-ELYZA-JP-8B-q4_k_m.gguf",
            displayName: "ELYZA JP 8B",
            vendor: "ELYZA(公式)",
            quant: "Q4_K_M",
            sizeBytes: 4_920_733_984,
            url: URL(string: "https://huggingface.co/elyza/Llama-3-ELYZA-JP-8B-GGUF/resolve/main/Llama-3-ELYZA-JP-8B-q4_k_m.gguf")!,
            description: "日本語特化チューニング。自然で丁寧な整形。メモリ 16GB 以上推奨。",
            japaneseStars: 5,
            tag: "日本語特化"
        ),
        BuiltinModel(
            fileName: "gemma-3-4b-it-Q4_K_M.gguf",
            displayName: "Gemma 3 4B",
            vendor: "Google / ggml-org",
            quant: "Q4_K_M",
            sizeBytes: 2_489_757_856,
            url: URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!,
            description: "Google 製。多言語で堅実、動作も軽快。",
            japaneseStars: 4,
            tag: nil
        ),
        BuiltinModel(
            fileName: "Qwen3-1.7B-Q8_0.gguf",
            displayName: "Qwen3 1.7B",
            vendor: "Alibaba(公式)",
            quant: "Q8_0",
            sizeBytes: 1_834_426_016,
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf")!,
            description: "軽量・高速。省メモリ環境や応答速度重視の方に。",
            japaneseStars: 4,
            tag: "軽量"
        ),
        BuiltinModel(
            fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            displayName: "Llama 3.2 3B",
            vendor: "Meta / bartowski",
            quant: "Q4_K_M",
            sizeBytes: 2_019_377_696,
            url: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            description: "英語の指示整形に強い。日本語はやや簡素。",
            japaneseStars: 3,
            tag: nil
        ),
        BuiltinModel(
            fileName: "Qwen3-0.6B-Q8_0.gguf",
            displayName: "Qwen3 0.6B",
            vendor: "Alibaba(公式)",
            quant: "Q8_0",
            sizeBytes: 639_446_688,
            url: URL(string: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf")!,
            description: "1〜2 分でダウンロードできる超軽量。まず動きを試したい方に。",
            japaneseStars: 2,
            tag: "お試し"
        ),
    ]
}
