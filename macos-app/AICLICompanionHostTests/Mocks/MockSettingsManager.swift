//
//  MockSettingsManager.swift
//  AICLICompanionHostTests
//
//  Mock settings manager for unit testing without UserDefaults
//

import Foundation
import Combine
@testable import AICLICompanionHost

@MainActor
class MockSettingsManager: ObservableObject {
    // MARK: - Settings Properties (in-memory storage)
    @Published var serverPort: Int = 3001
    @Published var autoStartServer: Bool = false
    @Published var autoRestartOnCrash: Bool = true
    @Published var launchAtLogin: Bool = false
    @Published var showDockIcon: Bool = false
    @Published var enableNotifications: Bool = true
    @Published var enableSounds: Bool = true
    @Published var logLevel: String = "info"
    @Published var maxLogEntries: Int = 1000
    @Published var enableBonjour: Bool = true
    @Published var theme: String = "system"

    // Security Settings
    @Published var requireAuthentication: Bool = true
    @Published var enableTouchID: Bool = true

    // Internet Access Settings
    @Published var enableTunnel: Bool = false
    @Published var tunnelProvider: String = "ngrok"
    @Published var ngrokAuthToken: String = ""

    // Project Settings
    @Published var defaultProjectDirectory: String = ""

    // Advanced Settings
    @Published var serverCommand: String = "npm start"
    @Published var serverDirectory: String = ""
    @Published var nodeExecutable: String = ""
    @Published var npmExecutable: String = ""

    // MARK: - Configuration Change Tracking
    @Published var configurationChanged: Bool = false

    // MARK: - Test Tracking Properties
    var resetToDefaultsCalled = false
    var exportSettingsCalled = false
    var importSettingsCalled = false
    var markConfigurationAppliedCalled = false
    var validateSettingsCalled = false

    // Store initial configuration to track changes
    private var initialConfiguration: [String: Any] = [:]

    // MARK: - Computed Properties
    var needsRestart: Bool {
        return configurationChanged
    }

    // MARK: - Initialization
    init() {
        captureInitialConfiguration()
    }

    // MARK: - Public Methods

    func resetToDefaults() {
        resetToDefaultsCalled = true

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
        serverDirectory = ""
        nodeExecutable = ""
        npmExecutable = ""

        configurationChanged = false
    }

    func exportSettings() -> Data? {
        exportSettingsCalled = true

        let settings: [String: Any] = [
            "serverPort": serverPort,
            "autoStartServer": autoStartServer,
            "autoRestartOnCrash": autoRestartOnCrash,
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

        return try? JSONSerialization.data(withJSONObject: settings)
    }

    func importSettings(from data: Data) -> Bool {
        importSettingsCalled = true

        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        // Import settings from dictionary
        if let value = settings["serverPort"] as? Int { serverPort = value }
        if let value = settings["autoStartServer"] as? Bool { autoStartServer = value }
        if let value = settings["autoRestartOnCrash"] as? Bool { autoRestartOnCrash = value }
        if let value = settings["launchAtLogin"] as? Bool { launchAtLogin = value }
        if let value = settings["showDockIcon"] as? Bool { showDockIcon = value }
        if let value = settings["enableNotifications"] as? Bool { enableNotifications = value }
        if let value = settings["enableSounds"] as? Bool { enableSounds = value }
        if let value = settings["logLevel"] as? String { logLevel = value }
        if let value = settings["maxLogEntries"] as? Int { maxLogEntries = value }
        if let value = settings["enableBonjour"] as? Bool { enableBonjour = value }
        if let value = settings["theme"] as? String { theme = value }
        if let value = settings["requireAuthentication"] as? Bool { requireAuthentication = value }
        if let value = settings["enableTouchID"] as? Bool { enableTouchID = value }
        if let value = settings["enableTunnel"] as? Bool { enableTunnel = value }
        if let value = settings["tunnelProvider"] as? String { tunnelProvider = value }
        if let value = settings["ngrokAuthToken"] as? String { ngrokAuthToken = value }
        if let value = settings["defaultProjectDirectory"] as? String { defaultProjectDirectory = value }
        if let value = settings["serverCommand"] as? String { serverCommand = value }
        if let value = settings["serverDirectory"] as? String { serverDirectory = value }
        if let value = settings["nodeExecutable"] as? String { nodeExecutable = value }
        if let value = settings["npmExecutable"] as? String { npmExecutable = value }

        configurationChanged = true
        return true
    }

    func markConfigurationApplied() {
        markConfigurationAppliedCalled = true
        configurationChanged = false
        captureInitialConfiguration()
    }

    func validateSettings() -> (isValid: Bool, errors: [String]) {
        validateSettingsCalled = true

        var errors: [String] = []

        // Validate port range
        if serverPort < 1024 || serverPort > 65535 {
            errors.append("Server port must be between 1024 and 65535")
        }

        // Validate max log entries
        if maxLogEntries < 100 || maxLogEntries > 10000 {
            errors.append("Max log entries must be between 100 and 10000")
        }

        // Validate log level
        let validLogLevels = ["debug", "info", "warning", "error"]
        if !validLogLevels.contains(logLevel) {
            errors.append("Invalid log level")
        }

        // Validate tunnel settings
        if enableTunnel && tunnelProvider == "ngrok" && ngrokAuthToken.isEmpty {
            errors.append("ngrok auth token is required when tunnel is enabled")
        }

        return (errors.isEmpty, errors)
    }

    // MARK: - Private Methods

    private func captureInitialConfiguration() {
        initialConfiguration = [
            "serverPort": serverPort,
            "autoStartServer": autoStartServer,
            "autoRestartOnCrash": autoRestartOnCrash,
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
    }

    func checkForConfigurationChanges() {
        let currentConfig: [String: Any] = [
            "serverPort": serverPort,
            "autoStartServer": autoStartServer,
            "autoRestartOnCrash": autoRestartOnCrash,
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

        // Check if any value has changed
        configurationChanged = false
        for (key, value) in currentConfig {
            if let initialValue = initialConfiguration[key] {
                if !areEqual(value, initialValue) {
                    configurationChanged = true
                    break
                }
            }
        }
    }

    private func areEqual(_ a: Any, _ b: Any) -> Bool {
        if let aInt = a as? Int, let bInt = b as? Int {
            return aInt == bInt
        }
        if let aBool = a as? Bool, let bBool = b as? Bool {
            return aBool == bBool
        }
        if let aString = a as? String, let bString = b as? String {
            return aString == bString
        }
        return false
    }

    // MARK: - Test Helpers

    func reset() {
        resetToDefaults()

        resetToDefaultsCalled = false
        exportSettingsCalled = false
        importSettingsCalled = false
        markConfigurationAppliedCalled = false
        validateSettingsCalled = false

        configurationChanged = false
        captureInitialConfiguration()
    }
}