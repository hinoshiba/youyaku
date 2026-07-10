// swift-tools-version:5.10
import PackageDescription

// Youyaku プロンプト評価ハーネス。
// Sources/eval/ には出荷ソース(Refiner / LlamaEngine / Sanitizer)への
// リポジトリ相対 symlink が置いてあり、それを直接コンパイルする。
// つまりここで測る挙動はアプリの挙動そのもの。
let package = Package(
    name: "youyaku-eval",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "eval",
            dependencies: ["llama"],
            path: "Sources/eval"
        ),
        .binaryTarget(
            name: "llama",
            path: "../../Vendor/build-apple/llama.xcframework"
        ),
    ]
)
