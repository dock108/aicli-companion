import SwiftUI
import AICLICompanion

@main
@available(iOS 17.0, macOS 14.0, *)
struct AppMain: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AICLICompanion.AppDelegate.self) var appDelegate
    #endif
    
    @StateObject private var aicliService = AICLICompanion.AICLIService()
    @StateObject private var settingsManager = AICLICompanion.SettingsManager()
    @StateObject private var pushNotificationService = AICLICompanion.PushNotificationService.shared
    
    init() {
        // Request enhanced push notification authorization on app launch
        Task {
            do {
                _ = try await AICLICompanion.EnhancedPushNotificationService.shared.requestAuthorizationWithOptions()
            } catch {
                print("Failed to request notification authorization: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            AICLICompanion.AdaptiveContentView()
                .environmentObject(aicliService)
                .environmentObject(settingsManager)
                .environmentObject(pushNotificationService)
        }
    }
}