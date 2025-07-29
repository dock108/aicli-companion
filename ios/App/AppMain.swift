import SwiftUI
import AICLICompanion

@main
@available(iOS 17.0, macOS 14.0, *)
struct AppMain: App {
    @StateObject private var aicliService = AICLICompanion.AICLIService()
    @StateObject private var settingsManager = AICLICompanion.SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            AICLICompanion.AdaptiveContentView()
                .environmentObject(aicliService)
                .environmentObject(settingsManager)
        }
    }
}