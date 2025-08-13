//
//  MenuBarViewModel.swift
//  AICLICompanionHost
//
//  ViewModel for Menu Bar functionality
//

import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - UI State Types
enum ServerUIStatus {
    case running
    case stopped
    case starting
    case stopping
}

@MainActor
class MenuBarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var connectionString: String = ""
    @Published var serverStatus: ServerUIStatus = .stopped
    @Published var serverHealth: ServerHealth = .unknown
    @Published var quickActions: [QuickAction] = []
    @Published var isProcessing: Bool = false
    @Published var sessionCount: Int = 0
    @Published var publicURL: String?
    @Published var localURL: String = ""
    @Published var showingQRCode: Bool = false
    @Published var recentLogs: [LogEntry] = []
    
    // MARK: - Properties
    private let serverManager = ServerManager.shared
    private let settingsManager = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var statusIcon: String {
        switch serverStatus {
        case .running:
            return serverHealth == .healthy ? "circle.fill" : "exclamationmark.circle.fill"
        case .starting:
            return "circle.dotted"
        case .stopping:
            return "circle.dotted"
        case .stopped:
            return "circle"
        }
    }
    
    var statusColor: Color {
        switch serverStatus {
        case .running:
            return serverHealth == .healthy ? .green : .orange
        case .starting, .stopping:
            return .yellow
        case .stopped:
            return .gray
        }
    }
    
    var statusText: String {
        switch serverStatus {
        case .running:
            return serverHealth == .healthy ? "Server Running" : "Server Running (Issues)"
        case .starting:
            return "Starting Server..."
        case .stopping:
            return "Stopping Server..."
        case .stopped:
            return "Server Stopped"
        }
    }
    
    var canToggleServer: Bool {
        !isProcessing
    }
    
    var toggleServerTitle: String {
        switch serverStatus {
        case .running:
            return "Stop Server"
        case .stopped:
            return "Start Server"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        }
    }
    
    var hasConnection: Bool {
        !connectionString.isEmpty && serverStatus == .running
    }
    
    // MARK: - Initialization
    init() {
        setupBindings()
        setupQuickActions()
        updateStatus()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Bind to server manager state
        serverManager.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.serverStatus = isRunning ? .running : .stopped
                self?.updateConnectionString()
            }
            .store(in: &cancellables)
        
        serverManager.$isProcessing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isProcessing)
        
        serverManager.$serverHealth
            .receive(on: DispatchQueue.main)
            .assign(to: &$serverHealth)
        
        // connectionString is computed, not @Published - calculate from other properties
        updateConnectionString()
        
        serverManager.$publicURL
            .receive(on: DispatchQueue.main)
            .assign(to: &$publicURL)
        
        serverManager.$activeSessions
            .receive(on: DispatchQueue.main)
            .map { $0.count }
            .assign(to: &$sessionCount)
        
        // Get recent logs
        serverManager.$logs
            .receive(on: DispatchQueue.main)
            .map { Array($0.suffix(5)) }
            .assign(to: &$recentLogs)
    }
    
    private func setupQuickActions() {
        quickActions = [
            QuickAction(
                id: "toggle",
                title: "Toggle Server",
                icon: "power",
                action: { [weak self] in
                    Task {
                        await self?.toggleServer()
                    }
                }
            ),
            QuickAction(
                id: "copy",
                title: "Copy Connection",
                icon: "doc.on.doc",
                isEnabled: { [weak self] in
                    self?.hasConnection ?? false
                },
                action: { [weak self] in
                    self?.copyConnectionString()
                }
            ),
            QuickAction(
                id: "qr",
                title: "Show QR Code",
                icon: "qrcode",
                isEnabled: { [weak self] in
                    self?.hasConnection ?? false
                },
                action: { [weak self] in
                    self?.showQRCode()
                }
            ),
            QuickAction(
                id: "activity",
                title: "Activity Monitor",
                icon: "chart.line.uptrend.xyaxis",
                action: { [weak self] in
                    self?.openActivityMonitor()
                }
            ),
            QuickAction(
                id: "settings",
                title: "Settings",
                icon: "gear",
                action: { [weak self] in
                    self?.openSettings()
                }
            ),
            QuickAction(
                id: "logs",
                title: "View Logs",
                icon: "doc.text",
                action: { [weak self] in
                    self?.openLogs()
                }
            )
        ]
    }
    
    // MARK: - Public Methods
    func toggleServer() async {
        guard canToggleServer else { return }
        
        if serverManager.isRunning {
            serverStatus = .stopping
            await serverManager.stopServer()
            serverStatus = .stopped
        } else {
            serverStatus = .starting
            do {
                try await serverManager.startServer()
                serverStatus = .running
            } catch {
                serverStatus = .stopped
                // Handle error - could show alert
                print("Failed to start server: \(error)")
            }
        }
    }
    
    func copyConnectionString() {
        guard !connectionString.isEmpty else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connectionString, forType: .string)
        
        // Could show notification
        if settingsManager.enableNotifications {
            NotificationManager.shared.showNotification(
                title: "Connection Copied",
                body: "Connection string copied to clipboard"
            )
        }
    }
    
    func showQRCode() {
        showingQRCode = true
    }
    
    func openSettings() {
        // Check if running in test environment
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            if let url = URL(string: "aiclicompanion://settings") {
                NSWorkspace.shared.open(url)
            }
        }
        
        // Alternative: Open settings window
        // NSApp.sendAction(#selector(AppDelegate.showSettings), to: nil, from: nil)
        print("Open settings")
    }
    
    func openActivityMonitor() {
        // Check if running in test environment
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            if let url = URL(string: "aiclicompanion://activity") {
                NSWorkspace.shared.open(url)
            }
        }
        
        // Alternative: Open activity window
        // NSApp.sendAction(#selector(AppDelegate.showActivityMonitor), to: nil, from: nil)
        print("Open activity monitor")
    }
    
    func openLogs() {
        // Check if running in test environment
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            if let url = URL(string: "aiclicompanion://logs") {
                NSWorkspace.shared.open(url)
            }
        }
        
        // Alternative: Open logs window
        // NSApp.sendAction(#selector(AppDelegate.showLogs), to: nil, from: nil)
        print("Open logs")
    }
    
    func restartServer() async {
        guard serverStatus == .running else { return }
        
        serverStatus = .stopping
        await serverManager.stopServer()
        
        serverStatus = .starting
        do {
            try await serverManager.startServer()
            serverStatus = .running
        } catch {
            serverStatus = .stopped
            print("Failed to restart server: \(error)")
        }
    }
    
    func refreshStatus() {
        Task {
            await serverManager.refreshStatus()
        }
    }
    
    func quitApp() {
        Task {
            if serverManager.isRunning {
                await serverManager.stopServer()
            }
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - Private Methods
    private func updateStatus() {
        serverStatus = serverManager.isRunning ? .running : .stopped
        updateConnectionString()
    }
    
    private func updateConnectionString() {
        if serverManager.isRunning {
            connectionString = serverManager.connectionString
            localURL = "http://\(serverManager.localIP):\(serverManager.port)"
        } else {
            connectionString = ""
            localURL = ""
        }
    }
}

// MARK: - Supporting Types
// ServerStatus is already defined in ServerTypes.swift

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let icon: String
    var isEnabled: () -> Bool = { true }
    let action: () -> Void
}