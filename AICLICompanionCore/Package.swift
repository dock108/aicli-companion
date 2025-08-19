// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AICLICompanionCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AICLICompanionCore",
            targets: ["AICLICompanionCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AICLICompanionCore",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "AICLICompanionCoreTests",
            dependencies: ["AICLICompanionCore"],
            path: "Tests"
        )
    ]
)