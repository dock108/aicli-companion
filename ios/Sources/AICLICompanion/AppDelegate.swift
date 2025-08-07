#if os(iOS)
import UIKit
import UserNotifications

@available(iOS 17.0, *)
public class AppDelegate: NSObject, UIApplicationDelegate {
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // App launch setup
        
        // Initialize BackgroundSessionCoordinator early to capture session IDs
        _ = BackgroundSessionCoordinator.shared
        print("🎯 BackgroundSessionCoordinator initialized and listening for session IDs")
        
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
        
        // Clean up old pending messages in BackgroundSessionCoordinator
        BackgroundSessionCoordinator.shared.cleanupOldPendingMessages()
        
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
        
        // Notify HTTPAICLIService about the device token
        // The service will register with the server when it connects
        NotificationCenter.default.post(
            name: Notification.Name("DeviceTokenReceived"),
            object: token
        )
    }
    
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📨 Received remote notification: \(userInfo)")
        
        // Parse notification payload
        guard let projectId = userInfo["projectId"] as? String,
              let projectName = userInfo["projectName"] as? String else {
            print("⚠️ Push notification missing required project information")
            completionHandler(.noData)
            return
        }
        
        let sessionId = userInfo["sessionId"] as? String
        let notificationTitle = userInfo["title"] as? String ?? "New Message"
        let notificationBody = userInfo["body"] as? String ?? "You have a new message in \(projectName)"
        
        // Start background task to prevent app termination during sync
        let taskId = application.beginBackgroundTask(withName: "BackgroundMessageSync") {
            print("⏰ Background task expired during message sync")
            completionHandler(.failed)
        }
        
        // Perform background message sync
        Task {
            var syncSuccess = false
            
            if let sessionId = sessionId {
                print("🔄 Starting background message sync for session: \(sessionId)")
                syncSuccess = await BackgroundMessageSyncService.shared.syncMessagesForSession(
                    sessionId,
                    projectId: projectId,
                    projectName: projectName
                )
            }
            
            // Schedule local notification after sync attempt
            EnhancedPushNotificationService.shared.scheduleProjectNotification(
                title: notificationTitle,
                body: notificationBody,
                projectId: projectId,
                projectName: projectName,
                sessionId: sessionId
            )
            
            // Complete background task
            application.endBackgroundTask(taskId)
            
            // Report result
            if syncSuccess {
                print("✅ Background message sync completed successfully")
                completionHandler(.newData)
            } else if sessionId == nil {
                print("ℹ️ No session ID in notification, skipping sync")
                completionHandler(.noData)
            } else {
                print("❌ Background message sync failed")
                completionHandler(.failed)
            }
        }
    }
}
#endif
