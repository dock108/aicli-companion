import SwiftUI
import Combine

/// Manages message CRUD operations and persistence
@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatMessageManager: ObservableObject {
    // MARK: - Dependencies
    private let persistenceService: MessagePersistenceService
    
    // MARK: - Published Properties
    @Published var messages: [Message] = []
    
    // MARK: - Initialization
    init(persistenceService: MessagePersistenceService = .shared) {
        self.persistenceService = persistenceService
    }
    
    // MARK: - Message Operations
    
    func loadMessages(for project: Project) {
        // Load messages from persistence
        print("📝 MessageManager: Loading messages for project: \(project.name)")
        
        // Clear current messages first
        messages.removeAll()
        
        // Load project-specific messages
        let loadedMessages = persistenceService.loadMessages(for: project.path)
        messages = loadedMessages
        
        print("📝 MessageManager: Loaded \(messages.count) messages for project: \(project.name)")
    }
    
    func saveMessages(for project: Project) {
        // Save messages to persistence
        print("📝 MessageManager: Saving messages for project: \(project.name)")
        
        // Save all messages at once
        persistenceService.saveMessages(for: project.path, messages: messages)
        
        print("📝 MessageManager: Saved \(messages.count) messages for project: \(project.name)")
    }
    
    func appendMessage(_ message: Message, for project: Project? = nil) {
        print("📝 MessageManager: Appending message: \(message.content.prefix(50))...")
        
        // Filter out empty messages
        guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("📝 MessageManager: Skipping empty message")
            return
        }
        
        // Check for duplicates before adding
        guard !messages.contains(where: { $0.id == message.id }) else {
            print("📝 MessageManager: Message already exists, skipping duplicate")
            return
        }
        
        messages.append(message)
        
        // If project is provided, also save to persistence immediately
        if let project = project {
            persistenceService.appendMessage(message, to: project.path)
        }
    }
    
    func clearMessages() {
        print("📝 MessageManager: Clearing all messages")
        messages.removeAll()
    }
    
    func syncNewMessagesIfNeeded(for project: Project) {
        print("📝 MessageManager: Syncing messages for project: \(project.name)")
        // TODO: Implement message sync logic
    }
    
    // MARK: - Message Validation
    
    func shouldDisplayMessage(_ message: Message) -> Bool {
        return MessageValidator.shouldDisplayMessage(message)
    }
}
