import SwiftUI
import ClaudeCompanion

@main
@available(iOS 16.0, macOS 13.0, *)
struct AppMain: App {
    @StateObject private var claudeService = ClaudeCompanion.ClaudeCodeService()
    @StateObject private var settingsManager = ClaudeCompanion.SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ClaudeCompanion.ContentView()
                .environmentObject(claudeService)
                .environmentObject(settingsManager)
        }
    }
}