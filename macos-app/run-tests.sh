#!/bin/bash

# Script to compile and run macOS tests with all test files

echo "🧪 Running macOS App Tests..."

cd "$(dirname "$0")"

# Create a temporary Package.swift for SPM-based testing
cat > Package.swift << 'EOF'
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "AICLICompanionHost",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "AICLICompanionHost", targets: ["AICLICompanionHost"])
    ],
    targets: [
        .executableTarget(
            name: "AICLICompanionHost",
            path: "AICLICompanionHost"
        ),
        .testTarget(
            name: "AICLICompanionHostTests",
            dependencies: ["AICLICompanionHost"],
            path: "AICLICompanionHostTests"
        )
    ]
)
EOF

# Try to build with SPM
echo "Building with Swift Package Manager..."
swift build

# Run tests
echo "Running tests..."
swift test --enable-code-coverage

# Clean up
rm Package.swift

echo "✅ Tests completed!"