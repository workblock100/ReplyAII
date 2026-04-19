// swift-tools-version:5.10
import PackageDescription

// SwiftPM target so the app can be built without Xcode. The resulting
// executable is wrapped into a .app bundle by scripts/build.sh.
//
// Keep this in sync with project.yml — the same sources and resources
// are consumed by both build paths.
let package = Package(
    name: "ReplyAI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReplyAI", targets: ["ReplyAI"]),
    ],
    targets: [
        .executableTarget(
            name: "ReplyAI",
            path: "Sources/ReplyAI",
            exclude: [
                "Resources/Info.plist",
                "Resources/ReplyAI.entitlements",
                "Resources/Fonts/README.md",
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
