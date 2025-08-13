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
    
    /// Simple check if notification should be shown (best practices)
    func shouldShowNotification(for sessionId: String, projectPath: String) -> Bool {
        // Only suppress if user is actively viewing this exact conversation
        let isViewingSameSession = (currentActiveSessionId == sessionId)
        let isViewingSameProject = (currentActiveProject?.path == projectPath)
        
        // Suppress notification only if both match (viewing exact same thread)
        return !(isViewingSameSession && isViewingSameProject)
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
            
            // Use simple check to decide if notification should be shown
            let shouldShow = shouldShowNotification(for: sessionId, projectPath: projectPath)
            
            if !shouldShow {
                print("🤖 Response is for CURRENT thread - processing silently")
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
                
                // Don't show banner for current thread - process silently
                // IMPORTANT: Return empty options to prevent didReceiveRemoteNotification from being called
                completionHandler([])
            } else {
                print("🔔 Response is for DIFFERENT thread - showing banner")
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
        
        // Simple notification post - no retry needed (best practices)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .claudeResponseReceived,
                object: nil,
                userInfo: [
                    "message": claudeMessage,
                    "sessionId": sessionId,
                    "projectPath": projectPath,
                    "project": project,
                    "timestamp": Date()
                ]
            )
            
            // Clear badge since we've processed this notification
            #if os(iOS)
            UIApplication.shared.applicationIconBadgeNumber = 0
            #endif
        }
        
        print("✅ Foreground Claude response posted to ChatViewModel")
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
        
        // Local-first pattern: Message already saved to local storage
        // No additional session coordination needed
        
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
        // Handle both old format (projectId) and new format (projectPath)
        let projectPath = userInfo["projectPath"] as? String ?? userInfo["projectId"] as? String
        let projectName = userInfo["projectName"] as? String ?? projectPath?.split(separator: "/").last.map(String.init) ?? "Project"
        
        guard let projectPath = projectPath else {
            print("⚠️ No project path in notification")
            return
        }
        
        print("👁 View action for project: \(projectName) at path: \(projectPath)")
        
        // Clear notifications for this project
        clearProjectNotifications(projectPath)
        
        // Navigate directly - no sync needed in stateless architecture
        if let sessionId = userInfo["sessionId"] as? String {
            Task { @MainActor in
                // Create project object
                let project = Project(
                    name: projectName,
                    path: projectPath,
                    type: "directory"
                )
                
                // Post notification to navigate to project
                NotificationCenter.default.post(
                    name: .openProject,
                    object: nil,
                    userInfo: [
                        "project": project,
                        "projectPath": projectPath,
                        "projectName": projectName,
                        "sessionId": sessionId
                    ]
                )
                
                print("✅ Posted navigation to project: \(projectName) with session: \(sessionId)")
            }
        } else {
            // No session ID, open project directly
            NotificationCenter.default.post(
                name: .openProject,
                object: nil,
                userInfo: [
                    "projectPath": projectPath,
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
}
