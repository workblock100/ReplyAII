// swift-tools-version:5.10
import PackageDescription

// SwiftPM target so the app can be built without Xcode. The resulting
// executable is wrapped into a .app bundle by scripts/build.sh.
//
// REP-500 (2026-05-18) split the single ReplyAI executable into:
//   • ReplyAICore — library target; everything except MLX + the @main entry point.
//   • ReplyAIMLX  — library target; MLXDraftService only. Depends on MLXLLM etc.
//   • ReplyAI     — executable target; ReplyAIApp @main entry point only.
//   • ReplyAITests — test target; depends on ReplyAICore ONLY (NOT ReplyAIMLX).
//
// Why: the bundled .app exited ~1s after launch when `pref.model.useMLX=true`
// because dynamic library loading of MLXLLM / MLXHuggingFace / Tokenizers on
// the launch path triggered a clean exit (REP-ALERT-260504-1650). Splitting
// MLX into its own SPM target means MLX symbols only load when the user has
// explicitly opted in — and tests never link MLX, so the cold-build budget
// constraint (45–90 min) no longer applies to test runs.
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
        // The bulk of the app. No MLX dependency — anything depending solely
        // on ReplyAICore compiles in seconds rather than the 45–90 minute
        // MLX cold-build.
        .target(
            name: "ReplyAICore",
            dependencies: [],
            path: "Sources/ReplyAICore",
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
        // MLXDraftService isolated so its eager dylib loading (REP-ALERT-260504-1650)
        // only fires when the user has flipped pref.model.useMLX = true AND the
        // executable target actually constructs MLXDraftService at runtime.
        .target(
            name: "ReplyAIMLX",
            dependencies: [
                "ReplyAICore",
                .product(name: "MLXLLM",         package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon",    package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace",    package: "swift-huggingface"),
                .product(name: "Tokenizers",     package: "swift-transformers"),
            ],
            path: "Sources/ReplyAIMLX"
        ),
        // The @main entry point. Pulls in everything because at runtime the
        // user can flip useMLX=true and we need both halves present.
        .executableTarget(
            name: "ReplyAI",
            dependencies: ["ReplyAICore", "ReplyAIMLX"],
            path: "Sources/ReplyAIApp"
        ),
        // Tests depend on ReplyAICore ONLY — never on ReplyAIMLX or the
        // executable. This is the load-bearing invariant of REP-500: an
        // MLXDraftService-touching test must live in `ReplyAIMLXTests`
        // (below), not here, so the main test suite never links MLX.
        .testTarget(
            name: "ReplyAITests",
            dependencies: ["ReplyAICore"],
            path: "Tests/ReplyAITests"
        ),
        // MLX-specific tests. Depends on ReplyAIMLX (and transitively
        // ReplyAICore). Pulls MLX into its build graph by design — these
        // tests are how the MLX-touching contracts stay pinned. Run them
        // only when you intend to compile MLX (40+ min cold cache); the
        // autopilot's primary test gate uses `--skip` on these or invokes
        // `swift test --filter ReplyAITests` to stay off the MLX path.
        .testTarget(
            name: "ReplyAIMLXTests",
            dependencies: ["ReplyAIMLX", "ReplyAICore"],
            path: "Tests/ReplyAIMLXTests"
        ),
    ]
)
