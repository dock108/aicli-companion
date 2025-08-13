//
//  SettingsViewModel.swift
//  AICLICompanionHost
//
//  ViewModel for Settings functionality
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var serverPort: Int
    @Published var autoStartServer: Bool
    @Published var autoRestartOnCrash: Bool
    @Published var launchAtLogin: Bool
    @Published var showDockIcon: Bool
    @Published var enableNotifications: Bool
    @Published var enableSounds: Bool
    @Published var logLevel: String
    @Published var maxLogEntries: Int
    @Published var enableBonjour: Bool
    @Published var theme: String
    @Published var requireAuthentication: Bool
    @Published var enableTouchID: Bool
    @Published var enableTunnel: Bool
    @Published var tunnelProvider: String
    @Published var ngrokAuthToken: String
    @Published var defaultProjectDirectory: String
    @Published var serverCommand: String
    @Published var nodeExecutable: String
    @Published var npmExecutable: String
    
    @Published var needsRestart: Bool = false
    @Published var hasUnsavedChanges: Bool = false
    @Published var isValidating: Bool = false
    @Published var validationErrors: [String] = []
    
    // MARK: - Properties
    private let settingsManager = SettingsManager.shared
    private let serverManager = ServerManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var originalSettings: SettingsSnapshot?
    
    // MARK: - Computed Properties
    var canSave: Bool {
        hasUnsavedChanges && validationErrors.isEmpty
    }
    
    var isServerRunning: Bool {
        serverManager.isRunning
    }
    
    var restartMessage: String {
        if needsRestart && isServerRunning {
            return "Server restart required for changes to take effect"
        }
        return ""
    }
    
    // MARK: - Initialization
    init() {
        // Initialize from SettingsManager
        self.serverPort = settingsManager.serverPort
        self.autoStartServer = settingsManager.autoStartServer
        self.autoRestartOnCrash = settingsManager.autoRestartOnCrash
        self.launchAtLogin = settingsManager.launchAtLogin
        self.showDockIcon = settingsManager.showDockIcon
        self.enableNotifications = settingsManager.enableNotifications
        self.enableSounds = settingsManager.enableSounds
        self.logLevel = settingsManager.logLevel
        self.maxLogEntries = settingsManager.maxLogEntries
        self.enableBonjour = settingsManager.enableBonjour
        self.theme = settingsManager.theme
        self.requireAuthentication = settingsManager.requireAuthentication
        self.enableTouchID = settingsManager.enableTouchID
        self.enableTunnel = settingsManager.enableTunnel
        self.tunnelProvider = settingsManager.tunnelProvider
        self.ngrokAuthToken = settingsManager.ngrokAuthToken
        self.defaultProjectDirectory = settingsManager.defaultProjectDirectory
        self.serverCommand = settingsManager.serverCommand
        self.nodeExecutable = settingsManager.nodeExecutable
        self.npmExecutable = settingsManager.npmExecutable
        
        captureOriginalSettings()
        setupBindings()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Watch for changes
        $serverPort
            .combineLatest($autoStartServer, $requireAuthentication, $enableTunnel)
            .sink { [weak self] _ in
                self?.checkForChanges()
                self?.validateSettings()
            }
            .store(in: &cancellables)
        
        // Monitor server-critical settings for restart requirement
        $serverPort
            .combineLatest($requireAuthentication, $enableTunnel, $tunnelProvider)
            .sink { [weak self] _ in
                self?.checkNeedsRestart()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func applySettings() async throws {
        guard canSave else {
            throw NSError(domain: "SettingsViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Settings validation failed"])
        }
        
        // Apply settings to SettingsManager
        settingsManager.serverPort = serverPort
        settingsManager.autoStartServer = autoStartServer
        settingsManager.autoRestartOnCrash = autoRestartOnCrash
        settingsManager.launchAtLogin = launchAtLogin
        settingsManager.showDockIcon = showDockIcon
        settingsManager.enableNotifications = enableNotifications
        settingsManager.enableSounds = enableSounds
        settingsManager.logLevel = logLevel
        settingsManager.maxLogEntries = maxLogEntries
        settingsManager.enableBonjour = enableBonjour
        settingsManager.theme = theme
        settingsManager.requireAuthentication = requireAuthentication
        settingsManager.enableTouchID = enableTouchID
        settingsManager.enableTunnel = enableTunnel
        settingsManager.tunnelProvider = tunnelProvider
        settingsManager.ngrokAuthToken = ngrokAuthToken
        settingsManager.defaultProjectDirectory = defaultProjectDirectory
        settingsManager.serverCommand = serverCommand
        settingsManager.nodeExecutable = nodeExecutable
        settingsManager.npmExecutable = npmExecutable
        
        // Mark configuration as applied
        settingsManager.markConfigurationApplied()
        
        // Update tracking
        captureOriginalSettings()
        hasUnsavedChanges = false
        
        // Restart server if needed
        if needsRestart && isServerRunning {
            await restartServer()
        }
    }
    
    func resetToDefaults() {
        settingsManager.resetToDefaults()
        
        // Update view model properties
        serverPort = settingsManager.serverPort
        autoStartServer = settingsManager.autoStartServer
        autoRestartOnCrash = settingsManager.autoRestartOnCrash
        launchAtLogin = settingsManager.launchAtLogin
        showDockIcon = settingsManager.showDockIcon
        enableNotifications = settingsManager.enableNotifications
        enableSounds = settingsManager.enableSounds
        logLevel = settingsManager.logLevel
        maxLogEntries = settingsManager.maxLogEntries
        enableBonjour = settingsManager.enableBonjour
        theme = settingsManager.theme
        requireAuthentication = settingsManager.requireAuthentication
        enableTouchID = settingsManager.enableTouchID
        enableTunnel = settingsManager.enableTunnel
        tunnelProvider = settingsManager.tunnelProvider
        ngrokAuthToken = settingsManager.ngrokAuthToken
        defaultProjectDirectory = settingsManager.defaultProjectDirectory
        serverCommand = settingsManager.serverCommand
        nodeExecutable = ""
        npmExecutable = ""
        
        captureOriginalSettings()
        hasUnsavedChanges = false
        validationErrors.removeAll()
    }
    
    func revertChanges() {
        guard let original = originalSettings else { return }
        
        serverPort = original.serverPort
        autoStartServer = original.autoStartServer
        autoRestartOnCrash = original.autoRestartOnCrash
        launchAtLogin = original.launchAtLogin
        showDockIcon = original.showDockIcon
        enableNotifications = original.enableNotifications
        enableSounds = original.enableSounds
        logLevel = original.logLevel
        maxLogEntries = original.maxLogEntries
        enableBonjour = original.enableBonjour
        theme = original.theme
        requireAuthentication = original.requireAuthentication
        enableTouchID = original.enableTouchID
        enableTunnel = original.enableTunnel
        tunnelProvider = original.tunnelProvider
        ngrokAuthToken = original.ngrokAuthToken
        defaultProjectDirectory = original.defaultProjectDirectory
        serverCommand = original.serverCommand
        nodeExecutable = original.nodeExecutable
        npmExecutable = original.npmExecutable
        
        hasUnsavedChanges = false
        validationErrors.removeAll()
    }
    
    func exportSettings() -> Data? {
        return settingsManager.exportSettings()
    }
    
    func importSettings(from data: Data) throws {
        try settingsManager.importSettings(from: data)
        
        // Update view model
        serverPort = settingsManager.serverPort
        autoStartServer = settingsManager.autoStartServer
        // ... update all properties
        
        captureOriginalSettings()
        hasUnsavedChanges = false
    }
    
    func validateNgrokToken() async -> Bool {
        guard !ngrokAuthToken.isEmpty else { return true }
        
        isValidating = true
        defer { isValidating = false }
        
        // Basic validation - token should be alphanumeric with some special chars
        let tokenRegex = "^[a-zA-Z0-9_-]{20,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", tokenRegex)
        
        return predicate.evaluate(with: ngrokAuthToken)
    }
    
    // MARK: - Private Methods
    private func captureOriginalSettings() {
        originalSettings = SettingsSnapshot(
            serverPort: serverPort,
            autoStartServer: autoStartServer,
            autoRestartOnCrash: autoRestartOnCrash,
            launchAtLogin: launchAtLogin,
            showDockIcon: showDockIcon,
            enableNotifications: enableNotifications,
            enableSounds: enableSounds,
            logLevel: logLevel,
            maxLogEntries: maxLogEntries,
            enableBonjour: enableBonjour,
            theme: theme,
            requireAuthentication: requireAuthentication,
            enableTouchID: enableTouchID,
            enableTunnel: enableTunnel,
            tunnelProvider: tunnelProvider,
            ngrokAuthToken: ngrokAuthToken,
            defaultProjectDirectory: defaultProjectDirectory,
            serverCommand: serverCommand,
            nodeExecutable: nodeExecutable,
            npmExecutable: npmExecutable
        )
    }
    
    private func checkForChanges() {
        guard let original = originalSettings else {
            hasUnsavedChanges = false
            return
        }
        
        hasUnsavedChanges = 
            serverPort != original.serverPort ||
            autoStartServer != original.autoStartServer ||
            autoRestartOnCrash != original.autoRestartOnCrash ||
            launchAtLogin != original.launchAtLogin ||
            showDockIcon != original.showDockIcon ||
            enableNotifications != original.enableNotifications ||
            enableSounds != original.enableSounds ||
            logLevel != original.logLevel ||
            maxLogEntries != original.maxLogEntries ||
            enableBonjour != original.enableBonjour ||
            theme != original.theme ||
            requireAuthentication != original.requireAuthentication ||
            enableTouchID != original.enableTouchID ||
            enableTunnel != original.enableTunnel ||
            tunnelProvider != original.tunnelProvider ||
            ngrokAuthToken != original.ngrokAuthToken ||
            defaultProjectDirectory != original.defaultProjectDirectory ||
            serverCommand != original.serverCommand ||
            nodeExecutable != original.nodeExecutable ||
            npmExecutable != original.npmExecutable
    }
    
    private func checkNeedsRestart() {
        guard let original = originalSettings else {
            needsRestart = false
            return
        }
        
        needsRestart = isServerRunning && (
            serverPort != original.serverPort ||
            requireAuthentication != original.requireAuthentication ||
            enableTunnel != original.enableTunnel ||
            tunnelProvider != original.tunnelProvider ||
            ngrokAuthToken != original.ngrokAuthToken
        )
    }
    
    private func validateSettings() {
        validationErrors.removeAll()
        
        // Validate port
        if serverPort < 1024 || serverPort > 65535 {
            validationErrors.append("Port must be between 1024 and 65535")
        }
        
        // Validate max log entries
        if maxLogEntries < 100 || maxLogEntries > 10000 {
            validationErrors.append("Max log entries must be between 100 and 10000")
        }
        
        // Validate ngrok token if tunnel enabled
        if enableTunnel && tunnelProvider == "ngrok" && ngrokAuthToken.isEmpty {
            validationErrors.append("Ngrok auth token is required when using ngrok tunnel")
        }
        
        // Validate project directory
        if !defaultProjectDirectory.isEmpty {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: defaultProjectDirectory) {
                validationErrors.append("Default project directory does not exist")
            }
        }
        
        // Validate server command
        if serverCommand.isEmpty {
            validationErrors.append("Server command cannot be empty")
        }
    }
    
    private func restartServer() async {
        do {
            try await serverManager.restartServerWithCurrentConfig()
            needsRestart = false
        } catch {
            print("Failed to restart server: \(error)")
        }
    }
}

// MARK: - Supporting Types
private struct SettingsSnapshot {
    let serverPort: Int
    let autoStartServer: Bool
    let autoRestartOnCrash: Bool
    let launchAtLogin: Bool
    let showDockIcon: Bool
    let enableNotifications: Bool
    let enableSounds: Bool
    let logLevel: String
    let maxLogEntries: Int
    let enableBonjour: Bool
    let theme: String
    let requireAuthentication: Bool
    let enableTouchID: Bool
    let enableTunnel: Bool
    let tunnelProvider: String
    let ngrokAuthToken: String
    let defaultProjectDirectory: String
    let serverCommand: String
    let nodeExecutable: String
    let npmExecutable: String
}

// SettingsError is already defined in SettingsManager.swift