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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastMessageDate, relativeTo: Date())
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
    
    private init() {
        // Setup directories
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        sessionsDirectory = documentsDirectory.appendingPathComponent("AICLICompanionSessions")
        
        // Create sessions directory if needed
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        
        // Configure encoder/decoder
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Load existing sessions
        loadAllSessionMetadata()
    }
    
    // MARK: - Public Methods
    
    func saveMessages(for projectId: String, messages: [Message], sessionId: String, project: Project) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
        
        // Convert messages to persisted format
        let persistedMessages = messages.map { PersistedMessage(from: $0) }
        
        // Save messages
        let messagesFile = projectDir.appendingPathComponent("\(sessionId)_messages.json")
        if let data = try? encoder.encode(persistedMessages) {
            try? data.write(to: messagesFile)
        }
        
        // Update metadata
        let metadata = PersistedSessionMetadata(
            sessionId: sessionId,
            projectId: projectId,
            projectName: project.name,
            projectPath: project.path,
            lastMessageDate: messages.last?.timestamp ?? Date(),
            messageCount: messages.count,
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
    
    private func loadAllSessionMetadata() {
        guard let projectDirs = try? fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for projectDir in projectDirs {
            let metadataFile = projectDir.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metadataFile),
               let metadata = try? decoder.decode(PersistedSessionMetadata.self, from: data) {
                savedSessions[metadata.projectId] = metadata
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