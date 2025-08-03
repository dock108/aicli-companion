import UIKit
import UserNotifications

@available(iOS 17.0, *)
public class AppDelegate: NSObject, UIApplicationDelegate {
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // App launch setup
        
        // Perform session cleanup on app launch
        performSessionCleanup()
        
        // Migrate legacy session data if needed
        SessionStatePersistenceService.shared.migrateFromLegacyStorage()
        
        // Start performance monitoring session
        PerformanceMonitor.shared.startSession()
        
        // Setup enhanced push notifications
        EnhancedPushNotificationService.shared.setupNotificationCategories()
        
        return true
    }
    
    private func performSessionCleanup() {
        print("🚀 App launched - performing session cleanup")
        
        // Clean up expired sessions
        SessionStatePersistenceService.shared.cleanupExpiredSessions()
        
        // Clean up stale session deduplication entries
        SessionDeduplicationManager.shared.cleanupExpiredSessions()
        
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
        
        // Send token to WebSocket service if connected
        if WebSocketService.shared.isConnected {
            WebSocketService.shared.sendDeviceToken(token)
        }
    }
    
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📨 Received remote notification: \(userInfo)")
        
        // Parse notification payload
        if let projectId = userInfo["projectId"] as? String,
           let projectName = userInfo["projectName"] as? String {
            
            // Schedule enhanced notification
            EnhancedPushNotificationService.shared.scheduleProjectNotification(
                title: userInfo["title"] as? String ?? "New Message",
                body: userInfo["body"] as? String ?? "You have a new message in \(projectName)",
                projectId: projectId,
                projectName: projectName,
                sessionId: userInfo["sessionId"] as? String
            )
        }
        
        completionHandler(.newData)
    }
}