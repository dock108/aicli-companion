import Foundation
@testable import AICLICompanion

/// Mock implementation of MessagePersistenceService for testing
@available(iOS 16.0, macOS 13.0, *)
class MockMessagePersistenceService: ObservableObject {
    
    // MARK: - Mock Storage
    private var mockMessages: [String: [Message]] = [:] // projectPath -> [Message]
    private var mockSessionMetadata: [String: PersistedSessionMetadata] = [:] // projectPath -> metadata
    
    // MARK: - Mock Control
    var shouldFailOperations = false
    var operationDelay: TimeInterval = 0.0
    var recordedOperations: [String] = []
    
    // MARK: - Message Persistence
    
    func saveMessage(_ message: Message, for projectPath: String) {
        recordOperation("saveMessage for \(projectPath)")
        
        if shouldFailOperations { return }
        
        executeWithDelay {
            if self.mockMessages[projectPath] == nil {
                self.mockMessages[projectPath] = []
            }
            
            // Remove existing message with same ID if it exists
            self.mockMessages[projectPath]?.removeAll { $0.id == message.id }
            
            // Add the new/updated message
            self.mockMessages[projectPath]?.append(message)
            
            // Update session metadata
            self.updateSessionMetadata(for: projectPath, with: message)
        }
    }
    
    func saveMessages(_ messages: [Message], for projectPath: String) {
        recordOperation("saveMessages (\(messages.count)) for \(projectPath)")
        
        if shouldFailOperations { return }
        
        executeWithDelay {
            self.mockMessages[projectPath] = messages
            
            if let lastMessage = messages.last {
                self.updateSessionMetadata(for: projectPath, with: lastMessage)
            }
        }
    }
    
    func loadMessages(for projectPath: String) -> [Message] {
        recordOperation("loadMessages for \(projectPath)")
        
        if shouldFailOperations { return [] }
        
        return mockMessages[projectPath] ?? []
    }
    
    func deleteMessage(withId messageId: UUID, for projectPath: String) {
        recordOperation("deleteMessage \(messageId) for \(projectPath)")
        
        if shouldFailOperations { return }
        
        executeWithDelay {
            self.mockMessages[projectPath]?.removeAll { $0.id == messageId }
        }
    }
    
    func clearMessages(for projectPath: String) {
        recordOperation("clearMessages for \(projectPath)")
        
        if shouldFailOperations { return }
        
        executeWithDelay {
            self.mockMessages[projectPath] = []
            self.mockSessionMetadata[projectPath] = nil
        }
    }
    
    func clearAllMessages() {
        recordOperation("clearAllMessages")
        
        if shouldFailOperations { return }
        
        executeWithDelay {
            self.mockMessages.removeAll()
            self.mockSessionMetadata.removeAll()
        }
    }
    
    // MARK: - Session Metadata
    
    func getSessionMetadata(for projectPath: String) -> PersistedSessionMetadata? {
        recordOperation("getSessionMetadata for \(projectPath)")
        
        if shouldFailOperations { return nil }
        
        return mockSessionMetadata[projectPath]
    }
    
    func getAllSessionMetadata() -> [PersistedSessionMetadata] {
        recordOperation("getAllSessionMetadata")
        
        if shouldFailOperations { return [] }
        
        return Array(mockSessionMetadata.values).sorted { $0.lastMessageDate > $1.lastMessageDate }
    }
    
    func deleteSessionMetadata(for projectPath: String) {
        recordOperation("deleteSessionMetadata for \(projectPath)")
        
        if shouldFailOperations { return }
        
        executeWithDelay {
            self.mockSessionMetadata[projectPath] = nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateSessionMetadata(for projectPath: String, with message: Message) {
        let messageCount = mockMessages[projectPath]?.count ?? 0
        let sessionId = message.metadata?.sessionId ?? "unknown"
        
        let metadata = PersistedSessionMetadata(
            sessionId: sessionId,
            projectId: projectPath,
            projectName: projectPath.components(separatedBy: "/").last ?? "Unknown",
            projectPath: projectPath,
            lastMessageDate: message.timestamp,
            messageCount: messageCount,
            aicliSessionId: sessionId,
            createdAt: mockSessionMetadata[projectPath]?.createdAt ?? Date()
        )
        
        mockSessionMetadata[projectPath] = metadata
    }
    
    private func executeWithDelay(_ operation: @escaping () -> Void) {
        if operationDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + operationDelay, execute: operation)
        } else {
            operation()
        }
    }
    
    private func recordOperation(_ operation: String) {
        recordedOperations.append(operation)
    }
    
    // MARK: - Mock Helpers
    
    func reset() {
        mockMessages.removeAll()
        mockSessionMetadata.removeAll()
        shouldFailOperations = false
        operationDelay = 0.0
        recordedOperations.removeAll()
    }
    
    func setMockMessages(_ messages: [Message], for projectPath: String) {
        mockMessages[projectPath] = messages
        
        if let lastMessage = messages.last {
            updateSessionMetadata(for: projectPath, with: lastMessage)
        }
    }
    
    func setMockSessionMetadata(_ metadata: PersistedSessionMetadata, for projectPath: String) {
        mockSessionMetadata[projectPath] = metadata
    }
    
    func getRecordedOperations() -> [String] {
        return recordedOperations
    }
    
    func simulateOperationFailure() {
        shouldFailOperations = true
    }
    
    func setOperationDelay(_ delay: TimeInterval) {
        operationDelay = delay
    }
    
    // MARK: - Test Data Access
    
    func getMockMessages(for projectPath: String) -> [Message] {
        return mockMessages[projectPath] ?? []
    }
    
    func getMockSessionMetadata(for projectPath: String) -> PersistedSessionMetadata? {
        return mockSessionMetadata[projectPath]
    }
    
    func getAllMockMessages() -> [String: [Message]] {
        return mockMessages
    }
}

// MARK: - Test Extensions

@available(iOS 16.0, macOS 13.0, *)
extension MockMessagePersistenceService {
    
    func addTestMessage(_ message: Message, to projectPath: String) {
        if mockMessages[projectPath] == nil {
            mockMessages[projectPath] = []
        }
        mockMessages[projectPath]?.append(message)
        updateSessionMetadata(for: projectPath, with: message)
    }
    
    func addTestMessages(_ messages: [Message], to projectPath: String) {
        mockMessages[projectPath] = messages
        if let lastMessage = messages.last {
            updateSessionMetadata(for: projectPath, with: lastMessage)
        }
    }
}