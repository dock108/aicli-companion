import Foundation
import SwiftUI

// MARK: - Session Metadata

@available(iOS 16.0, macOS 13.0, *)
struct PersistedSessionMetadata: Codable {
    let sessionId: String
    let projectId: String
    let projectName: String
    let projectPath: String
    let lastMessageDate: Date
    let messageCount: Int
    let aicliSessionId: String?
    let createdAt: Date
    
    var formattedLastUsed: String {
        if #available(macOS 10.15, iOS 13.0, *) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: lastMessageDate, relativeTo: Date())
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: lastMessageDate)
        }
    }
}

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
    
    @Published var savedSessions: [String: PersistedSessionMetadata] = [:]
    private var isInitialized = false
    
    private init() {
        // Setup directories
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        sessionsDirectory = documentsDirectory.appendingPathComponent("AICLICompanionSessions")
        
        // Create sessions directory if needed
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        
        // Configure encoder/decoder
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Load metadata asynchronously to avoid blocking UI
        Task {
            await loadAllSessionMetadataAsync()
        }
    }
    
    // MARK: - Public Methods
    
    /// WhatsApp/iMessage pattern: Simple append single message to conversation
    func appendMessage(_ message: Message, to projectId: String, sessionId: String, project: Project) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        let messagesFile = projectDir.appendingPathComponent("\(sessionId)_messages.json")
        
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
            
            // Update metadata
            updateMetadata(for: projectId, sessionId: sessionId, project: project, messageCount: allMessages.count, lastMessage: message)
        } else {
            print("📝 MessagePersistence: Message already exists, skipping append")
        }
    }
    
    func saveMessages(for projectId: String, messages: [Message], sessionId: String, project: Project) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        let messagesFile = projectDir.appendingPathComponent("\(sessionId)_messages.json")
        
        // CRITICAL FIX: Load existing messages first to preserve conversation history
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
        
        // Update metadata with complete conversation info
        let metadata = PersistedSessionMetadata(
            sessionId: sessionId,
            projectId: projectId,
            projectName: project.name,
            projectPath: project.path,
            lastMessageDate: allMessages.last?.timestamp ?? Date(),
            messageCount: allMessages.count, // Use complete message count, not just new ones
            aicliSessionId: sessionId,
            createdAt: savedSessions[projectId]?.createdAt ?? Date()
        )
        
        let metadataFile = projectDir.appendingPathComponent("metadata.json")
        if let data = try? encoder.encode(metadata) {
            try? data.write(to: metadataFile)
            savedSessions[projectId] = metadata
        }
    }
    
    func loadMessages(for projectId: String, sessionId: String) -> [Message] {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        let messagesFile = projectDir.appendingPathComponent("\(sessionId)_messages.json")
        
        print("🗂️ MessagePersistence: Loading messages for project '\(projectId)', session '\(sessionId)'")
        print("   - Messages file path: \(messagesFile.path)")
        print("   - File exists: \(fileManager.fileExists(atPath: messagesFile.path))")
        
        guard fileManager.fileExists(atPath: messagesFile.path) else {
            print("❌ MessagePersistence: Messages file not found for project '\(projectId)'")
            return []
        }
        
        do {
            let data = try Data(contentsOf: messagesFile)
            print("🗂️ MessagePersistence: Read \(data.count) bytes from messages file for '\(projectId)'")
            
            let persistedMessages = try decoder.decode([PersistedMessage].self, from: data)
            print("🗂️ MessagePersistence: Successfully decoded \(persistedMessages.count) messages for '\(projectId)'")
            
            let messages = persistedMessages.map { $0.toMessage() }
            print("🗂️ MessagePersistence: Converted to \(messages.count) Message objects for '\(projectId)'")
            
            return messages
        } catch {
            print("❌ MessagePersistence: Failed to load messages for project '\(projectId)': \(error)")
            print("❌ MessagePersistence: Error details: \(error.localizedDescription)")
            
            // Try to move corrupted file to backup location
            let backupFile = messagesFile.appendingPathExtension("corrupted.\(Date().timeIntervalSince1970)")
            try? fileManager.moveItem(at: messagesFile, to: backupFile)
            print("🗂️ MessagePersistence: Moved corrupted file to: \(backupFile.path)")
            
            return []
        }
    }
    
    func getSessionMetadata(for projectId: String) -> PersistedSessionMetadata? {
        guard let metadata = savedSessions[projectId] else {
            print("🗂️ MessagePersistence: No session metadata found for project '\(projectId)'")
            return nil
        }
        
        // Validate session metadata integrity
        if !isValidSessionMetadata(metadata, for: projectId) {
            print("❌ MessagePersistence: Invalid session metadata for project '\(projectId)', removing from cache")
            savedSessions.removeValue(forKey: projectId)
            return nil
        }
        
        return metadata
    }
    
    private func isValidSessionMetadata(_ metadata: PersistedSessionMetadata, for projectId: String) -> Bool {
        print("🗂️ MessagePersistence: Validating session metadata for '\(projectId)'")
        
        // Check basic metadata fields
        guard !metadata.sessionId.isEmpty else {
            print("❌ MessagePersistence: Empty session ID for '\(projectId)'")
            return false
        }
        
        guard !metadata.projectName.isEmpty else {
            print("❌ MessagePersistence: Empty project name for '\(projectId)'")
            return false
        }
        
        guard !metadata.projectPath.isEmpty else {
            print("❌ MessagePersistence: Empty project path for '\(projectId)'")
            return false
        }
        
        // Check if metadata file exists
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        let metadataFile = projectDir.appendingPathComponent("metadata.json")
        
        guard fileManager.fileExists(atPath: metadataFile.path) else {
            print("❌ MessagePersistence: Metadata file missing for '\(projectId)' at: \(metadataFile.path)")
            return false
        }
        
        // If aicliSessionId exists, check if messages file exists
        if let aicliSessionId = metadata.aicliSessionId {
            let messagesFile = projectDir.appendingPathComponent("\(aicliSessionId)_messages.json")
            if !fileManager.fileExists(atPath: messagesFile.path) {
                print("❌ MessagePersistence: Messages file missing for '\(projectId)' session '\(aicliSessionId)' at: \(messagesFile.path)")
                return false
            }
        }
        
        print("✅ MessagePersistence: Session metadata validation passed for '\(projectId)'")
        return true
    }
    
    func clearMessages(for projectId: String) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        try? fileManager.removeItem(at: projectDir)
        savedSessions.removeValue(forKey: projectId)
    }
    
    /// Helper method to update metadata after message operations
    private func updateMetadata(for projectId: String, sessionId: String, project: Project, messageCount: Int, lastMessage: Message) {
        let metadata = PersistedSessionMetadata(
            sessionId: sessionId,
            projectId: projectId,
            projectName: project.name,
            projectPath: project.path,
            lastMessageDate: lastMessage.timestamp,
            messageCount: messageCount,
            aicliSessionId: sessionId,
            createdAt: savedSessions[projectId]?.createdAt ?? Date()
        )
        
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        let metadataFile = projectDir.appendingPathComponent("metadata.json")
        
        if let data = try? encoder.encode(metadata) {
            try? data.write(to: metadataFile)
            savedSessions[projectId] = metadata
        }
    }
    
    func updateSessionMetadata(for projectId: String, aicliSessionId: String) {
        guard let metadata = savedSessions[projectId] else {
            print("❌ MessagePersistence: No metadata to update for project '\(projectId)'")
            return
        }
        
        // Create new metadata with updated AICLI session ID
        let updatedMetadata = PersistedSessionMetadata(
            sessionId: metadata.sessionId,
            projectId: metadata.projectId,
            projectName: metadata.projectName,
            projectPath: metadata.projectPath,
            lastMessageDate: metadata.lastMessageDate,
            messageCount: metadata.messageCount,
            aicliSessionId: aicliSessionId,
            createdAt: metadata.createdAt
        )
        savedSessions[projectId] = updatedMetadata
        
        // Save to disk
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        let metadataFile = projectDir.appendingPathComponent("metadata.json")
        
        if let data = try? encoder.encode(updatedMetadata) {
            try? data.write(to: metadataFile)
            print("✅ MessagePersistence: Updated AICLI session ID to '\(aicliSessionId)' for project '\(projectId)'")
        } else {
            print("❌ MessagePersistence: Failed to save updated metadata for project '\(projectId)'")
        }
    }
    
    func archiveCurrentSession(for projectId: String) {
        guard let metadata = savedSessions[projectId] else { return }
        
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        let archiveDir = projectDir.appendingPathComponent("archive")
        try? fileManager.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        
        // Move current session to archive
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let archiveName = "\(metadata.sessionId)_\(timestamp)"
        
        let currentMessagesFile = projectDir.appendingPathComponent("\(metadata.sessionId)_messages.json")
        let archiveMessagesFile = archiveDir.appendingPathComponent("\(archiveName)_messages.json")
        
        try? fileManager.moveItem(at: currentMessagesFile, to: archiveMessagesFile)
        
        // Save archived metadata
        let archiveMetadataFile = archiveDir.appendingPathComponent("\(archiveName)_metadata.json")
        if let data = try? encoder.encode(metadata) {
            try? data.write(to: archiveMetadataFile)
        }
    }
    
    func hasSession(for projectId: String) -> Bool {
        return savedSessions[projectId] != nil
    }
    
    // MARK: - Private Methods
    
    private func loadAllSessionMetadataAsync() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                print("🗂️ MessagePersistence: Loading all session metadata from disk")
                
                guard let projectDirs = try? self.fileManager.contentsOfDirectory(at: self.sessionsDirectory, includingPropertiesForKeys: nil) else {
                    print("   ❌ Failed to list sessions directory")
                    continuation.resume()
                    return
                }
                
                var loadedSessions: [String: PersistedSessionMetadata] = [:]
                
                for projectDir in projectDirs {
                    let metadataFile = projectDir.appendingPathComponent("metadata.json")
                    if let data = try? Data(contentsOf: metadataFile),
                       let metadata = try? self.decoder.decode(PersistedSessionMetadata.self, from: data) {
                        // Store by projectPath for consistency with getSessionMetadata
                        loadedSessions[metadata.projectPath] = metadata
                        print("   ✅ Loaded metadata for project: \(metadata.projectName) - Last message: \(metadata.formattedLastUsed)")
                    }
                }
                
                print("   📊 Loaded metadata for \(loadedSessions.count) projects")
                
                // Update on main thread
                DispatchQueue.main.async {
                    self.savedSessions = loadedSessions
                    self.isInitialized = true
                    continuation.resume()
                }
            }
        }
    }
    
    private func sanitizeFilename(_ filename: String) -> String {
        return filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
