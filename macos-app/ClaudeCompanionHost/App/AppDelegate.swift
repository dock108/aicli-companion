//
//  AppDelegate.swift
//  ClaudeCompanionHost
//
//  Handles app lifecycle and system integration
//

import Cocoa
import SwiftUI
import UserNotifications
import Combine
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, AppCommands {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy based on user preference
        updateDockIconVisibility()

        // Request notification permissions
        requestNotificationPermissions()

        // Register for launch at login if enabled
        Task { @MainActor in
            registerLaunchAtLogin()
        }

        // Start monitoring network changes
        NetworkMonitor.shared.startMonitoring()

        // Check if server should auto-start (with delay to ensure settings are loaded)
        if SettingsManager.shared.autoStartServer {
            Task {
                // Add delay to ensure all managers are fully initialized
                try await Task.sleep(for: .milliseconds(1000))
                
                print("🚀 Auto-starting server with current settings...")
                print("   - Auth required: \(SettingsManager.shared.requireAuthentication)")
                print("   - Tunnel enabled: \(SettingsManager.shared.enableTunnel)")
                print("   - Tunnel provider: \(SettingsManager.shared.tunnelProvider)")
                print("   - Token configured: \(!SettingsManager.shared.ngrokAuthToken.isEmpty)")
                
                do {
                    try await ServerManager.shared.startServer()
                    print("✅ Auto-start successful")
                } catch {
                    print("❌ Auto-start failed: \(error)")
                    // Don't fail silently - user should know auto-start failed
                    await MainActor.run {
                        ServerManager.shared.addLog(.error, "Auto-start failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            print("ℹ️ Auto-start disabled - server can be started manually")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown
        Task {
            await ServerManager.shared.stopServer()
        }

        // Stop network monitoring
        NetworkMonitor.shared.stopMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when all windows are closed
        return false
    }

    // MARK: - Private Methods

    private func updateDockIconVisibility() {
        let showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permissions granted")
                } else {
                    print("⚠️ Notifications not authorized - some features may be limited")
                    if let error = error {
                        print("❌ Notification permission error: \(error)")
                    }
                    // Don't show this error to user as it's not critical for app function
                }
            }
        }
    }

    @MainActor
    private func registerLaunchAtLogin() {
        if SettingsManager.shared.launchAtLogin {
            // Use SMAppService for modern launch at login
            do {
                if #available(macOS 13.0, *) {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("❌ Failed to register launch at login: \(error)")
            }
        }
    }

    @objc func openActivityMonitor() {
        // Open the activity monitor window
        if let window = NSApp.windows.first(where: { $0.title == "Activity Monitor" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Create new window if needed
            let windowController = NSWindowController()
            windowController.showWindow(nil)
        }
    }

    @objc func openLogs() {
        // Open the logs window by creating a new window
        if let window = NSApp.windows.first(where: { $0.title == "Activity Monitor" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Create a new window for logs
            let logsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            logsWindow.title = "Activity Monitor"
            logsWindow.center()
            logsWindow.contentView = NSHostingView(rootView: LogsView().environmentObject(ServerManager.shared))
            logsWindow.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showQRCode() {
        // Open the QR code window
        if let window = NSApp.windows.first(where: { $0.title == "QR Code" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let serverDidStart = Notification.Name("serverDidStart")
    static let serverDidStop = Notification.Name("serverDidStop")
    static let serverDidError = Notification.Name("serverDidError")
    static let sessionDidConnect = Notification.Name("sessionDidConnect")
    static let sessionDidDisconnect = Notification.Name("sessionDidDisconnect")
}
