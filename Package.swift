// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Koe",
            dependencies: ["llama"],
            path: "Sources/Koe"
        ),
        // llama.cpp 公式リリース(b9859)の xcframework
        .binaryTarget(
            name: "llama",
            path: "Vendor/build-apple/llama.xcframework"
        ),
    ]
)
