import SwiftUI
import Combine

/// Handles APNS and notification processing for chat
@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatNotificationHandler: ObservableObject {
    // MARK: - Dependencies
    private let messageManager: ChatMessageManager
    private let loadingStateManager: ChatLoadingStateManager
    private let projectStateManager: ChatProjectStateManager
    
    // MARK: - Initialization
    init(
        messageManager: ChatMessageManager,
        loadingStateManager: ChatLoadingStateManager,
        projectStateManager: ChatProjectStateManager
    ) {
        self.messageManager = messageManager
        self.loadingStateManager = loadingStateManager
        self.projectStateManager = projectStateManager
        setupNotificationObservers()
    }
    
    // MARK: - Setup
    
    private func setupNotificationObservers() {
        // Set up notification observers for Claude responses
        NotificationCenter.default.addObserver(
            forName: .claudeResponseReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleClaudeResponseNotification(notification)
        }
    }
    
    // MARK: - Notification Handling
    
    private func handleClaudeResponseNotification(_ notification: Notification) {
        print("📨 ChatNotificationHandler: Received Claude response notification")
        
        guard let payload = extractNotificationPayload(notification) else {
            debugInvalidNotification(notification)
            return
        }
        
        let (message, sessionId, project) = payload
        logNotificationDetails(message: message, sessionId: sessionId, project: project)
        
        // Only process if this is for the current project
        guard project.path == projectStateManager.currentProject?.path else {
            print("🚫 ChatNotificationHandler: Ignoring message for different project")
            print("   Received for: \(project.path)")
            print("   Current project: \(projectStateManager.currentProject?.path ?? "none")")
            return
        }
        
        // Clear loading state for the project
        clearLoadingStateIfNeeded(for: project)
        
        // Add message to conversation
        addMessageToConversation(message, for: project)
    }
    
    private func extractNotificationPayload(_ notification: Notification) -> (Message, String, Project)? {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? Message,
              let project = userInfo["project"] as? Project else {
            return nil
        }
        // Session ID is optional in the sessionless architecture
        let sessionId = userInfo["sessionId"] as? String ?? ""
        return (message, sessionId, project)
    }
    
    private func debugInvalidNotification(_ notification: Notification) {
        print("⚠️ ChatNotificationHandler: Invalid Claude response notification payload")
        if let keys = notification.userInfo?.keys {
            print("⚠️ userInfo keys: \(Array(keys))")
        } else {
            print("⚠️ userInfo is nil")
        }
    }
    
    private func logNotificationDetails(message: Message, sessionId: String, project: Project) {
        print("🎯 ChatNotificationHandler: Claude response notification validated")
        print("🎯 Project: \(project.name) (\(project.path))")
        print("🎯 Current Project: \(projectStateManager.currentProject?.name ?? "nil")")
        print("🎯 Message ID: \(message.id)")
        print("🎯 Message content preview: \(String(message.content.prefix(100)))...")
    }
    
    private func clearLoadingStateIfNeeded(for project: Project) {
        // Clear loading state if this is for the current project
        if project.path == projectStateManager.currentProject?.path {
            loadingStateManager.clearLoadingState(for: project.path)
            
            // Also clear waiting state in project state to re-enable send button
            projectStateManager.updateProjectState(for: project.path) { state in
                state.isWaitingForResponse = false
            }
        }
    }
    
    private func addMessageToConversation(_ message: Message, for project: Project) {
        // Validate and add message
        guard messageManager.shouldDisplayMessage(message) else {
            print("🚫 ChatNotificationHandler: Filtered blank message from conversation")
            return
        }
        
        // Message was already saved to disk by PushNotificationService
        // The duplicate check in appendMessage will prevent double-saving
        // since we're now using the same Message ID
        messageManager.appendMessage(message, for: project)
        
        // Clear badge count
        #if os(iOS)
        UIApplication.shared.applicationIconBadgeNumber = 0
        #endif
    }
}
