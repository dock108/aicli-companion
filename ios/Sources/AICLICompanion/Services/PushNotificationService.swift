import Foundation
import UserNotifications
import CryptoKit
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
    // Use unified project state instead of duplicate tracking
    private let projectStateManager = ProjectStateManager.shared
    
    // Track current active project for notification suppression
    @MainActor
    private var currentActiveProjectPath: String? {
        return projectStateManager.currentProject?.path
    }
    
    // MARK: - Constants
    
    private let notificationCategoryIdentifier = "CLAUDE_COMPANION_CATEGORY"
    private let viewActionIdentifier = "VIEW_ACTION"
    private let dismissActionIdentifier = "DISMISS_ACTION"
    private let markReadActionIdentifier = "MARK_READ_ACTION"
    
    // MARK: - Private Properties
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // Track processed message IDs to prevent duplicates (WhatsApp/iMessage pattern)
    private var processedMessageIds = Set<String>()
    private let processedMessageQueue = DispatchQueue(label: "com.aiclicompanion.processedMessages")
    private let processedMessagesKey = "processedPushNotificationIds"
    
    
    // MARK: - Initialization
    
    override private init() {
        super.init()
        setupNotificationCategories()
        notificationCenter.delegate = self
        loadProcessedMessageIds()
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
        let userInfo: [String: Any] = [
            "projectId": projectId,
            "projectName": projectName,
            "type": "project_message"
        ]
        
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
    
    /// Process any pending notifications that weren't processed while app was terminated
    /// This ensures no messages are lost even if background delivery failed
    public func processPendingNotifications() async {
        print("🔍 Checking for pending notifications to process...")
        
        // Get all delivered notifications
        let notifications = await notificationCenter.deliveredNotifications()
        
        var processedCount = 0
        for notification in notifications {
            let userInfo = notification.request.content.userInfo
            
            // Check if this is a Claude message that needs processing
            // Note: Check for non-empty message content, not just presence
            let hasValidMessage = (userInfo["message"] as? String)?.isEmpty == false
            let isClaudeMessage = hasValidMessage ||
                                 userInfo["requiresFetch"] != nil ||
                                 userInfo["messageId"] != nil
            
            if isClaudeMessage {
                // Check if we've already processed this notification
                let notificationId = extractNotificationId(from: userInfo)
                let alreadyProcessed = processedMessageQueue.sync {
                    processedMessageIds.contains(notificationId)
                }
                
                if !alreadyProcessed {
                    print("🔍 Found unprocessed Claude message, processing now...")
                    await processAPNSMessage(userInfo: userInfo)
                    processedCount += 1
                }
            }
        }
        
        if processedCount > 0 {
            print("✅ Processed \(processedCount) pending notifications")
        } else {
            print("✅ No pending notifications to process")
        }
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
    
    /// Update the currently active project
    public func setActiveProject(_ project: Project?) {
        // Project state is now managed by ProjectStateManager
        
        if let project = project {
            print("📍 Active project set to: \(project.name)")
        } else {
            print("📍 No active project")
        }
    }
    
    /// Simple check if notification should be shown (best practices)
    @MainActor
    func shouldShowNotification(for projectPath: String) -> Bool {
        // Only suppress if user is actively viewing this exact project
        let isViewingSameProject = (currentActiveProjectPath == projectPath)
        
        // Suppress notification only if viewing same project
        return !isViewingSameProject
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

// MARK: - Unified Message Processing

@available(iOS 16.0, macOS 13.0, *)
extension PushNotificationService {
    /// Unified APNS message handler - ALL messages go through this single pipeline
    /// Handles both small messages and large message fetching
    public func processAPNSMessage(userInfo: [AnyHashable: Any]) async {
        print("🚀 === UNIFIED MESSAGE PROCESSING ===")
        print("🚀 Processing with keys: \(Array(userInfo.keys))")
        
        // Extract or generate a unique ID for this notification
        let notificationId = extractNotificationId(from: userInfo)
        
        // Check if we've already processed this message (WhatsApp/iMessage pattern)
        let alreadyProcessed = processedMessageQueue.sync { processedMessageIds.contains(notificationId) }
        if alreadyProcessed {
            print("✅ Message already processed, skipping duplicate: \(notificationId)")
            return
        }
        
        // Mark as processed
        processedMessageQueue.sync { _ = processedMessageIds.insert(notificationId) }
        
        // Save to UserDefaults to persist across app restarts
        saveProcessedMessageIds()
        
        // Clean up old entries if set gets too large (keep last 100)
        await cleanupProcessedMessageIds()
        
        // Extract and store session ID if present
        if let projectPath = userInfo["projectPath"] as? String {
            // Check for claudeSessionId (new format) or sessionId (legacy)
            let sessionId = userInfo["claudeSessionId"] as? String ?? userInfo["sessionId"] as? String
            
            if let sessionId = sessionId {
                // Store session ID for this project
                let key = "claude_session_\(projectPath.replacingOccurrences(of: "/", with: "_"))"
                UserDefaults.standard.set(sessionId, forKey: key)
                print("✅ Stored Claude session ID from APNS: \(sessionId) for project: \(projectPath)")
            } else {
                print("⚠️ No session ID in APNS message for project: \(projectPath)")
                print("⚠️ Available keys: \(userInfo.keys.map { String(describing: $0) }.joined(separator: ", "))")
            }
        }
        
        // 1. Extract message data
        if let requiresFetch = userInfo["requiresFetch"] as? Bool,
           requiresFetch,
           let messageId = userInfo["messageId"] as? String,
           let projectPath = userInfo["projectPath"] as? String {
            // Large message - fetch full content
            let preview = userInfo["preview"] as? String ?? "Loading message..."
            print("📲 Large message signal - fetching full content...")
            print("📲 Message ID: \(messageId)")
            print("📲 Project Path: \(projectPath)")
            print("📲 Preview: \(preview)")
            
            do {
                let fullMessage = try await AICLIService.shared.fetchMessage(
                    messageId: messageId
                )
                
                print("✅ Message fetched: \(fullMessage.content.count) characters")
                
                // 2. Validate content
                guard !fullMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("⚠️ Fetched empty message - skipping")
                    return
                }
                
                // 3. Save to storage and get the Message object
                let savedMessage = await saveClaudeMessage(
                    message: fullMessage.content,
                    projectPath: projectPath,
                    userInfo: userInfo
                )
                
                // 4. Post notification to UI with the same Message object
                await postClaudeResponseNotificationWithMessage(
                    savedMessage,
                    projectPath: projectPath
                )
            } catch {
                print("❌ Failed to fetch message: \(error)")
                
                // Fallback to preview with error indication
                let errorMessage = "\(preview)\n\n⚠️ [Failed to load full message. Tap to retry.]"
                
                let savedErrorMessage = await saveClaudeMessage(
                    message: errorMessage,
                    projectPath: projectPath,
                    userInfo: userInfo
                )
                
                await postClaudeResponseNotificationWithMessage(
                    savedErrorMessage,
                    projectPath: projectPath
                )
            }
        } else if let claudeMessage = userInfo["message"] as? String,
                  let projectPath = userInfo["projectPath"] as? String {
            // Small message - process directly
            print("🤖 Processing message: \(claudeMessage.count) characters")
            print("🤖 Project Path: \(projectPath)")
            
            // 2. Validate content
            guard !claudeMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("⚠️ Received empty message - skipping")
                return
            }
            
            // 3. Save to storage and get the Message object
            let savedMessage = await saveClaudeMessage(
                message: claudeMessage,
                projectPath: projectPath,
                userInfo: userInfo
            )
            
            // 4. Post notification to UI with the same Message object
            await postClaudeResponseNotificationWithMessage(
                savedMessage,
                projectPath: projectPath
            )
            
            print("✅ Message processed and saved")
        } else {
            print("ℹ️ No Claude message content in notification payload")
        }
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
        print("🔔 === FOREGROUND NOTIFICATION ===")
        let userInfo = notification.request.content.userInfo
        
        // Process message through unified pipeline
        Task {
            await processAPNSMessage(userInfo: userInfo)
        }
        
        // Banner decision logic (UI presentation only)
        if let projectPath = userInfo["projectPath"] as? String {
            Task { @MainActor in
                let shouldShow = shouldShowNotification(for: projectPath)
                
                if !shouldShow {
                    print("🔕 Suppressing banner - user viewing same project")
                    completionHandler([])
                } else {
                    print("🔔 Showing banner - different project")
                    completionHandler([.banner, .sound, .badge])
                }
            }
        } else {
            // Non-Claude notification
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    /// Post Claude response notification to UI
    @MainActor
    internal func postClaudeResponseNotification(
        message: String,
        projectPath: String
    ) {
        let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
        let project = Project(name: projectName, path: projectPath, type: "directory")
        
        let claudeMessage = Message(
            content: message,
            sender: .assistant,
            type: .markdown
        )
        
        print("🔔 Posting claudeResponseReceived notification to UI")
        print("🔔 Message content length: \(claudeMessage.content.count)")
        print("🔔 Message ID: \(claudeMessage.id)")
        
        NotificationCenter.default.post(
            name: .claudeResponseReceived,
            object: nil,
            userInfo: [
                "message": claudeMessage,
                "projectPath": projectPath,
                "project": project
            ]
        )
        
        print("🔔 Notification posted successfully")
    }
    
    /// Post Claude response notification to UI with existing Message (prevents duplicate IDs)
    @MainActor
    internal func postClaudeResponseNotificationWithMessage(
        _ claudeMessage: Message,
        projectPath: String
    ) {
        let projectName = projectPath.split(separator: "/").last.map(String.init) ?? "Project"
        let project = Project(name: projectName, path: projectPath, type: "directory")
        
        print("🔔 Posting claudeResponseReceived notification to UI (reusing Message)")
        print("🔔 Message content length: \(claudeMessage.content.count)")
        print("🔔 Message ID: \(claudeMessage.id)")
        
        NotificationCenter.default.post(
            name: .claudeResponseReceived,
            object: nil,
            userInfo: [
                "message": claudeMessage,
                "projectPath": projectPath,
                "project": project
            ]
        )
        
        print("🔔 Notification posted successfully")
    }
    
    /// Extract unique notification ID from userInfo
    private func extractNotificationId(from userInfo: [AnyHashable: Any]) -> String {
        // Try to get existing message ID
        if let messageId = userInfo["messageId"] as? String {
            return messageId
        }
        
        // Try to get request ID
        if let requestId = userInfo["requestId"] as? String {
            return requestId
        }
        
        // For small messages, create stable ID from content hash
        if let message = userInfo["message"] as? String,
           let projectPath = userInfo["projectPath"] as? String {
            // Create deterministic ID from message content and project using SHA256
            let combined = "\(projectPath):\(message)"
            return stableHash(of: combined)
        }
        
        // Fallback to random ID (shouldn't happen)
        return UUID().uuidString
    }
    
    /// Create stable hash that doesn't change between app launches
    private func stableHash(of string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Load processed message IDs from UserDefaults
    private func loadProcessedMessageIds() {
        processedMessageQueue.sync {
            if let savedIds = UserDefaults.standard.array(forKey: processedMessagesKey) as? [String] {
                processedMessageIds = Set(savedIds)
                print("📱 Loaded \(processedMessageIds.count) processed message IDs from UserDefaults")
            } else {
                processedMessageIds = Set<String>()
                print("📱 No processed message IDs found in UserDefaults")
            }
        }
    }
    
    /// Save processed message IDs to UserDefaults
    private func saveProcessedMessageIds() {
        processedMessageQueue.sync {
            let idsArray = Array(processedMessageIds)
            UserDefaults.standard.set(idsArray, forKey: processedMessagesKey)
            print("💾 Saved \(processedMessageIds.count) processed message IDs to UserDefaults")
        }
    }
    
    /// Clear processed message IDs for a specific project when chat is cleared
    public func clearProcessedMessagesForProject(_ projectPath: String) {
        processedMessageQueue.sync {
            // Get all delivered notifications for this project
            notificationCenter.getDeliveredNotifications { [weak self] notifications in
                guard let self = self else { return }
                
                let projectNotificationIds = notifications
                    .filter { notification in
                        if let notificationProjectPath = notification.request.content.userInfo["projectPath"] as? String {
                            return notificationProjectPath == projectPath
                        }
                        return false
                    }
                    .compactMap { notification in
                        self.extractNotificationId(from: notification.request.content.userInfo)
                    }
                
                // Remove these IDs from processed set
                self.processedMessageQueue.sync {
                    for notificationId in projectNotificationIds {
                        self.processedMessageIds.remove(notificationId)
                    }
                }
                
                // Save updated processed IDs
                self.saveProcessedMessageIds()
                
                print("🗑️ Cleared \(projectNotificationIds.count) processed message IDs for project: \(projectPath)")
            }
        }
    }
    
    /// Clean up old processed message IDs to prevent memory growth
    private func cleanupProcessedMessageIds() async {
        var didCleanup = false
        processedMessageQueue.sync {
            // Keep only last 100 message IDs
            if processedMessageIds.count > 100 {
                // Convert to array, sort by insertion order isn't preserved in Set
                // So we'll just remove oldest entries when limit exceeded
                let excess = processedMessageIds.count - 100
                for _ in 0..<excess {
                    processedMessageIds.remove(processedMessageIds.first!)
                }
                didCleanup = true
            }
        }
        
        // Save to UserDefaults if we cleaned up
        if didCleanup {
            saveProcessedMessageIds()
        }
    }
    
    /// Simple method to save Claude message to local storage
    /// Returns the created Message for reuse
    internal func saveClaudeMessage(
        message: String,
        projectPath: String,
        userInfo: [AnyHashable: Any]
    ) async -> Message {
        print("💾 === SAVING CLAUDE MESSAGE TO LOCAL STORAGE ===")
        print("💾 Message length: \(message.count) characters")
        print("💾 Project Path: \(projectPath)")
        
        // Create Message object from Claude response
        // Trim trailing whitespace/newlines to prevent empty rows
        let trimmedContent = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let claudeMessage = Message(
            content: trimmedContent,
            sender: .assistant,
            type: .markdown
        )
        
        // Save to local storage using append (local-first pattern)
        MessagePersistenceService.shared.appendMessage(
            claudeMessage,
            to: projectPath
        )
        
        print("💾 Claude message saved to local storage")
        
        // Sync to CloudKit for cross-device availability
        print("☁️ PushNotificationService: Starting CloudKit sync task...")
        Task { @MainActor in
            do {
                print("☁️ PushNotificationService: Getting CloudKitSyncManager instance...")
                var mutableMessage = claudeMessage
                let cloudKitManager = CloudKitSyncManager.shared
                print("☁️ PushNotificationService: CloudKitSyncManager.iCloudAvailable = \(cloudKitManager.iCloudAvailable)")
                if cloudKitManager.iCloudAvailable {
                    // Include projectPath for CloudKit record
                    mutableMessage.projectPath = projectPath
                    print("☁️ PushNotificationService: Attempting to save message to CloudKit...")
                    try await cloudKitManager.saveMessage(mutableMessage)
                    print("☁️ PushNotificationService: Message synced to CloudKit for project: \(projectPath)")
                } else {
                    print("⚠️ PushNotificationService: CloudKit not available, message saved locally only")
                    if let errorMsg = cloudKitManager.errorMessage {
                        print("⚠️ CloudKit error: \(errorMsg)")
                    }
                }
            } catch {
                print("❌ PushNotificationService: Failed to sync message to CloudKit: \(error.localizedDescription)")
                // Don't fail the whole operation - local save was successful
            }
        }
        
        return claudeMessage
    }
    
    
    /// Handle notification actions - NAVIGATION ONLY (WhatsApp/iMessage pattern)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        print("📱 === NOTIFICATION TAPPED ===")
        print("📱 Action: \(response.actionIdentifier)")
        
        // WhatsApp/iMessage pattern: Tapping ONLY navigates, never processes messages
        // Messages should already be saved when received, not when tapped
        
        // Navigation logic only
        switch response.actionIdentifier {
        case viewActionIdentifier,
             UNNotificationDefaultActionIdentifier:
            handleViewAction(userInfo: userInfo)
            
        case dismissActionIdentifier:
            handleDismissAction(userInfo: userInfo)
            
        case markReadActionIdentifier:
            handleMarkReadAction(userInfo: userInfo)
            
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
                    "projectName": projectName
                ]
            )
            
            print("✅ Posted navigation to project: \(projectName)")
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
    static let projectMessagesCleared = Notification.Name("com.aiclicompanion.projectMessagesCleared")
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
