import Foundation
import SwiftUI

// MARK: - Session Metadata

@available(iOS 13.0, macOS 10.15, *)
struct SessionMetadata: Codable {
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

@available(iOS 13.0, macOS 10.15, *)
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

@available(iOS 13.0, macOS 10.15, *)
class MessagePersistenceService: ObservableObject {
    static let shared = MessagePersistenceService()
    
    private let documentsDirectory: URL
    private let sessionsDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    
    @Published var savedSessions: [String: SessionMetadata] = [:]
    
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
        let metadata = SessionMetadata(
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
        
        guard let data = try? Data(contentsOf: messagesFile),
              let persistedMessages = try? decoder.decode([PersistedMessage].self, from: data) else {
            return []
        }
        
        return persistedMessages.map { $0.toMessage() }
    }
    
    func getSessionMetadata(for projectId: String) -> SessionMetadata? {
        return savedSessions[projectId]
    }
    
    func clearMessages(for projectId: String) {
        let projectDir = sessionsDirectory.appendingPathComponent(sanitizeFilename(projectId))
        try? fileManager.removeItem(at: projectDir)
        savedSessions.removeValue(forKey: projectId)
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
               let metadata = try? decoder.decode(SessionMetadata.self, from: data) {
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