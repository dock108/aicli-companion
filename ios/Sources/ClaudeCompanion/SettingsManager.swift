import Foundation
import Combine

public class SettingsManager: ObservableObject {
    @Published var theme: Theme = .system
    @Published var fontSize: FontSize = .medium
    @Published var autoScroll: Bool = true
    @Published var showTypingIndicators: Bool = true
    @Published var hapticFeedback: Bool = true
    @Published var storeChatHistory: Bool = false
    @Published var isPremium: Bool = false

    private let userDefaults = UserDefaults.standard
    private let keychain = KeychainManager()

    var currentConnection: ServerConnection? {
        get {
            guard let data = userDefaults.data(forKey: SettingsKey.currentConnection.rawValue),
                  let connection = try? JSONDecoder().decode(ServerConnection.self, from: data) else {
                return nil
            }
            return connection
        }
        set {
            if let connection = newValue,
               let data = try? JSONEncoder().encode(connection) {
                userDefaults.set(data, forKey: SettingsKey.currentConnection.rawValue)
            } else {
                userDefaults.removeObject(forKey: SettingsKey.currentConnection.rawValue)
            }
        }
    }

    var appSettings: AppSettings {
        get {
            guard let data = userDefaults.data(forKey: SettingsKey.appSettings.rawValue),
                  let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return AppSettings()
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: SettingsKey.appSettings.rawValue)
            }
        }
    }

    public init() {
        loadSettings()
    }

    // MARK: - Settings Management

    private func loadSettings() {
        let settings = appSettings

        theme = settings.theme
        fontSize = settings.fontSize
        autoScroll = settings.autoScroll
        showTypingIndicators = settings.showTypingIndicators
        hapticFeedback = settings.hapticFeedback
        storeChatHistory = settings.storeChatHistory
        isPremium = settings.isPremium
    }

    func saveSettings() {
        var settings = appSettings

        settings.theme = theme
        settings.fontSize = fontSize
        settings.autoScroll = autoScroll
        settings.showTypingIndicators = showTypingIndicators
        settings.hapticFeedback = hapticFeedback
        settings.storeChatHistory = storeChatHistory
        settings.isPremium = isPremium

        appSettings = settings
    }

    // MARK: - Connection Management

    func saveConnection(address: String, port: Int, token: String?) {
        let connection = ServerConnection(
            address: address,
            port: port,
            authToken: token,
            isSecure: port == 443
        )

        currentConnection = connection

        // Save auth token securely in keychain if provided
        if let token = token, !token.isEmpty {
            keychain.save(token, forKey: "auth_token_\(address)_\(port)")
        }
    }

    func clearConnection() {
        if let connection = currentConnection {
            // Remove auth token from keychain
            keychain.delete(forKey: "auth_token_\(connection.address)_\(connection.port)")
        }

        currentConnection = nil
    }

    func hasValidConnection() -> Bool {
        return currentConnection != nil
    }

    // MARK: - Chat History

    func saveChatHistory(_ messages: [Message]) {
        guard storeChatHistory else { return }

        if let data = try? JSONEncoder().encode(messages) {
            userDefaults.set(data, forKey: SettingsKey.chatHistory.rawValue)
        }
    }

    func loadChatHistory() -> [Message] {
        guard storeChatHistory,
              let data = userDefaults.data(forKey: SettingsKey.chatHistory.rawValue),
              let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            return []
        }

        return messages
    }

    func clearChatHistory() {
        userDefaults.removeObject(forKey: SettingsKey.chatHistory.rawValue)
    }

    // MARK: - Premium Features

    func isPremiumFeatureAvailable(_ feature: PremiumFeature) -> Bool {
        if isPremium {
            return true
        }

        // Some features might be available in free tier with limitations
        switch feature {
        case .remoteConnections, .notifications, .offlineQueue, .cliMode, .multipleConnections, .advancedCustomization:
            return false
        }
    }

    func unlockPremiumFeatures() {
        var settings = appSettings
        settings.isPremium = true
        settings.allowRemoteConnections = true
        settings.enableNotifications = true
        settings.enableOfflineQueue = true
        settings.enableCLIMode = true
        settings.allowMultipleConnections = true
        appSettings = settings

        isPremium = true
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        get {
            userDefaults.bool(forKey: SettingsKey.hasCompletedOnboarding.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: SettingsKey.hasCompletedOnboarding.rawValue)
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        // Clear all user defaults
        for key in SettingsKey.allCases {
            userDefaults.removeObject(forKey: key.rawValue)
        }

        // Clear keychain
        keychain.deleteAll()

        // Reset published properties
        let defaultSettings = AppSettings()
        theme = defaultSettings.theme
        fontSize = defaultSettings.fontSize
        autoScroll = defaultSettings.autoScroll
        showTypingIndicators = defaultSettings.showTypingIndicators
        hapticFeedback = defaultSettings.hapticFeedback
        storeChatHistory = defaultSettings.storeChatHistory
        isPremium = defaultSettings.isPremium
    }
}

// MARK: - Extensions

extension SettingsKey: CaseIterable {
    static var allCases: [SettingsKey] {
        return [
            .appSettings,
            .currentConnection,
            .savedConnections,
            .chatHistory,
            .lastSessionId,
            .hasCompletedOnboarding,
            .purchaseTransactions
        ]
    }
}
