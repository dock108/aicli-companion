import SwiftUI
import AICLICompanion

@main
@available(iOS 17.0, macOS 14.0, *)
struct AppMain: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AICLICompanion.AppDelegate.self) var appDelegate
    #endif
    
    // Lazy initialization to avoid blocking app startup
    @StateObject private var aicliService: AICLICompanion.AICLIService = {
        let start = CFAbsoluteTimeGetCurrent()
        print("🔄 Initializing AICLIService...")
        let service = AICLICompanion.AICLIService.shared
        let time = CFAbsoluteTimeGetCurrent() - start
        print("✅ AICLIService initialized in \(String(format: "%.3f", time))s")
        return service
    }()
    
    @StateObject private var settingsManager: AICLICompanion.SettingsManager = {
        let start = CFAbsoluteTimeGetCurrent()
        print("🔄 Initializing SettingsManager...")
        let manager = AICLICompanion.SettingsManager()
        let time = CFAbsoluteTimeGetCurrent() - start
        print("✅ SettingsManager initialized in \(String(format: "%.3f", time))s")
        return manager
    }()
    
    @StateObject private var pushNotificationService: AICLICompanion.PushNotificationService = {
        let start = CFAbsoluteTimeGetCurrent()
        print("🔄 Initializing PushNotificationService...")
        let service = AICLICompanion.PushNotificationService.shared
        let time = CFAbsoluteTimeGetCurrent() - start
        print("✅ PushNotificationService initialized in \(String(format: "%.3f", time))s")
        return service
    }()
    
    init() {
        print("🚀 AppMain init started")
        // Heavy service initialization will happen lazily when first accessed
        print("🚀 AppMain init completed quickly")
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
                    
                    // Don't process pending notifications here - already handled in AppDelegate
                    // This prevents duplicate processing and improves performance
                }
        }
    }
}