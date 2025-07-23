import SwiftUI

// This is now in the App target's AppMain.swift
// This file is kept for the library target
@available(iOS 16.0, macOS 13.0, *)
public struct ClaudeCompanionApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClaudeCodeService())
                .environmentObject(SettingsManager())
        }
    }
}
