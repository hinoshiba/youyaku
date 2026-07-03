import Foundation

struct CatalogModel: Identifiable {
    let name: String          // ollama のモデルタグ
    let title: String
    let vendor: String
    let sizeLabel: String
    let description: String
    let japaneseStars: Int    // 1-5
    let recommended: Bool

    var id: String { name }
}

enum ModelCatalog {
    static var all: [CatalogModel] { [
        CatalogModel(
            name: "gemma3:4b",
            title: "Gemma 3 4B",
            vendor: "Google",
            sizeLabel: "3.3 GB",
            description: tr("小型ながら日本語が自然。速度と品質のバランスが良く、最初の 1 台に最適。", "Small yet natural in Japanese. A great balance of speed and quality — the ideal first pick."),
            japaneseStars: 4,
            recommended: true
        ),
        CatalogModel(
            name: "qwen3:8b",
            title: "Qwen 3 8B",
            vendor: "Alibaba",
            sizeLabel: "5.2 GB",
            description: tr("日本語性能トップクラス。メモリ 16GB 以上ならこちらがおすすめ。", "Top-tier Japanese quality. Recommended if you have 16 GB+ RAM."),
            japaneseStars: 5,
            recommended: true
        ),
        CatalogModel(
            name: "qwen3:4b",
            title: "Qwen 3 4B",
            vendor: "Alibaba",
            sizeLabel: "2.6 GB",
            description: tr("軽量・高速で日本語も良好。省メモリ環境向け。", "Light and fast with solid Japanese. Good for low-memory setups."),
            japaneseStars: 4,
            recommended: false
        ),
        CatalogModel(
            name: "gemma3:12b",
            title: "Gemma 3 12B",
            vendor: "Google",
            sizeLabel: "8.1 GB",
            description: tr("高品質な整形が可能。メモリ 24GB 以上推奨。", "High-quality refinement. 24 GB+ RAM recommended."),
            japaneseStars: 5,
            recommended: false
        ),
        CatalogModel(
            name: "llama3.2:3b",
            title: "Llama 3.2 3B",
            vendor: "Meta",
            sizeLabel: "2.0 GB",
            description: tr("非常に軽量で高速。英語の指示整形に強い。", "Very light and fast. Strong at refining English prompts."),
            japaneseStars: 3,
            recommended: false
        ),
        CatalogModel(
            name: "phi4-mini:3.8b",
            title: "Phi-4 Mini",
            vendor: "Microsoft",
            sizeLabel: "2.5 GB",
            description: tr("推論が得意な小型モデル。技術系の指示整理に。", "A small model that excels at reasoning. Great for technical prompts."),
            japaneseStars: 3,
            recommended: false
        ),
    ] }
}
