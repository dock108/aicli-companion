import SwiftUI
import AICLICompanion

@main
@available(iOS 17.0, macOS 14.0, *)
struct AppMain: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AICLICompanion.AppDelegate.self) var appDelegate
    #endif
    
    @StateObject private var aicliService = AICLICompanion.AICLIService.shared
    @StateObject private var settingsManager = AICLICompanion.SettingsManager()
    @StateObject private var pushNotificationService = AICLICompanion.PushNotificationService.shared
    
    init() {
        // Request enhanced push notification authorization on app launch
        Task {
            do {
                _ = try await AICLICompanion.PushNotificationService.shared.requestAuthorizationWithOptions()
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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Clear badge count when app becomes active
                    #if os(iOS)
                    UIApplication.shared.applicationIconBadgeNumber = 0
                    #endif
                    // Also reset the notification service's badge tracking
                    AICLICompanion.PushNotificationService.shared.resetBadgeCount()
                    print("📱 App became active - cleared badge count")
                    
                    // Process any pending notifications that arrived while app was terminated
                    // This catches messages that weren't delivered via background fetch
                    Task {
                        await AICLICompanion.PushNotificationService.shared.processPendingNotifications()
                    }
                }
        }
    }
}