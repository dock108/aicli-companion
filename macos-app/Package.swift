// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClaudeCompanionHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ClaudeCompanionHost",
            targets: ["ClaudeCompanionHost"]
        )
    ],
    dependencies: [
        // Add any external dependencies here if needed
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCompanionHost",
            dependencies: [],
            path: "ClaudeCompanionHost",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "ClaudeCompanionHostTests",
            dependencies: ["ClaudeCompanionHost"]
        )
    ]
)
