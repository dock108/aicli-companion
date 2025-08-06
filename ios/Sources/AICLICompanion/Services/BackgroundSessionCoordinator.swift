import Foundation
import Combine

/// Manages session IDs and messages in the background, independent of view lifecycle
@available(iOS 16.0, macOS 13.0, *)
class BackgroundSessionCoordinator: ObservableObject {
    static let shared = BackgroundSessionCoordinator()
    
    // MARK: - Properties
    
    /// Pending messages awaiting session IDs, keyed by project path
    private var pendingMessages: [String: PendingMessageSet] = [:]
    
    /// Lock for thread-safe access to pending messages
    private let pendingMessagesLock = NSLock()
    
    /// WebSocket service reference
    private let webSocketService = WebSocketService.shared
    
    /// Message persistence service
    private let persistenceService = MessagePersistenceService.shared
    
    /// Session manager
    private let sessionManager = ChatSessionManager.shared
    
    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Types
    
    struct PendingMessageSet {
        let projectPath: String
        let projectName: String
        var messages: [Message]
        let createdAt: Date
        var requestId: String? // Track the request that will bring the session ID
    }
    
    // MARK: - Initialization
    
    private init() {
        setupWebSocketHandlers()
    }
    
    // MARK: - Public Methods
    
    /// Store messages that don't yet have a session ID
    func storePendingMessages(for project: Project, messages: [Message], requestId: String? = nil) {
        pendingMessagesLock.lock()
        defer { pendingMessagesLock.unlock() }
        
        print("📋 BackgroundSessionCoordinator: Storing \(messages.count) pending messages for project '\(project.name)'")
        
        let pendingSet = PendingMessageSet(
            projectPath: project.path,
            projectName: project.name,
            messages: messages,
            createdAt: Date(),
            requestId: requestId
        )
        
        pendingMessages[project.path] = pendingSet
    }
    
    /// Check if there are pending messages for a project
    func hasPendingMessages(for projectPath: String) -> Bool {
        pendingMessagesLock.lock()
        defer { pendingMessagesLock.unlock() }
        
        return pendingMessages[projectPath] != nil
    }
    
    /// Get pending messages for a project (and remove them from pending)
    func retrievePendingMessages(for projectPath: String) -> [Message]? {
        pendingMessagesLock.lock()
        defer { pendingMessagesLock.unlock() }
        
        guard let pendingSet = pendingMessages[projectPath] else { return nil }
        
        // Remove from pending since we're retrieving them
        pendingMessages.removeValue(forKey: projectPath)
        
        print("📋 BackgroundSessionCoordinator: Retrieved \(pendingSet.messages.count) pending messages for project")
        return pendingSet.messages
    }
    
    // MARK: - Private Methods
    
    private func setupWebSocketHandlers() {
        // Listen for ALL claudeResponse messages, not just ones for active views
        webSocketService.setGlobalMessageHandler(for: .claudeResponse) { [weak self] message in
            self?.handleClaudeResponse(message)
        }
        
        // Also listen for conversationResult messages
        webSocketService.setGlobalMessageHandler(for: .conversationResult) { [weak self] message in
            self?.handleConversationResult(message)
        }
    }
    
    private func handleClaudeResponse(_ message: WebSocketMessage) {
        guard case .claudeResponse(let response) = message.data,
              let sessionId = response.sessionId,
              !sessionId.isEmpty else {
            return
        }
        
        print("🎯 BackgroundSessionCoordinator: Received Claude response with session ID: \(sessionId)")
        
        // Check if this response matches any pending messages
        processPendingMessagesWithSessionId(sessionId, requestId: message.requestId)
    }
    
    private func handleConversationResult(_ message: WebSocketMessage) {
        guard case .conversationResult(let result) = message.data,
              let sessionId = result.claudeSessionId ?? result.sessionId,
              !sessionId.isEmpty else {
            return
        }
        
        print("🎯 BackgroundSessionCoordinator: Received conversation result with session ID: \(sessionId)")
        
        // Process any pending messages
        processPendingMessagesWithSessionId(sessionId, requestId: message.requestId)
    }
    
    private func processPendingMessagesWithSessionId(_ sessionId: String, requestId: String?) {
        pendingMessagesLock.lock()
        
        // Find pending messages that match this request or don't have a request ID
        let matchingProjects = pendingMessages.filter { (projectPath, pendingSet) in
            // Match by request ID if available, otherwise process all pending
            return pendingSet.requestId == nil || pendingSet.requestId == requestId
        }
        
        pendingMessagesLock.unlock()
        
        // Process each matching project's messages
        for (projectPath, pendingSet) in matchingProjects {
            print("📋 BackgroundSessionCoordinator: Processing pending messages for project at: \(projectPath)")
            
            // Create project object
            let project = Project(
                name: pendingSet.projectName,
                path: pendingSet.projectPath,
                type: "folder"
            )
            
            // Save messages with the newly received session ID
            persistenceService.saveMessages(
                for: projectPath,
                messages: pendingSet.messages,
                sessionId: sessionId,
                project: project
            )
            
            print("✅ BackgroundSessionCoordinator: Saved \(pendingSet.messages.count) messages with session ID: \(sessionId)")
            
            // Remove from pending
            pendingMessagesLock.lock()
            pendingMessages.removeValue(forKey: projectPath)
            pendingMessagesLock.unlock()
            
            // Create session in session manager for future use
            sessionManager.createSessionFromClaudeResponse(
                sessionId: sessionId,
                for: project
            ) { result in
                switch result {
                case .success:
                    print("✅ BackgroundSessionCoordinator: Created session for future use")
                case .failure(let error):
                    print("❌ BackgroundSessionCoordinator: Failed to create session: \(error)")
                }
            }
        }
    }
    
    /// Clean up old pending messages (called periodically)
    func cleanupOldPendingMessages() {
        pendingMessagesLock.lock()
        defer { pendingMessagesLock.unlock() }
        
        let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour
        
        pendingMessages = pendingMessages.filter { (_, pendingSet) in
            return pendingSet.createdAt > cutoffDate
        }
    }
}
