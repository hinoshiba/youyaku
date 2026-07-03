// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Youyaku",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Youyaku",
            dependencies: ["llama"],
            path: "Sources/Youyaku"
        ),
        // llama.cpp 公式リリース(b9859)の xcframework
        .binaryTarget(
            name: "llama",
            path: "Vendor/build-apple/llama.xcframework"
        ),
    ]
)
