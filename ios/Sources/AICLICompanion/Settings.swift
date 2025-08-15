import Foundation

// MARK: - App Settings

enum Theme: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum FontSize: String, CaseIterable, Codable {
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.2
        }
    }
}

struct AppSettings: Codable {
    var theme: Theme = .system
    var fontSize: FontSize = .medium
    var autoScroll: Bool = true
    var showTypingIndicators: Bool = true
    var hapticFeedback: Bool = true
    var storeChatHistory: Bool = true
    var maxChatHistory: Int = 100

    // Premium features
    var isPremium: Bool = false
    var allowRemoteConnections: Bool = false
    var enableNotifications: Bool = false
    var enableOfflineQueue: Bool = false
    var enableCLIMode: Bool = false
    var allowMultipleConnections: Bool = false
}

// MARK: - Premium Features

enum PremiumFeature: String, CaseIterable {
    case remoteConnections = "remote_connections"
    case notifications = "notifications"
    case offlineQueue = "offline_queue"
    case cliMode = "cli_mode"
    case multipleConnections = "multiple_connections"
    case advancedCustomization = "advanced_customization"

    var displayName: String {
        switch self {
        case .remoteConnections: return "Remote Access"
        case .notifications: return "Push Notifications"
        case .offlineQueue: return "Offline Queue"
        case .cliMode: return "CLI Terminal Mode"
        case .multipleConnections: return "Multiple Servers"
        case .advancedCustomization: return "Advanced Themes"
        }
    }

    var description: String {
        switch self {
        case .remoteConnections:
            return "Connect to your Claude Code server from anywhere over the internet"
        case .notifications:
            return "Get notified when Claude needs your input or completes tasks"
        case .offlineQueue:
            return "Compose messages offline and send them when connection is restored"
        case .cliMode:
            return "Access full terminal interface for advanced CLI interactions"
        case .multipleConnections:
            return "Save and switch between multiple Claude Code servers"
        case .advancedCustomization:
            return "Custom themes, syntax highlighting, and UI customization"
        }
    }

    var systemImageName: String {
        switch self {
        case .remoteConnections: return "globe"
        case .notifications: return "bell"
        case .offlineQueue: return "tray.and.arrow.down"
        case .cliMode: return "terminal"
        case .multipleConnections: return "server.rack"
        case .advancedCustomization: return "paintbrush"
        }
    }
}

// MARK: - Settings Keys

enum SettingsKey: String {
    case appSettings = "app_settings"
    case currentConnection = "current_connection"
    case savedConnections = "saved_connections"
    case chatHistory = "chat_history"
    case lastSessionId = "last_session_id"
    case hasCompletedOnboarding = "has_completed_onboarding"
    case purchaseTransactions = "purchase_transactions"
}
