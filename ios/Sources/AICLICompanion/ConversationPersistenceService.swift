import Foundation
import SwiftUI

// MARK: - Main Conversation Persistence Service
// Uses composition pattern with specialized storage and export components

class ConversationPersistenceService: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    
    // MARK: - Composed Services
    private let storage: ConversationStorage
    private let exporter = ConversationExporter()
    
    init() {
        do {
            self.storage = try ConversationStorage()
            loadConversations()
        } catch {
            print("Failed to initialize ConversationStorage: \(error)")
            // Create a temporary storage that will fail gracefully
            self.storage = try! ConversationStorage()
        }
    }
    
    // MARK: - Conversation Management
    
    func createNewConversation(title: String? = nil, sessionId: String? = nil, workingDirectory: String? = nil) -> Conversation {
        let conversation = Conversation(
            title: title ?? "New Conversation",
            sessionId: sessionId,
            workingDirectory: workingDirectory
        )
        
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        saveConversation(conversation)
        
        return conversation
    }
    
    func addMessageToCurrentConversation(_ message: Message) {
        guard var conversation = currentConversation else {
            currentConversation = createNewConversation()
            addMessageToCurrentConversation(message)
            return
        }
        
        conversation.addMessage(message)
        
        // Update in array
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        
        currentConversation = conversation
        saveConversation(conversation)
    }
    
    func updateCurrentConversationTitle(_ title: String) {
        guard var conversation = currentConversation else { return }
        
        conversation.title = title
        conversation.updatedAt = Date()
        
        updateConversationInList(conversation)
        saveConversation(conversation)
    }
    
    func updateCurrentConversationWorkingDirectory(_ workingDirectory: String) {
        guard var conversation = currentConversation else { return }
        
        conversation.workingDirectory = workingDirectory
        conversation.updatedAt = Date()
        
        updateConversationInList(conversation)
        saveConversation(conversation)
    }
    
    func switchToConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        
        do {
            try storage.delete(id: conversation.id)
        } catch {
            print("Failed to delete conversation file: \(error)")
        }
    }
    
    // MARK: - Storage Operations
    
    private func loadConversations() {
        do {
            conversations = try storage.loadAll()
            currentConversation = conversations.first
        } catch {
            print("Failed to load conversations: \(error)")
            conversations = []
            currentConversation = nil
        }
    }
    
    private func saveConversation(_ conversation: Conversation) {
        do {
            try storage.save(conversation)
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
    
    private func updateConversationInList(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        currentConversation = conversation
    }
    
    // MARK: - Export Operations
    
    func exportConversation(_ conversation: Conversation, to format: ExportFormat) throws -> Data {
        return try exporter.export(conversation, to: format)
    }
    
    func exportConversations(_ conversations: [Conversation], to format: ExportFormat) throws -> Data {
        return try exporter.export(conversations, to: format)
    }
    
    func exportAllConversations(to format: ExportFormat) throws -> Data {
        return try exporter.export(conversations, to: format)
    }
    
    // MARK: - Statistics and Utilities
    
    func getStatistics() throws -> ConversationStatistics {
        let totalMessages = conversations.reduce(0) { $0 + $1.messages.count }
        let averageMessages = conversations.isEmpty ? 0.0 : Double(totalMessages) / Double(conversations.count)
        let oldestDate = conversations.map { $0.createdAt }.min()
        let newestDate = conversations.map { $0.createdAt }.max()
        let withToolUsage = conversations.filter { $0.metadata.hasToolUsage }.count
        let withRichContent = conversations.filter { $0.metadata.hasRichContent }.count
        let storageSize = try storage.getTotalStorageSize()
        
        return ConversationStatistics(
            totalConversations: conversations.count,
            totalMessages: totalMessages,
            averageMessagesPerConversation: averageMessages,
            oldestConversation: oldestDate,
            newestConversation: newestDate,
            conversationsWithToolUsage: withToolUsage,
            conversationsWithRichContent: withRichContent,
            totalStorageSize: storageSize
        )
    }
    
    func cleanupOldConversations(keepingRecent count: Int = 100) {
        do {
            try storage.cleanupOldConversations(keepingRecent: count)
            loadConversations() // Refresh the list
        } catch {
            print("Failed to cleanup old conversations: \(error)")
        }
    }
    
    func getStorageURL() -> URL {
        return storage.getStorageURL()
    }
    
    // MARK: - Search and Filtering
    
    func searchConversations(query: String) -> [Conversation] {
        let lowercaseQuery = query.lowercased()
        return conversations.filter { conversation in
            conversation.title.lowercased().contains(lowercaseQuery) ||
            conversation.messages.contains { message in
                message.content.lowercased().contains(lowercaseQuery)
            }
        }
    }
    
    func getConversationsWithWorkingDirectory(_ directory: String) -> [Conversation] {
        return conversations.filter { $0.workingDirectory == directory }
    }
    
    func getFavoriteConversations() -> [Conversation] {
        return conversations.filter { $0.metadata.isFavorite }
    }
    
    func getConversationsWithToolUsage() -> [Conversation] {
        return conversations.filter { $0.metadata.hasToolUsage }
    }
}