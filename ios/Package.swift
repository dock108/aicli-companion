// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCompanion",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ClaudeCompanion",
            targets: ["ClaudeCompanion"]),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2")
    ],
    targets: [
        .target(
            name: "ClaudeCompanion",
            dependencies: [
                "Starscream",
                .product(name: "Markdown", package: "swift-markdown"),
                "KeychainAccess"
            ]
        ),
        .testTarget(
            name: "ClaudeCompanionTests",
            dependencies: ["ClaudeCompanion"]
        ),
    ]
)