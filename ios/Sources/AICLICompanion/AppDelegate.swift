#if os(iOS)
import Foundation
import UIKit
import UserNotifications

@available(iOS 17.0, *)
public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // App launch setup
        
        // Local-first pattern: No background session coordination needed
        print("🎯 AppDelegate initialized with local-first message storage")
        
        // Perform session cleanup on app launch
        performSessionCleanup()
        
        // Migrate legacy session data if needed
        SessionStatePersistenceService.shared.migrateFromLegacyStorage()
        
        // Start performance monitoring session
        PerformanceMonitor.shared.startSession()
        
        // Setup enhanced push notifications
        PushNotificationService.shared.setupNotificationCategories()
        
        return true
    }
    
    private func performSessionCleanup() {
        print("🚀 App launched - performing session cleanup")
        
        // Clean up expired sessions
        SessionStatePersistenceService.shared.cleanupExpiredSessions()
        
        // Clean up stale session deduplication entries
        SessionDeduplicationManager.shared.cleanupExpiredSessions()
        
        // Local-first pattern: Message persistence handled by MessagePersistenceService
        // No pending message cleanup needed
        
        // Log active sessions
        let activeSessions = SessionStatePersistenceService.shared.getActiveSessions()
        print("📊 Active sessions: \(activeSessions.count)")
        
        for session in activeSessions {
            print("  - \(session.projectName): expires \(session.formattedExpiry)")
        }
    }
    
    // MARK: - Remote Notifications
    
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to string
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        print("📱 Device Token: \(token)")
        
        // Save token for later use
        UserDefaults.standard.set(token, forKey: "devicePushToken")
        
        // Notify AICLIService about the device token
        // The service will register with the server when it connects
        NotificationCenter.default.post(
            name: Notification.Name("DeviceTokenReceived"),
            object: token
        )
    }
    
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📨 === BACKGROUND NOTIFICATION RECEIVED ===")
        
        // Simplified: All APNS notifications handled by PushNotificationService.willPresent
        // This method only called when app is not in foreground
        // Just acknowledge and let willPresent handle the logic
        
        print("📨 Background notification received - trusting APNS delivery")
        completionHandler(.noData)
    }
}
#endif
