//
//  SettingsManager.swift
//  AICLICompanionHost
//
//  Manages app settings and preferences
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Published Properties
    @AppStorage("serverPort") var serverPort: Int = 3001
    @AppStorage("autoStartServer") var autoStartServer: Bool = false
    @AppStorage("autoRestartOnCrash") var autoRestartOnCrash: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showDockIcon") var showDockIcon: Bool = false
    @AppStorage("enableNotifications") var enableNotifications: Bool = true
    @AppStorage("enableSounds") var enableSounds: Bool = true
    @AppStorage("logLevel") var logLevel: String = "info"
    @AppStorage("maxLogEntries") var maxLogEntries: Int = 1000
    @AppStorage("enableBonjour") var enableBonjour: Bool = true
    @AppStorage("theme") var theme: String = "system"

    // Security Settings
    @AppStorage("requireAuthentication") var requireAuthentication: Bool = true
    @AppStorage("enableTouchID") var enableTouchID: Bool = true

    // Internet Access Settings
    @AppStorage("enableTunnel") var enableTunnel: Bool = false
    @AppStorage("tunnelProvider") var tunnelProvider: String = "ngrok"
    @AppStorage("ngrokAuthToken") var ngrokAuthToken: String = ""

    // Project Settings
    @AppStorage("defaultProjectDirectory") var defaultProjectDirectory: String = ""

    // Advanced Settings
    @AppStorage("serverCommand") var serverCommand: String = "npm start"
    // Server directory - deprecated, kept for compatibility
    @AppStorage("serverDirectory") var serverDirectory: String = ""
    @AppStorage("nodeExecutable") var nodeExecutable: String = ""  // Empty means auto-detect
    @AppStorage("npmExecutable") var npmExecutable: String = ""  // Empty means auto-detect

    // MARK: - Configuration Change Tracking
    @Published var configurationChanged: Bool = false

    // Store initial configuration to track changes
    private var initialConfiguration: [String: Any] = [:]

    // MARK: - Computed Properties
    var needsRestart: Bool {
        // Server needs restart if configuration has changed and server is running
        return configurationChanged && (ServerManager.shared.isRunning)
    }

    // MARK: - Private Properties
    private init() {
        captureInitialConfiguration()
        setupConfigurationTracking()
    }

    // MARK: - Public Methods
    func resetToDefaults() {
        serverPort = 3001
        autoStartServer = false
        autoRestartOnCrash = true
        launchAtLogin = false
        showDockIcon = false
        enableNotifications = true
        enableSounds = true
        logLevel = "info"
        maxLogEntries = 1000
        enableBonjour = true
        theme = "system"
        requireAuthentication = true
        enableTouchID = true
        enableTunnel = false
        tunnelProvider = "ngrok"
        ngrokAuthToken = ""
        defaultProjectDirectory = ""
        serverCommand = "npm start"
        serverDirectory = "/Users/michaelfuscoletti/Desktop/claude-companion/server"
        nodeExecutable = ""  // Reset to auto-detect
        npmExecutable = ""  // Reset to auto-detect
    }

    func exportSettings() -> Data? {
        let settings: [String: Any] = [
            "serverPort": serverPort,
            "autoStartServer": autoStartServer,
            "launchAtLogin": launchAtLogin,
            "showDockIcon": showDockIcon,
            "enableNotifications": enableNotifications,
            "enableSounds": enableSounds,
            "logLevel": logLevel,
            "maxLogEntries": maxLogEntries,
            "enableBonjour": enableBonjour,
            "theme": theme,
            "requireAuthentication": requireAuthentication,
            "enableTouchID": enableTouchID,
            "enableTunnel": enableTunnel,
            "tunnelProvider": tunnelProvider,
            "ngrokAuthToken": ngrokAuthToken,
            "defaultProjectDirectory": defaultProjectDirectory,
            "serverCommand": serverCommand,
            "serverDirectory": serverDirectory,
            "nodeExecutable": nodeExecutable,
            "npmExecutable": npmExecutable
        ]

        return try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    }

    func importSettings(from data: Data) throws {
        guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalidFormat
        }

        importGeneralSettings(from: settings)
        importServerSettings(from: settings)
        importSecuritySettings(from: settings)
        importAdvancedSettings(from: settings)
    }

    private func importGeneralSettings(from settings: [String: Any]) {
        if let autoStart = settings["autoStartServer"] as? Bool {
            autoStartServer = autoStart
        }

        if let launchLogin = settings["launchAtLogin"] as? Bool {
            launchAtLogin = launchLogin
        }

        if let dockIcon = settings["showDockIcon"] as? Bool {
            showDockIcon = dockIcon
        }

        if let notifications = settings["enableNotifications"] as? Bool {
            enableNotifications = notifications
        }

        if let sounds = settings["enableSounds"] as? Bool {
            enableSounds = sounds
        }

        if let themeValue = settings["theme"] as? String {
            theme = themeValue
        }

        if let projectDir = settings["defaultProjectDirectory"] as? String {
            defaultProjectDirectory = projectDir
        }
    }

    private func importServerSettings(from settings: [String: Any]) {
        if let port = settings["serverPort"] as? Int, port >= 1024, port <= 65535 {
            serverPort = port
        }

        if let level = settings["logLevel"] as? String {
            logLevel = level
        }

        if let maxLogs = settings["maxLogEntries"] as? Int, maxLogs > 0 {
            maxLogEntries = maxLogs
        }

        if let bonjour = settings["enableBonjour"] as? Bool {
            enableBonjour = bonjour
        }
    }

    private func importSecuritySettings(from settings: [String: Any]) {
        if let auth = settings["requireAuthentication"] as? Bool {
            requireAuthentication = auth
        }

        if let touchID = settings["enableTouchID"] as? Bool {
            enableTouchID = touchID
        }

        if let tunnel = settings["enableTunnel"] as? Bool {
            enableTunnel = tunnel
        }

        if let provider = settings["tunnelProvider"] as? String {
            tunnelProvider = provider
        }

        if let ngrokToken = settings["ngrokAuthToken"] as? String {
            ngrokAuthToken = ngrokToken
        }
    }

    private func importAdvancedSettings(from settings: [String: Any]) {
        if let cmd = settings["serverCommand"] as? String {
            serverCommand = cmd
        }

        if let dir = settings["serverDirectory"] as? String {
            serverDirectory = dir
        }

        if let node = settings["nodeExecutable"] as? String {
            nodeExecutable = node
        }

        if let npm = settings["npmExecutable"] as? String {
            npmExecutable = npm
        }
    }

    /// Mark configuration as applied (call after successful restart)
    func markConfigurationApplied() {
        configurationChanged = false
        captureInitialConfiguration()
    }

    /// Force mark configuration as changed (useful for manual tracking)
    func markConfigurationChanged() {
        configurationChanged = true
    }

    // MARK: - Private Methods
    private func captureInitialConfiguration() {
        initialConfiguration = [
            "serverPort": serverPort,
            "requireAuthentication": requireAuthentication,
            "enableTunnel": enableTunnel,
            "tunnelProvider": tunnelProvider,
            "ngrokAuthToken": ngrokAuthToken,
            "nodeExecutable": nodeExecutable,
            "npmExecutable": npmExecutable
        ]
    }

    private func setupConfigurationTracking() {
        // Track changes to server-relevant settings using @Published properties
        // We'll use objectWillChange to detect any changes to the SettingsManager
        objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.checkForConfigurationChanges()
            }
            .store(in: &cancellables)
    }

    private func checkForConfigurationChanges() {
        let currentConfiguration: [String: Any] = [
            "serverPort": serverPort,
            "requireAuthentication": requireAuthentication,
            "enableTunnel": enableTunnel,
            "tunnelProvider": tunnelProvider,
            "ngrokAuthToken": ngrokAuthToken,
            "nodeExecutable": nodeExecutable,
            "npmExecutable": npmExecutable
        ]

        // Compare current with initial configuration
        for (key, currentValue) in currentConfiguration {
            if let initialValue = initialConfiguration[key] {
                // Use string comparison for consistency
                if String(describing: currentValue) != String(describing: initialValue) {
                    configurationChanged = true
                    return
                }
            } else {
                configurationChanged = true
                return
            }
        }

        configurationChanged = false
    }

    // Add cancellables storage
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Environment Variable Support

    /// Set an environment variable for the server process
    func setEnvironmentVariable(_ name: String, value: String) {
        UserDefaults.standard.set(value, forKey: "env_\(name)")
        configurationChanged = true
    }

    /// Get an environment variable value
    func getEnvironmentVariable(_ name: String) -> String? {
        return UserDefaults.standard.string(forKey: "env_\(name)")
    }

    /// Remove an environment variable
    func removeEnvironmentVariable(_ name: String) {
        UserDefaults.standard.removeObject(forKey: "env_\(name)")
        configurationChanged = true
    }

    /// Get all environment variables as a dictionary
    func getAllEnvironmentVariables() -> [String: String] {
        var envVars: [String: String] = [:]

        // Get all UserDefaults keys that start with "env_"
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            if key.hasPrefix("env_"), let stringValue = value as? String {
                let envName = String(key.dropFirst(4)) // Remove "env_" prefix
                envVars[envName] = stringValue
            }
        }

        return envVars
    }
}

// MARK: - Supporting Types
enum SettingsError: LocalizedError {
    case invalidFormat
    case importFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid settings file format"
        case .importFailed:
            return "Failed to import settings"
        }
    }
}
