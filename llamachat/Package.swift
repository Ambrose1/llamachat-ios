// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaChat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LlamaKit", targets: ["LlamaKit"]),
        .executable(name: "LlamaChatApp", targets: ["LlamaChatApp"]),
    ],
    targets: [
        .target(
            name: "LlamaKit",
            path: "Sources/LlamaKit"
        ),
        .executableTarget(
            name: "LlamaChatApp",
            dependencies: ["LlamaKit"],
            path: "App"
        ),
    ]
)
