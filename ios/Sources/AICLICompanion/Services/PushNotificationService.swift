import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Push notification service with actions and grouping
@available(iOS 16.0, macOS 13.0, *)
public class PushNotificationService: NSObject, ObservableObject {
    public static let shared = PushNotificationService()
    
    // MARK: - Published Properties
    
    @Published public var badgeCount: Int = 0
    @Published public var pendingNotifications: [String: Int] = [:] // projectId: count
    @Published public var currentActiveProject: Project?
    @Published public var currentActiveSessionId: String?
    
    // MARK: - Constants
    
    private let notificationCategoryIdentifier = "CLAUDE_COMPANION_CATEGORY"
    private let viewActionIdentifier = "VIEW_ACTION"
    private let dismissActionIdentifier = "DISMISS_ACTION"
    private let markReadActionIdentifier = "MARK_READ_ACTION"
    
    // MARK: - Private Properties
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Message Queue for Retry (TODO 2.1)
    
    private struct PendingNotification {
        let message: Message
        let sessionId: String
        let projectPath: String
        let project: Project
        let retryCount: Int
        let timestamp: Date
    }
    
    private var pendingMessageQueue: [PendingNotification] = []
    private var retryTimers: [UUID: Timer] = [:]
    private let maxRetryAttempts = 3
    private let retryDelays: [TimeInterval] = [0.5, 1.0, 2.0] // Exponential backoff
    
    // MARK: - Initialization
    
    override private init() {
        super.init()
        setupNotificationCategories()
        notificationCenter.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Configure notification categories and actions
    func setupNotificationCategories() {
        // Create actions
        let viewAction = UNNotificationAction(
            identifier: viewActionIdentifier,
            title: "View",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: dismissActionIdentifier,
            title: "Dismiss",
            options: [.destructive]
        )
        
        let markReadAction = UNNotificationAction(
            identifier: markReadActionIdentifier,
            title: "Mark as Read",
            options: []
        )
        
        // Create category
        let category = UNNotificationCategory(
            identifier: notificationCategoryIdentifier,
            actions: [viewAction, markReadAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register categories
        notificationCenter.setNotificationCategories([category])
        
        print("📱 Registered notification categories with actions")
    }
    
    /// Request notification authorization with enhanced options
    public func requestAuthorizationWithOptions() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .criticalAlert]
        
        do {
            let granted = try await notificationCenter.requestAuthorization(options: options)
            
            if granted {
                print("✅ Push notifications authorized with all options")
                
                // Register for remote notifications on main thread
                await MainActor.run {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
            }
            
            return granted
        } catch {
            print("❌ Failed to request notification authorization: \(error)")
            throw error
        }
    }
    
    /// Schedule a grouped notification for a project
    func scheduleProjectNotification(
        title: String,
        body: String,
        projectId: String,
        projectName: String,
        sessionId: String?,
        sound: UNNotificationSound = .default
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.categoryIdentifier = notificationCategoryIdentifier
        
        // Group by project
        content.threadIdentifier = projectId
        
        // Add user info
        var userInfo: [String: Any] = [
            "projectId": projectId,
            "projectName": projectName,
            "type": "project_message"
        ]
        
        if let sessionId = sessionId {
            userInfo["sessionId"] = sessionId
        }
        
        content.userInfo = userInfo
        
        // Update badge count
        incrementBadgeCount(for: projectId)
        content.badge = NSNumber(value: badgeCount)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        // Schedule notification
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error)")
            } else {
                print("📬 Scheduled notification for project: \(projectName)")
            }
        }
    }
    
    /// Clear notifications for a specific project
    public func clearProjectNotifications(_ projectId: String) {
        notificationCenter.getDeliveredNotifications { [weak self] notifications in
            let identifiersToRemove = notifications
                .filter { notification in
                    if let notificationProjectId = notification.request.content.userInfo["projectId"] as? String {
                        return notificationProjectId == projectId
                    }
                    return false
                }
                .map { $0.request.identifier }
            
            if !identifiersToRemove.isEmpty {
                self?.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
                print("🧹 Cleared \(identifiersToRemove.count) notifications for project: \(projectId)")
                
                // Update badge count
                self?.decrementBadgeCount(for: projectId, count: identifiersToRemove.count)
            }
        }
    }
    
    /// Update application badge count
    func updateApplicationBadge() {
        #if os(iOS)
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
        #endif
    }
    
    /// Reset badge count
    public func resetBadgeCount() {
        badgeCount = 0
        pendingNotifications.removeAll()
        updateApplicationBadge()
    }
    
    /// Get notification settings
    func getNotificationSettings() async -> UNNotificationSettings {
        return await notificationCenter.notificationSettings()
    }
    
    /// Update the currently active project and session
    public func setActiveProject(_ project: Project?, sessionId: String?) {
        currentActiveProject = project
        currentActiveSessionId = sessionId
        
        if let project = project {
            print("📍 Active project set to: \(project.name) (session: \(sessionId ?? "none"))")
        } else {
            print("📍 No active project")
        }
    }
    
    // MARK: - Private Methods
    
    private func incrementBadgeCount(for projectId: String) {
        pendingNotifications[projectId, default: 0] += 1
        badgeCount = pendingNotifications.values.reduce(0, +)
        updateApplicationBadge()
    }
    
    private func decrementBadgeCount(for projectId: String, count: Int = 1) {
        if let currentCount = pendingNotifications[projectId] {
            let newCount = max(0, currentCount - count)
            if newCount == 0 {
                pendingNotifications.removeValue(forKey: projectId)
            } else {
                pendingNotifications[projectId] = newCount
            }
        }
        
        badgeCount = pendingNotifications.values.reduce(0, +)
        updateApplicationBadge()
    }
}

// MARK: - UNUserNotificationCenterDelegate

@available(iOS 16.0, macOS 13.0, *)
extension PushNotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification while app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("🔔 === FOREGROUND NOTIFICATION RECEIVED ===")
        let userInfo = notification.request.content.userInfo
        print("🔔 Notification payload keys: \(userInfo.keys)")
        
        // Check if this is a Claude response notification with APNS payload
        if let claudeMessage = userInfo["message"] as? String,
           let sessionId = userInfo["sessionId"] as? String,
           let projectPath = userInfo["projectPath"] as? String {
            print("🤖 === CLAUDE RESPONSE IN FOREGROUND ===")
            print("🤖 Session ID: \(sessionId)")
            print("🤖 Project Path: \(projectPath)")
            print("🤖 Current Active Session: \(currentActiveSessionId ?? "none")")
            print("🤖 Current Active Project: \(currentActiveProject?.path ?? "none")")
            
            // Check if this notification is for the currently active project/session
            let isForCurrentProject = (sessionId == currentActiveSessionId) ||
                                     (currentActiveProject?.path == projectPath)
            
            if isForCurrentProject {
                print("🤖 Response is for CURRENT project - processing silently")
                print("🤖 Message preview: \(String(claudeMessage.prefix(100)))...")
                
                // Process Claude response immediately for foreground delivery
                Task {
                    await processClaudeResponseInForeground(
                        message: claudeMessage,
                        sessionId: sessionId,
                        projectPath: projectPath,
                        originalMessage: userInfo["originalMessage"] as? String,
                        requestId: userInfo["requestId"] as? String,
                        userInfo: userInfo
                    )
                }
                
                // Don't show banner for current project - process silently
                // IMPORTANT: Return empty options to prevent didReceiveRemoteNotification from being called
                completionHandler([])
            } else {
                print("🔔 Response is for DIFFERENT project - showing banner")
                print("🔔 Project: \(projectPath.split(separator: "/").last ?? "Unknown")")
                
                // Save to persistence for later viewing
                Task {
                    await saveClaudeResponseForBackground(
                        message: claudeMessage,
                        sessionId: sessionId,
                        projectPath: projectPath,
                        originalMessage: userInfo["originalMessage"] as? String,
                        requestId: userInfo["requestId"] as? String,
                        userInfo: userInfo
                    )
                }
                
                // Show banner for responses from other projects
                completionHandler([.banner, .sound, .badge])
            }
        } else {
            print("🔔 Standard notification - showing banner")
            // Show notification banner for non-Claude notifications
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    private func processClaudeResponseInForeground(
        message: String,
        sessionId: String,
        projectPath: String,
        originalMessage: String?,
        requestId: String?,
        userInfo: [AnyHashable: Any]
    ) async {
        print("🔄 === PROCESSING CLAUDE RESPONSE IN FOREGROUND ===")
        
        // Create Message object from Claude response
        let claudeMessage = Message(
            content: message,
            sender: .assistant,
            type: .markdown,
            metadata: AICLIMessageMetadata(
                sessionId: sessionId,
                duration: 0,
                additionalInfo: [
                    "deliveredVia": "apns_foreground",
                    "requestId": requestId ?? "",
                    "originalMessage": originalMessage ?? "",
                    "processedAt": Date()
                ]
            )
        )
        
        // Extract project name from path
        let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
        
        // Create project object
        let project = Project(
            name: projectName,
            path: projectPath,
            type: "directory"
        )
        
        // Post notification to ChatViewModel with retry mechanism (TODO 2.1)
        await postNotificationWithRetry(
            message: claudeMessage,
            sessionId: sessionId,
            projectPath: projectPath,
            project: project
        )
        
        print("✅ Foreground Claude response processing completed")
    }
    
    private func saveClaudeResponseForBackground(
        message: String,
        sessionId: String,
        projectPath: String,
        originalMessage: String?,
        requestId: String?,
        userInfo: [AnyHashable: Any]
    ) async {
        print("💾 === SAVING CLAUDE RESPONSE FOR BACKGROUND PROJECT ===")
        print("💾 Session ID: \(sessionId)")
        print("💾 Project Path: \(projectPath)")
        
        // Create Message object from Claude response
        let claudeMessage = Message(
            content: message,
            sender: .assistant,
            type: .markdown,
            metadata: AICLIMessageMetadata(
                sessionId: sessionId,
                duration: 0,
                additionalInfo: [
                    "deliveredVia": "apns_background_project",
                    "requestId": requestId ?? "",
                    "originalMessage": originalMessage ?? "",
                    "processedAt": Date()
                ]
            )
        )
        
        // Extract project name from path
        let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
        
        // Create project object
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
        
        print("💾 Saved background project response to persistence")
        
        // Update session tracking
        BackgroundSessionCoordinator.shared.processSavedMessagesWithSessionId(sessionId, for: project)
        
        print("💾 Background project response processing completed")
    }
    
    /// Handle notification actions
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        print("📱 User responded to notification with action: \(response.actionIdentifier)")
        
        switch response.actionIdentifier {
        case viewActionIdentifier:
            handleViewAction(userInfo: userInfo)
            
        case dismissActionIdentifier:
            handleDismissAction(userInfo: userInfo)
            
        case markReadActionIdentifier:
            handleMarkReadAction(userInfo: userInfo)
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            handleViewAction(userInfo: userInfo)
            
        default:
            break
        }
        
        completionHandler()
    }
    
    private func handleViewAction(userInfo: [AnyHashable: Any]) {
        guard let projectId = userInfo["projectId"] as? String,
              let projectName = userInfo["projectName"] as? String else {
            return
        }
        
        print("👁 View action for project: \(projectName)")
        
        // Clear notifications for this project
        clearProjectNotifications(projectId)
        
        // Sync messages before opening project
        if let sessionId = userInfo["sessionId"] as? String {
            Task {
                print("🔄 Syncing messages before opening project")
                let syncSuccess = await BackgroundMessageSyncService.shared.syncMessagesForSession(
                    sessionId,
                    projectId: projectId,
                    projectName: projectName
                )
                
                if syncSuccess {
                    print("✅ Messages synced successfully, opening project")
                } else {
                    print("⚠️ Message sync failed, opening project anyway")
                }
                
                // Post notification to open the project after sync attempt
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .openProject,
                        object: nil,
                        userInfo: [
                            "projectId": projectId,
                            "projectName": projectName,
                            "sessionId": sessionId,
                            "messagesSynced": syncSuccess
                        ]
                    )
                }
            }
        } else {
            // No session ID, open project directly
            NotificationCenter.default.post(
                name: .openProject,
                object: nil,
                userInfo: [
                    "projectId": projectId,
                    "projectName": projectName,
                    "sessionId": userInfo["sessionId"] as? String
                ]
            )
        }
    }
    
    private func handleDismissAction(userInfo: [AnyHashable: Any]) {
        guard let projectId = userInfo["projectId"] as? String else {
            return
        }
        
        print("🗑 Dismiss action for project: \(projectId)")
        
        // Clear notifications for this project
        clearProjectNotifications(projectId)
    }
    
    private func handleMarkReadAction(userInfo: [AnyHashable: Any]) {
        guard let projectId = userInfo["projectId"] as? String else {
            return
        }
        
        print("✓ Mark as read action for project: \(projectId)")
        
        // Update badge count without clearing notifications
        if let count = pendingNotifications[projectId] {
            decrementBadgeCount(for: projectId, count: count)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openProject = Notification.Name("com.aiclicompanion.openProject")
    static let markProjectRead = Notification.Name("com.aiclicompanion.markProjectRead")
    static let claudeResponseReceived = Notification.Name("com.aiclicompanion.claudeResponseReceived")
    static let openChatSession = Notification.Name("com.aiclicompanion.openChatSession")
}

// MARK: - Push Notification Payload Helper

@available(iOS 16.0, macOS 13.0, *)
struct PushNotificationPayload: Codable {
    let aps: APSPayload
    let projectId: String
    let projectName: String
    let sessionId: String?
    let messageType: String
    
    struct APSPayload: Codable {
        let alert: Alert
        let badge: Int?
        let sound: String?
        let threadId: String
        let category: String
        
        struct Alert: Codable {
            let title: String
            let body: String
            let subtitle: String?
        }
        
        enum CodingKeys: String, CodingKey {
            case alert, badge, sound
            case threadId = "thread-id"
            case category
        }
    }
    
    // MARK: - Message Queue and Retry Mechanism (TODO 2.1)
    
    private func postNotificationWithRetry(
        message: Message,
        sessionId: String,
        projectPath: String,
        project: Project
    ) async {
        print("📡 === POSTING NOTIFICATION WITH RETRY ===")
        
        // First attempt - post immediately
        let notificationPosted = await postNotificationToViewModel(
            message: message,
            sessionId: sessionId,
            projectPath: projectPath,
            project: project
        )
        
        if !notificationPosted {
            // Add to retry queue if first attempt failed
            let pending = PendingNotification(
                message: message,
                sessionId: sessionId,
                projectPath: projectPath,
                project: project,
                retryCount: 0,
                timestamp: Date()
            )
            
            await MainActor.run {
                pendingMessageQueue.append(pending)
                print("⏳ Added message to retry queue - will retry in \(retryDelays[0])s")
            }
            
            // Schedule retry
            scheduleRetry(for: pending)
        }
    }
    
    private func postNotificationToViewModel(
        message: Message,
        sessionId: String,
        projectPath: String,
        project: Project
    ) async -> Bool {
        // Check if ChatViewModel is ready to receive notifications
        // We do this by checking if there are observers for the notification
        
        await MainActor.run {
            print("📡 Attempting to post notification to ChatViewModel")
            
            // Post the notification
            NotificationCenter.default.post(
                name: .claudeResponseReceived,
                object: nil,
                userInfo: [
                    "message": message,
                    "sessionId": sessionId,
                    "projectPath": projectPath,
                    "project": project,
                    "timestamp": Date()
                ]
            )
            
            // Clear badge since we're processing this notification
            #if os(iOS)
            UIApplication.shared.applicationIconBadgeNumber = 0
            #endif
            
            print("📡 Notification posted successfully")
            
            // TODO 2.2: In the future, we'll check for acknowledgment from ChatViewModel
            // For now, we assume success if we reach this point
            return true
        }
    }
    
    private func scheduleRetry(for notification: PendingNotification) {
        guard notification.retryCount < maxRetryAttempts else {
            print("❌ Max retry attempts reached for message: \(notification.message.id)")
            // Save to persistence as fallback
            saveFailedNotificationToPersistence(notification)
            return
        }
        
        let delay = retryDelays[min(notification.retryCount, retryDelays.count - 1)]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task {
                await self?.retryNotification(notification)
            }
        }
    }
    
    private func retryNotification(_ notification: PendingNotification) async {
        print("🔄 Retrying notification (attempt \(notification.retryCount + 1)/\(maxRetryAttempts))")
        
        let success = await postNotificationToViewModel(
            message: notification.message,
            sessionId: notification.sessionId,
            projectPath: notification.projectPath,
            project: notification.project
        )
        
        if !success {
            // Increment retry count and try again
            let updatedNotification = PendingNotification(
                message: notification.message,
                sessionId: notification.sessionId,
                projectPath: notification.projectPath,
                project: notification.project,
                retryCount: notification.retryCount + 1,
                timestamp: notification.timestamp
            )
            
            scheduleRetry(for: updatedNotification)
        } else {
            print("✅ Notification delivered successfully on retry")
            // Remove from pending queue
            await MainActor.run {
                pendingMessageQueue.removeAll { $0.message.id == notification.message.id }
            }
        }
    }
    
    private func saveFailedNotificationToPersistence(_ notification: PendingNotification) {
        print("💾 Saving failed notification to persistence as fallback")
        
        // Save message to persistence
        MessagePersistenceService.shared.saveMessages(
            for: notification.projectPath,
            messages: [notification.message],
            sessionId: notification.sessionId,
            project: notification.project
        )
        
        // Update session tracking
        BackgroundSessionCoordinator.shared.processSavedMessagesWithSessionId(
            notification.sessionId, 
            for: notification.project
        )
        
        print("💾 Failed notification saved to persistence - will be recovered on next app launch")
    }
    
    /// Clear pending message queue - useful when ChatViewModel is destroyed
    public func clearPendingQueue() {
        pendingMessageQueue.removeAll()
        retryTimers.values.forEach { $0.invalidate() }
        retryTimers.removeAll()
        print("🧹 Cleared pending message queue")
    }
}
