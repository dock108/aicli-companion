import UIKit

@available(iOS 17.0, iPadOS 17.0, *)
public class AppDelegate: NSObject, UIApplicationDelegate {
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // App launch setup
        return true
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
        
        // Handle the notification
        if let sessionId = userInfo["sessionId"] as? String {
            // Post notification to open the session
            NotificationCenter.default.post(
                name: .openChatSession,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
        }
        
        completionHandler(.newData)
    }
}