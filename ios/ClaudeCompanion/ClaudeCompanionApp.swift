import SwiftUI

@main
struct ClaudeCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClaudeCodeService())
                .environmentObject(SettingsManager())
        }
    }
}