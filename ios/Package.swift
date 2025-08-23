// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AICLICompanion",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "AICLICompanion",
            dependencies: [
                "Starscream",
                .product(name: "Markdown", package: "swift-markdown"),
                "KeychainAccess",
                .product(name: "Crypto", package: "swift-crypto")
            ]),
        .testTarget(
            name: "AICLICompanionTests",
            dependencies: [
                "AICLICompanion",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "ViewInspector", package: "ViewInspector")
            ])
    ]
)