// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AICLICompanionHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AICLICompanionHost",
            targets: ["AICLICompanionHost"]
        )
    ],
    dependencies: [
        // Add any external dependencies here if needed
    ],
    targets: [
        .executableTarget(
            name: "AICLICompanionHost",
            dependencies: [],
            path: "AICLICompanionHost",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "AICLICompanionHostTests",
            dependencies: ["AICLICompanionHost"],
            path: "AICLICompanionHostTests"
        )
    ]
)
