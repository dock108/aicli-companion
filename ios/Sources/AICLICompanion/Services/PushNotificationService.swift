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
        
        // Check if this requires fetching (iMessage-style for large messages)
        if let requiresFetch = userInfo["requiresFetch"] as? Bool,
           requiresFetch,
           let messageId = userInfo["messageId"] as? String,
           let sessionId = userInfo["sessionId"] as? String,
           let projectPath = userInfo["projectPath"] as? String,
           let preview = userInfo["preview"] as? String {
            print("📲 === LARGE MESSAGE SIGNAL RECEIVED ===")
            print("📲 Message ID: \(messageId)")
            print("📲 Session ID: \(sessionId)")
            print("📲 Preview: \(preview)")
            
            // Fetch the full message content
            Task {
                do {
                    print("🌐 Fetching full message content...")
                    let fullMessage = try await AICLIService.shared.fetchMessage(
                        sessionId: sessionId,
                        messageId: messageId
                    )
                    
                    print("✅ Full message fetched: \(fullMessage.content.count) characters")
                    
                    // Save the fetched message
                    await saveClaudeMessage(
                        message: fullMessage.content,
                        sessionId: sessionId,
                        projectPath: projectPath,
                        userInfo: userInfo
                    )
                    
                    // Post notification to UI with full content
                    await postClaudeResponseNotification(
                        message: fullMessage.content,
                        sessionId: sessionId,
                        projectPath: projectPath
                    )
                } catch {
                    print("❌ Failed to fetch message: \(error)")
                    
                    // Show preview with error indication
                    let errorMessage = "\(preview)\n\n⚠️ [Failed to load full message. Tap to retry.]"
                    await saveClaudeMessage(
                        message: errorMessage,
                        sessionId: sessionId,
                        projectPath: projectPath,
                        userInfo: userInfo
                    )
                    
                    await postClaudeResponseNotification(
                        message: errorMessage,
                        sessionId: sessionId,
                        projectPath: projectPath
                    )
                }
            }
            
            // Don't show system notification for large messages being fetched
            // The notification will be handled after fetching is complete
            completionHandler([])
            return
        } else if let claudeMessage = userInfo["message"] as? String,
                  let sessionId = userInfo["sessionId"] as? String,
                  let projectPath = userInfo["projectPath"] as? String {
            // Small message - process normally (backwards compatible)
            print("🤖 === CLAUDE RESPONSE RECEIVED ===")
            print("🤖 Session ID: \(sessionId)")
            print("🤖 Project Path: \(projectPath)")
            print("🤖 Message length: \(claudeMessage.count) characters")
            print("🤖 Message preview: \(String(claudeMessage.prefix(100)))...")
            
            // Always save message to local storage (simple local-first pattern)
            Task {
                await saveClaudeMessage(
                    message: claudeMessage,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    userInfo: userInfo
                )
            }
            
            // Notify UI about the Claude response
            Task {
                await postClaudeResponseNotification(
                    message: claudeMessage,
                    sessionId: sessionId,
                    projectPath: projectPath
                )
            }
            
            // Simple notification suppression check
            let shouldShow = shouldShowNotification(for: sessionId, projectPath: projectPath)
            
            if !shouldShow {
                print("🤖 Suppressing notification - user viewing same project/session")
                // Don't show banner
                completionHandler([])
            } else {
                print("🔔 Showing notification banner - different project")
                // Show banner for responses from other projects
                completionHandler([.banner, .sound, .badge])
            }
        } else {
            print("🔔 Standard notification - showing banner")
            // Show notification banner for non-Claude notifications
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    /// Post Claude response notification to UI
    @MainActor
    private func postClaudeResponseNotification(
        message: String,
        sessionId: String,
        projectPath: String
    ) {
        let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
        let project = Project(name: projectName, path: projectPath, type: "directory")
        
        let claudeMessage = Message(
            content: message,
            sender: .assistant,
            type: .markdown,
            metadata: AICLIMessageMetadata(sessionId: sessionId, duration: 0)
        )
        
        print("🔔 Posting claudeResponseReceived notification to UI")
        print("🔔 Message content length: \(claudeMessage.content.count)")
        print("🔔 Message ID: \(claudeMessage.id)")
        
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
        
        print("🔔 Notification posted successfully")
    }
    
    /// Simple method to save Claude message to local storage
    private func saveClaudeMessage(
        message: String,
        sessionId: String,
        projectPath: String,
        userInfo: [AnyHashable: Any]
    ) async {
        print("💾 === SAVING CLAUDE MESSAGE TO LOCAL STORAGE ===")
        print("💾 Message length: \(message.count) characters")
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
                    "deliveredVia": "apns",
                    "requestId": userInfo["requestId"] as? String ?? "",
                    "originalMessage": userInfo["originalMessage"] as? String ?? ""
                ]
            )
        )
        
        // Extract project name and create project object
        let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
        let project = Project(name: projectName, path: projectPath, type: "directory")
        
        // Check if this is a fresh chat BEFORE saving (important!)
        let hadExistingSession = MessagePersistenceService.shared.getSessionMetadata(for: projectPath) != nil
        
        // Save to local storage using append (local-first pattern)
        MessagePersistenceService.shared.appendMessage(
            claudeMessage,
            to: projectPath,
            sessionId: sessionId,
            project: project
        )
        
        if !hadExistingSession {
            print("🆕 Fresh chat detected - posting session establishment notification")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .freshChatSessionEstablished,
                    object: nil,
                    userInfo: [
                        "sessionId": sessionId,
                        "projectPath": projectPath,
                        "project": project
                    ]
                )
            }
        }
        
        print("💾 Claude message saved to local storage")
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
                    "sessionId": userInfo["sessionId"] as? String ?? ""
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
    static let freshChatSessionEstablished = Notification.Name("com.aiclicompanion.freshChatSessionEstablished")
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
