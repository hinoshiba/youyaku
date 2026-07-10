// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Youyaku",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Youyaku",
            dependencies: ["llama", "Sparkle"],
            path: "Sources/Youyaku"
        ),
        // llama.cpp 公式リリース(b9859)の xcframework
        .binaryTarget(
            name: "llama",
            path: "Vendor/build-apple/llama.xcframework"
        ),
        // Sparkle 公式リリース(2.9.4)の xcframework。直販版の自動更新に使う
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
        ),
    ]
)
