import SwiftUI
import ClaudeCompanion

@main
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