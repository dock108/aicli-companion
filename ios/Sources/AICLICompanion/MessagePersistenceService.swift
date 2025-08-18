import Foundation
import SwiftUI

// MARK: - Persisted Message

@available(iOS 16.0, macOS 13.0, *)
struct PersistedMessage: Codable {
    let id: String
    let content: String
    let sender: MessageSender
    let type: MessageType
    let timestamp: Date
    let metadata: AICLIMessageMetadata?
    
    init(from message: Message) {
        self.id = message.id.uuidString
        self.content = message.content
        self.sender = message.sender
        self.type = message.type
        self.timestamp = message.timestamp
        self.metadata = message.metadata
    }
    
    func toMessage() -> Message {
        return Message(
            id: UUID(uuidString: id) ?? UUID(),
            content: content,
            sender: sender,
            timestamp: timestamp,
            type: type,
            metadata: metadata
        )
    }
}

// MARK: - Message Persistence Service

@available(iOS 16.0, macOS 13.0, *)
class MessagePersistenceService: ObservableObject {
    static let shared = MessagePersistenceService()
    
    private let documentsDirectory: URL
    private let sessionsDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let logger = LoggingManager.shared
    
    private init() {
        // Setup directories
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        sessionsDirectory = documentsDirectory.appendingPathComponent("AICLICompanionSessions")
        
        // Create sessions directory if needed
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        
        // Configure encoder/decoder
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public Methods
    
    /// Simple append single message to conversation
    func appendMessage(_ message: Message, to projectPath: String) {
        // Filter out empty messages
        guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("📝 MessagePersistence: Skipping empty message")
            return
        }
        
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectPath))
        try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        let messagesFile = projectDir.appendingPathComponent("messages.json")
        
        // Load existing messages (or empty array if none)
        var allMessages: [Message] = []
        if fileManager.fileExists(atPath: messagesFile.path) {
            do {
                let existingData = try Data(contentsOf: messagesFile)
                let existingPersisted = try decoder.decode([PersistedMessage].self, from: existingData)
                allMessages = existingPersisted.map { $0.toMessage() }
            } catch {
                print("⚠️ MessagePersistence: Failed to load existing messages: \(error)")
                allMessages = []
            }
        }
        
        // Simple append (check for duplicate by ID)
        if !allMessages.contains(where: { $0.id == message.id }) {
            allMessages.append(message)
            allMessages.sort { $0.timestamp < $1.timestamp }
            
            // Save updated conversation
            let persistedMessages = allMessages.map { PersistedMessage(from: $0) }
            if let data = try? encoder.encode(persistedMessages) {
                try? data.write(to: messagesFile)
                print("📝 MessagePersistence: Appended message, total: \(allMessages.count)")
            }
        } else {
            print("📝 MessagePersistence: Message already exists, skipping append")
        }
    }
    
    func saveMessages(for projectPath: String, messages: [Message]) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectPath))
        try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        let messagesFile = projectDir.appendingPathComponent("messages.json")
        
        // Load existing messages first to preserve conversation history
        var allMessages: [Message] = []
        
        if fileManager.fileExists(atPath: messagesFile.path) {
            // Load existing messages from disk
            do {
                let existingData = try Data(contentsOf: messagesFile)
                let existingPersisted = try decoder.decode([PersistedMessage].self, from: existingData)
                let existingMessages = existingPersisted.map { $0.toMessage() }
                
                print("🗂️ MessagePersistence: Loaded \(existingMessages.count) existing messages for merge")
                allMessages = existingMessages
            } catch {
                print("⚠️ MessagePersistence: Failed to load existing messages, starting fresh: \(error)")
                allMessages = []
            }
        }
        
        // Merge new messages with existing ones, avoiding duplicates
        let existingIds = Set(allMessages.map { $0.id })
        let newMessages = messages.filter { !existingIds.contains($0.id) }
        
        if !newMessages.isEmpty {
            allMessages.append(contentsOf: newMessages)
            // Sort by timestamp to maintain chronological order
            allMessages.sort { $0.timestamp < $1.timestamp }
            print("🗂️ MessagePersistence: Added \(newMessages.count) new messages, total: \(allMessages.count)")
        } else {
            print("🗂️ MessagePersistence: No new messages to add (all \(messages.count) were duplicates)")
        }
        
        // Convert all messages to persisted format
        let persistedMessages = allMessages.map { PersistedMessage(from: $0) }
        
        // Save complete conversation (not just new messages)
        if let data = try? encoder.encode(persistedMessages) {
            try? data.write(to: messagesFile)
            print("🗂️ MessagePersistence: Saved complete conversation (\(allMessages.count) messages) to disk")
        }
    }
    
    func loadMessages(for projectPath: String) -> [Message] {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectPath))
        let messagesFile = projectDir.appendingPathComponent("messages.json")
        
        print("🗂️ MessagePersistence: Loading messages for project '\(projectPath)'")
        print("   - Messages file path: \(messagesFile.path)")
        print("   - File exists: \(fileManager.fileExists(atPath: messagesFile.path))")
        
        guard fileManager.fileExists(atPath: messagesFile.path) else {
            print("❌ MessagePersistence: Messages file not found for project '\(projectPath)'")
            return []
        }
        
        do {
            let data = try Data(contentsOf: messagesFile)
            print("🗂️ MessagePersistence: Read \(data.count) bytes from messages file for '\(projectPath)'")
            
            let persistedMessages = try decoder.decode([PersistedMessage].self, from: data)
            print("🗂️ MessagePersistence: Successfully decoded \(persistedMessages.count) messages for '\(projectPath)'")
            
            let messages = persistedMessages.map { $0.toMessage() }
            print("🗂️ MessagePersistenceService: Converted to \(messages.count) Message objects for '\(projectPath)'")
            
            // Ensure chronological order (defensive)
            let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
            print("🗂️ MessagePersistenceService: Messages sorted chronologically")
            
            return sortedMessages
        } catch {
            print("❌ MessagePersistence: Failed to load messages for project '\(projectPath)': \(error)")
            print("❌ MessagePersistence: Error details: \(error.localizedDescription)")
            
            // Try to move corrupted file to backup location
            let backupFile = messagesFile.appendingPathExtension("corrupted.\(Date().timeIntervalSince1970)")
            try? fileManager.moveItem(at: messagesFile, to: backupFile)
            print("🗂️ MessagePersistence: Moved corrupted file to: \(backupFile.path)")
            
            return []
        }
    }
    
    func clearMessages(for projectPath: String) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectPath))
        try? fileManager.removeItem(at: projectDir)
    }
    
    func hasMessages(for projectPath: String) -> Bool {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectPath))
        let messagesFile = projectDir.appendingPathComponent("messages.json")
        return fileManager.fileExists(atPath: messagesFile.path)
    }
    
    // MARK: - Private Methods
    
    private func sanitizeFilename(_ filename: String) -> String {
        return filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}