// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Openly",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Openly",
            path: "Sources",
            exclude: [
                // Xcode-only preview helpers excluded from CLI builds
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Disable macro-required features that need Xcode
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
