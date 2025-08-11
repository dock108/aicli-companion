import Foundation
import Combine

@available(iOS 16.0, macOS 13.0, *)
public class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var theme: Theme = .system
    @Published var fontSize: FontSize = .medium
    @Published var autoScroll: Bool = true
    @Published var showTypingIndicators: Bool = true
    @Published var hapticFeedback: Bool = true
    @Published var storeChatHistory: Bool = false
    @Published var isPremium: Bool = false
    
    // Connection status
    @Published var isConnected: Bool = false
    @Published var currentSessionId: String?
    
    // Additional settings for EnhancedSettingsView
    @Published var showMarkdownPreview: Bool = true
    @Published var showThinkingIndicator: Bool = true
    @Published var enableNotifications: Bool = true
    @Published var notificationSound: Bool = true
    @Published var notificationVibration: Bool = true
    @Published var notificationPreview: Bool = true
    @Published var debugMode: Bool = false
    @Published var showNetworkActivity: Bool = false

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
    
    var serverURL: URL? {
        return currentConnection?.url
    }
    
    var authToken: String? {
        guard let connection = currentConnection else { return nil }
        
        // Try to get token from keychain first
        let keychainKey = "auth_token_\(connection.address)_\(connection.port)"
        if let token = keychain.load(forKey: keychainKey), !token.isEmpty {
            return token
        }
        
        // Fallback to stored token
        return connection.authToken
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

    // MARK: - Additional Methods for EnhancedSettingsView
    
    func reconnect() {
        // Implementation for reconnect functionality
        print("🔄 Attempting to reconnect to server")
        // This would trigger reconnection logic
        isConnected = false
        // Actual reconnection logic would go here
    }
    
    func clearCache() {
        // Clear app cache
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        do {
            let cacheContents = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
            for file in cacheContents {
                let filePath = cacheURL.appendingPathComponent(file)
                try FileManager.default.removeItem(at: filePath)
            }
            print("🧹 Cache cleared successfully")
        } catch {
            print("❌ Failed to clear cache: \(error)")
        }
    }
    
    func getCacheSize() -> Int {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        var cacheSize = 0
        
        do {
            let cacheContents = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
            for file in cacheContents {
                let filePath = cacheURL.appendingPathComponent(file)
                let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
                if let fileSize = attributes[.size] as? Int {
                    cacheSize += fileSize
                }
            }
        } catch {
            print("❌ Failed to calculate cache size: \(error)")
        }
        
        return cacheSize
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
        
        // Reset additional properties
        showMarkdownPreview = true
        showThinkingIndicator = true
        enableNotifications = true
        notificationSound = true
        notificationVibration = true
        notificationPreview = true
        debugMode = false
        showNetworkActivity = false
        isConnected = false
        currentSessionId = nil
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
