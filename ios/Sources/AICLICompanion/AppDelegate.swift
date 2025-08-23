#if os(iOS)
import Foundation
import UIKit
import UserNotifications

@available(iOS 17.0, *)
public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🚀 AppDelegate.didFinishLaunching started")
        
        // Local-first pattern: No background session coordination needed
        print("🎯 AppDelegate initialized with local-first message storage")
        
        // Check if app was launched from a notification while terminated
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            print("🚀 App launched from notification while terminated")
        }
        
        // Setup lightweight components first
        PushNotificationService.shared.setupNotificationCategories()
        print("📱 Registered notification categories with actions")
        
        // Start performance monitoring (lightweight)
        PerformanceMonitor.shared.startSession()
        print("📊 Performance monitoring started")
        
        // Do heavy operations asynchronously after app is ready
        Task {
            print("🔄 Starting async initialization tasks...")
            
            // Request push notification authorization
            do {
                _ = try await PushNotificationService.shared.requestAuthorizationWithOptions()
                print("✅ Push notification authorization requested")
            } catch {
                print("❌ Failed to request notification authorization: \(error)")
            }
            
            // Process pending notifications (can be slow)
            await PushNotificationService.shared.processPendingNotifications()
            
            // Perform session cleanup
            await performSessionCleanupAsync()
            
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ App initialization completed in \(String(format: "%.2f", totalTime))s")
        }
        
        let syncTime = CFAbsoluteTimeGetCurrent() - startTime
        print("🚀 AppDelegate.didFinishLaunching completed synchronously in \(String(format: "%.3f", syncTime))s")
        
        return true
    }
    
    private func performSessionCleanupAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                print("🚀 App launched - performing cleanup")
                
                // Sessions are no longer tracked in iOS app
                // All session management is handled by the server
                
                // Local-first pattern: Message persistence handled by MessagePersistenceService
                // No cleanup needed as messages are stored per project
                
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
        print("📨 UserInfo keys: \(Array(userInfo.keys))")
        
        // Process APNS message through unified pipeline when app is backgrounded
        Task {
            // Check if this is a Claude message that needs processing
            let isClaudeMessage = userInfo["sessionId"] != nil ||
                                 userInfo["message"] != nil ||
                                 userInfo["requiresFetch"] != nil ||
                                 userInfo["messageId"] != nil ||
                                 userInfo["projectPath"] != nil
            
            if isClaudeMessage {
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
