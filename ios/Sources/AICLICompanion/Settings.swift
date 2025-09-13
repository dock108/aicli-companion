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
    var enableNotifications: Bool = true
}

// MARK: - Settings Keys

enum SettingsKey: String {
    case appSettings = "app_settings"
    case currentConnection = "current_connection"
    case savedConnections = "saved_connections"
    case chatHistory = "chat_history"
    case lastSessionId = "last_session_id"
    case hasCompletedOnboarding = "has_completed_onboarding"
}
