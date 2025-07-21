// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCompanion",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ClaudeCompanion",
            targets: ["ClaudeCompanion"])
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "ClaudeCompanion",
            dependencies: [
                "Starscream",
                .product(name: "Markdown", package: "swift-markdown"),
                "KeychainAccess",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            exclude: [
                "ClaudeCompanionApp.swift",
                "AccessibilityHelpers.swift",
                "AnimationConstants.swift",
                "ChatView.swift",
                "ConnectionView.swift",
                "ContentView.swift",
                "ConversationHistoryView.swift",
                "DevelopmentWorkflowView.swift",
                "FileBrowserView.swift",
                "ProjectContextView.swift",
                "SettingsView.swift",
                "RichContentRenderer.swift",
                "ToolActivity.swift",
                "WebSocketService.swift",
                "ServiceDiscoveryManager.swift",
                "FileManagementService.swift",
                "ConversationPersistenceService.swift",
                "DevelopmentWorkflowService.swift",
                "ProjectAwarenessService.swift"
            ]
        ),
        .testTarget(
            name: "ClaudeCompanionTests",
            dependencies: ["ClaudeCompanion"]
        )
    ]
)
