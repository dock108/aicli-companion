import SwiftUI

// This is now in the App target's AppMain.swift
// Keeping this file for reference only
struct ClaudeCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClaudeCodeService())
                .environmentObject(SettingsManager())
        }
    }
}
