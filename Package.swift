// swift-tools-version:5.10
import PackageDescription

// SwiftPM target so the app can be built without Xcode. The resulting
// executable is wrapped into a .app bundle by scripts/build.sh.
let package = Package(
    name: "ReplyAI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReplyAI", targets: ["ReplyAI"]),
    ],
    dependencies: [
        // On-device LLM inference.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.0"),
        // HubClient (HuggingFace Hub downloader). mlx-swift-lm's MLXHuggingFace
        // macros expand to code that references HubClient.default; we must
        // link the transport ourselves.
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
        // AutoTokenizer + Tokenizer conformances. Used via macro expansion
        // from #huggingFaceTokenizerLoader().
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "ReplyAI",
            dependencies: [
                .product(name: "MLXLLM",         package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon",    package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace",    package: "swift-huggingface"),
                .product(name: "Tokenizers",     package: "swift-transformers"),
            ],
            path: "Sources/ReplyAI",
            exclude: [
                "Resources/Info.plist",
                "Resources/ReplyAI.entitlements",
                "Resources/Fonts/README.md",
                // The .icns is consumed at bundle time by scripts/build.sh,
                // which copies it directly into Contents/Resources. SwiftPM
                // doesn't need to process it.
                "Resources/AppIcon.icns",
            ],
            resources: [
                .copy("Resources/Fonts"),
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "ReplyAITests",
            dependencies: ["ReplyAI"],
            path: "Tests/ReplyAITests"
        ),
    ]
)
