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
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleClaudeResponseNotification(notification)
            }
        }
    }
    
    // MARK: - Notification Handling
    
    private func handleClaudeResponseNotification(_ notification: Notification) {
        guard let payload = extractNotificationPayload(notification) else {
            debugInvalidNotification(notification)
            return
        }
        
        let (message, sessionId, project) = payload
        logNotificationDetails(message: message, sessionId: sessionId, project: project)
        
        // ALWAYS clear loading state for ANY project that receives a response
        // This prevents stuck "Thinking" states when switching between projects
        clearLoadingStateIfNeeded(for: project)
        
        // Only add message to conversation if this is for the current project
        if project.path == projectStateManager.currentProject?.path {
            addMessageToConversation(message, for: project)
        }
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
        // Minimal logging - just project name
        print("📨 Response for: \(project.name)")
    }
    
    private func clearLoadingStateIfNeeded(for project: Project) {
        // Clear ALL loading states when ANY response arrives for this project
        loadingStateManager.clearLoadingState(for: project.path)
        
        // Clear waiting state to re-enable send button
        projectStateManager.updateProjectState(for: project.path) { state in
            state.isWaitingForResponse = false
        }
        
        // Clear processing state (stop button becomes send button)
        ProjectStatusManager.shared.statusFor(project).isProcessing = false
        
        // Clear from global coordinator
        LoadingStateCoordinator.shared.stopProjectLoading(project.path)
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
