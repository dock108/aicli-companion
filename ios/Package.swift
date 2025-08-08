// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AICLICompanion",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AICLICompanion",
            targets: ["AICLICompanion"])
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "AICLICompanion",
            dependencies: [
                "Starscream",
                .product(name: "Markdown", package: "swift-markdown"),
                "KeychainAccess",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            resources: [
                .process("Resources")
            ]),
        .testTarget(
            name: "AICLICompanionTests",
            dependencies: ["AICLICompanion"])
    ]
)