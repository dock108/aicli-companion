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
        print("🔥 === APNS NOTIFICATION RECEIVED (didReceiveRemoteNotification) ===")
        print("📨 App state: \(application.applicationState.rawValue) (0=active, 1=inactive, 2=background)")
        
        // IMPORTANT: Skip processing if app is in foreground (active)
        // The willPresent delegate in EnhancedPushNotificationService handles foreground notifications
        if application.applicationState == .active {
            print("📱 App is active/foreground - skipping (handled by willPresent)")
            completionHandler(.noData)
            return
        }
        
        print("📨 Full notification payload: \(userInfo)")
        print("📨 Notification keys: \(userInfo.keys)")
        
        // Check if this is a Claude response notification with the new always-APNS payload
        if let claudeMessage = userInfo["message"] as? String,
           let sessionId = userInfo["sessionId"] as? String,
           let projectPath = userInfo["projectPath"] as? String {
            
            print("🤖 === CLAUDE RESPONSE NOTIFICATION DETECTED ===")
            print("🤖 Message preview: \(String(claudeMessage.prefix(100)))...")
            print("🤖 Session ID: \(sessionId)")
            print("🤖 Project Path: \(projectPath)")
            print("🤖 Full message length: \(claudeMessage.count) characters")
            
            
            // Start background task to process Claude response
            let taskId = application.beginBackgroundTask(withName: "ProcessClaudeResponse") {
                print("⏰ Background task expired during Claude response processing")
                completionHandler(.failed)
            }
            
            Task {
                let processSuccess = await self.processClaudeResponseNotification(
                    message: claudeMessage,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    originalMessage: userInfo["originalMessage"] as? String,
                    requestId: userInfo["requestId"] as? String,
                    userInfo: userInfo
                )
                
                // Complete background task
                application.endBackgroundTask(taskId)
                
                if processSuccess {
                    print("✅ Claude response processed successfully")
                    completionHandler(.newData)
                } else {
                    print("❌ Failed to process Claude response")
                    completionHandler(.failed)
                }
            }
            
            return
        }
        
        // Legacy notification handling (for backward compatibility)
        print("📨 === NOT A CLAUDE RESPONSE NOTIFICATION ===")
        print("📨 Checking for legacy notification format...")
        
        guard let projectId = userInfo["projectId"] as? String,
              let projectName = userInfo["projectName"] as? String else {
            print("⚠️ === UNKNOWN NOTIFICATION FORMAT ===")
            print("⚠️ Missing both Claude response format AND legacy format")
            print("⚠️ Available keys: \(userInfo.keys)")
            completionHandler(.noData)
            return
        }
        
        let sessionId = userInfo["sessionId"] as? String
        let notificationTitle = userInfo["title"] as? String ?? "New Message"
        let notificationBody = userInfo["body"] as? String ?? "You have a new message in \(projectName)"
        
        // Schedule local notification for legacy notifications
        EnhancedPushNotificationService.shared.scheduleProjectNotification(
            title: notificationTitle,
            body: notificationBody,
            projectId: projectId,
            projectName: projectName,
            sessionId: sessionId
        )
        
        print("ℹ️ Processed legacy notification")
        completionHandler(.noData)
    }
    
    // MARK: - Claude Response Processing
    
    private func processClaudeResponseNotification(
        message: String,
        sessionId: String,
        projectPath: String,
        originalMessage: String?,
        requestId: String?,
        userInfo: [AnyHashable: Any]
    ) async -> Bool {
        print("🔄 === PROCESSING CLAUDE RESPONSE FROM APNS ===")
        print("🔄 Session ID: \(sessionId)")
        print("🔄 Project Path: \(projectPath)")
        print("🔄 Message Length: \(message.count)")
        print("🔄 Original Message: \(originalMessage ?? "none")")
        print("🔄 Request ID: \(requestId ?? "none")")
        
        do {
            // Create Message object from Claude response
            let claudeMessage = Message(
                content: message,
                sender: .assistant,
                type: .markdown, // Claude responses are typically markdown
                metadata: AICLIMessageMetadata(
                    sessionId: sessionId,
                    duration: 0,
                    additionalInfo: [
                        "deliveredVia": "apns",
                        "requestId": requestId ?? "",
                        "originalMessage": originalMessage ?? "",
                        "processedAt": Date()
                    ]
                )
            )
            
            // Extract project name from path
            let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
            
            // Create project object for persistence
            let project = Project(
                name: projectName,
                path: projectPath,
                type: "directory"
            )
            
            // Save message to persistence
            let messages = [claudeMessage]
            MessagePersistenceService.shared.saveMessages(
                for: projectPath,
                messages: messages,
                sessionId: sessionId,
                project: project
            )
            
            print("💾 Saved Claude response to persistence")
            
            // Update session tracking
            BackgroundSessionCoordinator.shared.processSavedMessagesWithSessionId(sessionId, for: project)
            
            // Notify UI if app is active
            await MainActor.run {
                print("📡 === POSTING NOTIFICATION TO UI ===")
                print("📡 Notification name: .claudeResponseReceived")
                print("📡 Session ID: \(sessionId)")
                print("📡 Project: \(project.name)")
                
                NotificationCenter.default.post(
                    name: .claudeResponseReceived,
                    object: nil,
                    userInfo: [
                        "message": claudeMessage,
                        "sessionId": sessionId,
                        "projectPath": projectPath,
                        "project": project
                    ]
                )
                
                print("📡 NotificationCenter.post() completed")
            }
            
            print("✅ === CLAUDE RESPONSE PROCESSING COMPLETED ===")
            print("✅ Message saved to persistence: \(claudeMessage.content.prefix(50))...")
            print("✅ UI notification posted successfully")
            return true
            
        } catch {
            print("❌ Failed to process Claude response: \(error)")
            return false
        }
    }
}
#endif
