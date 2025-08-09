//
//  AppDelegate.swift
//  AICLICompanionHost
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

        // Request developer tools permissions for process management
        requestDeveloperToolsPermissions()

        // Register for launch at login if enabled
        Task { @MainActor in
            registerLaunchAtLogin()
        }

        // Start monitoring network changes
        NetworkMonitor.shared.startMonitoring()

        // Check if server should auto-start (with delay to ensure settings are loaded)
        Task {
            // Add delay to ensure all managers are fully initialized
            try await Task.sleep(for: .milliseconds(1500))

            await MainActor.run {
                let autoStartEnabled = SettingsManager.shared.autoStartServer
                ServerManager.shared.addLog(
                    .info,
                    "Checking auto-start setting: \(autoStartEnabled ? "enabled" : "disabled")"
                )

                if autoStartEnabled {
                    Task {
                        await self.performAutoStart()
                    }
                } else {
                    ServerManager.shared.addLog(.info, "Auto-start disabled - server can be started manually")
                    print("ℹ️ Auto-start disabled - server can be started manually")
                }
            }
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

    /// Perform auto-start with improved error handling and logging
    @MainActor
    private func performAutoStart() async {
        ServerManager.shared.addLog(.info, "🚀 Auto-starting server with current settings...")
        print("🚀 Auto-starting server with current settings...")

        // Log current configuration
        let settings = SettingsManager.shared
        ServerManager.shared.addLog(.debug, "Auto-start configuration:")
        ServerManager.shared.addLog(.debug, "   - Auth required: \(settings.requireAuthentication)")
        ServerManager.shared.addLog(.debug, "   - Tunnel enabled: \(settings.enableTunnel)")
        ServerManager.shared.addLog(.debug, "   - Tunnel provider: \(settings.tunnelProvider)")
        ServerManager.shared.addLog(.debug, "   - Token configured: \(!settings.ngrokAuthToken.isEmpty)")

        do {
            // Use regular startServer instead of restart to avoid unnecessary cleanup
            try await ServerManager.shared.startServer()
            ServerManager.shared.addLog(.info, "✅ Auto-start completed successfully")
            print("✅ Auto-start successful")

            // Show notification about successful auto-start
            NotificationManager.shared.showServerNotification(
                title: "AICLI Companion Started",
                body: "Server auto-started successfully on port \(ServerManager.shared.port)"
            )

        } catch {
            let errorMessage = "Auto-start failed: \(error.localizedDescription)"
            ServerManager.shared.addLog(.error, "❌ \(errorMessage)")
            print("❌ Auto-start failed: \(error)")

            // Show notification about failed auto-start
            NotificationManager.shared.showServerNotification(
                title: "Auto-start Failed",
                body: "Failed to start server automatically. Please check logs and start manually.",
                isError: true
            )
        }
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

    private func requestDeveloperToolsPermissions() {
        // Test if we can actually manage processes (more comprehensive test)
        let testTask = Process()
        testTask.executableURL = URL(fileURLWithPath: "/bin/sleep")
        testTask.arguments = ["0.1"] // Short sleep

        do {
            try testTask.run()
            let pid = testTask.processIdentifier

            // Try to get task info - this is what actually fails without Full Disk Access
            let result = kill(pid, 0) // Signal 0 tests if we can access the process
            testTask.waitUntilExit()

            if result == 0 {
                print("✅ Full process management permissions available (PID access works)")
                Task { @MainActor in
                    ServerManager.shared.addLog(
                        .info,
                        "Full Disk Access permissions verified - can access process PIDs"
                    )
                }
            } else {
                print("❌ Cannot access process PIDs - Full Disk Access required")
                Task { @MainActor in
                    ServerManager.shared.addLog(.error, "Missing Full Disk Access - cannot manage server processes")
                }
                showDeveloperToolsAlert()
            }
        } catch {
            print("❌ Process creation failed: \(error)")
            Task { @MainActor in
                ServerManager.shared.addLog(.error, "Process management test failed: \(error.localizedDescription)")
            }
            showDeveloperToolsAlert()
        }
    }

    private func showDeveloperToolsAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Full Disk Access Permission Required"
            alert.informativeText = """
            AICLI Companion needs Full Disk Access permission to manage server processes.

            This is required to start and stop the Node.js server process properly.

            Please go to:
            System Preferences → Security & Privacy → Privacy → Full Disk Access

            Then:
            1. Click the lock icon and enter your password
            2. Click the '+' button or drag the app to add "AICLI Companion"
            3. Restart the app after granting permission

            This permission allows the app to control server processes without freezing.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Preferences to Full Disk Access
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
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
        // Activate the app to bring it to foreground
        NSApp.activate(ignoringOtherApps: true)

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
        // Activate the app to bring it to foreground
        NSApp.activate(ignoringOtherApps: true)

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
        // Activate the app to bring it to foreground
        NSApp.activate(ignoringOtherApps: true)

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
