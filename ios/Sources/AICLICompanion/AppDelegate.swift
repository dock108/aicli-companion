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
        
        // Perform async initialization tasks in background
        Task {
            // Perform session cleanup on app launch
            await performSessionCleanupAsync()
        }
        
        // Start performance monitoring session (lightweight, can stay synchronous)
        PerformanceMonitor.shared.startSession()
        
        // Setup enhanced push notifications
        PushNotificationService.shared.setupNotificationCategories()
        
        return true
    }
    
    private func performSessionCleanupAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
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
                
                continuation.resume()
            }
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
        print("📨 UserInfo: \(userInfo)")
        
        // Process APNS message through unified pipeline when app is backgrounded
        Task {
            // Check if this is a Claude message that needs processing
            if userInfo["sessionId"] != nil || userInfo["message"] != nil || userInfo["requiresFetch"] != nil {
                print("📨 Processing Claude message in background...")
                
                // Process through PushNotificationService unified pipeline
                // This will save to local storage and post notification to UI
                await PushNotificationService.shared.processAPNSMessage(userInfo: userInfo)
                
                // Indicate new data was fetched
                await MainActor.run {
                    completionHandler(.newData)
                }
            } else {
                print("📨 Non-Claude notification in background")
                await MainActor.run {
                    completionHandler(.noData)
                }
            }
        }
    }
}
#endif
