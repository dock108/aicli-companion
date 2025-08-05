//
//  SettingsManager.swift
//  ClaudeCompanionHost
//
//  Manages app settings and preferences
//

import Foundation
import SwiftUI

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
    
    // Advanced Settings
    @AppStorage("serverCommand") var serverCommand: String = "npm start"
    @AppStorage("serverDirectory") var serverDirectory: String = ""
    @AppStorage("nodeExecutable") var nodeExecutable: String = "/usr/local/bin/node"
    @AppStorage("npmExecutable") var npmExecutable: String = "/usr/local/bin/npm"
    
    // MARK: - Private Properties
    private init() {
        setupDefaults()
    }
    
    // MARK: - Public Methods
    func resetToDefaults() {
        serverPort = 3001
        autoStartServer = false
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
        serverCommand = "npm start"
        serverDirectory = ""
        nodeExecutable = "/usr/local/bin/node"
        npmExecutable = "/usr/local/bin/npm"
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
        
        // Import each setting with validation
        if let port = settings["serverPort"] as? Int, port >= 1024, port <= 65535 {
            serverPort = port
        }
        
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
        
        if let level = settings["logLevel"] as? String {
            logLevel = level
        }
        
        if let maxLogs = settings["maxLogEntries"] as? Int, maxLogs > 0 {
            maxLogEntries = maxLogs
        }
        
        if let bonjour = settings["enableBonjour"] as? Bool {
            enableBonjour = bonjour
        }
        
        if let themeValue = settings["theme"] as? String {
            theme = themeValue
        }
        
        if let auth = settings["requireAuthentication"] as? Bool {
            requireAuthentication = auth
        }
        
        if let touchID = settings["enableTouchID"] as? Bool {
            enableTouchID = touchID
        }
        
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
    
    // MARK: - Private Methods
    private func setupDefaults() {
        // Set default server directory if not set
        if serverDirectory.isEmpty {
            serverDirectory = "/Users/michaelfuscoletti/Desktop/claude-companion/server"
        }
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