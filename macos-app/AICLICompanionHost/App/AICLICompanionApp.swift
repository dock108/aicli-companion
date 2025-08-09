//
//  AICLICompanionApp.swift
//  AICLICompanionHost
//
//  The main app entry point for AICLI Companion Host
//

import SwiftUI
import ServiceManagement

@main
struct AICLICompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverManager = ServerManager.shared
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @AppStorage("showDockIcon") private var showDockIcon = false

    var body: some Scene {
        // Settings window
        Settings {
            SettingsView()
                .environmentObject(serverManager)
                .environmentObject(settingsManager)
                .environmentObject(networkMonitor)
        }

        // Activity Monitor window
        WindowGroup("Activity Monitor", id: "activity-monitor") {
            ActivityMonitorView()
                .environmentObject(serverManager)
                .environmentObject(settingsManager)
        }
        .windowResizability(.contentSize)

        // QR Code window
        WindowGroup("QR Code", id: "qr-code") {
            if !serverManager.connectionString.isEmpty {
                QRCodeView(connectionString: serverManager.connectionString)
            } else {
                ContentUnavailableView(
                    "Server Not Running",
                    systemImage: "server.rack",
                    description: Text("Start the server to generate a QR code")
                )
                .frame(width: 350, height: 200)
            }
        }
        .windowResizability(.contentSize)

        // Menu bar extra
        MenuBarExtra {
            MenuBarView()
                .environmentObject(serverManager)
                .environmentObject(settingsManager)
                .environmentObject(networkMonitor)
                .environmentObject(notificationManager)
        } label: {
            MenuBarIcon(isServerRunning: serverManager.isRunning)
        }
        .menuBarExtraStyle(.window)
    }
}
