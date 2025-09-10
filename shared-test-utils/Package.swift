// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SharedTestUtils",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SharedTestUtils",
            targets: ["SharedTestUtils"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SharedTestUtils",
            dependencies: [],
            path: "Sources"
        )
    ]
)
