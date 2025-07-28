import SwiftUI
import ClaudeCompanion

@main
@available(iOS 17.0, macOS 14.0, *)
struct AppMain: App {
    @StateObject private var claudeService = ClaudeCompanion.ClaudeCodeService()
    @StateObject private var settingsManager = ClaudeCompanion.SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ClaudeCompanion.AdaptiveContentView()
                .environmentObject(claudeService)
                .environmentObject(settingsManager)
        }
    }
}