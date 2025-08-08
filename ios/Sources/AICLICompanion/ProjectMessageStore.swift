import Foundation

// MARK: - Project Message Storage Models

struct ProjectMessageStore: Codable {
    let projectId: UUID
    let projectName: String
    let projectPath: String
    let sessionId: String?
    var messages: [Message]
    let createdAt: Date
    var lastUpdated: Date
    let metadata: ProjectSessionMetadata

    init(projectId: UUID, projectName: String, projectPath: String, sessionId: String? = nil) {
        self.projectId = projectId
        self.projectName = projectName
        self.projectPath = projectPath
        self.sessionId = sessionId
        self.messages = []
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.metadata = ProjectSessionMetadata()
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
        lastUpdated = Date()
    }

    mutating func clearMessages() {
        messages.removeAll()
        lastUpdated = Date()
    }

    var messageCount: Int {
        messages.count
    }

    var hasMessages: Bool {
        !messages.isEmpty
    }
}

struct ProjectSessionMetadata: Codable {
    var totalMessages: Int = 0
    var userMessages: Int = 0
    var claudeMessages: Int = 0
    var lastMessageDate: Date?
    var totalTokensUsed: Int = 0
    var totalCost: Double = 0.0
    var hasToolUsage: Bool = false
    var hasErrors: Bool = false
    var continuationCount: Int = 0

    mutating func updateFromMessages(_ messages: [Message]) {
        totalMessages = messages.count
        userMessages = messages.filter { $0.sender == .user }.count
        claudeMessages = messages.filter { $0.sender == .assistant }.count
        lastMessageDate = messages.last?.timestamp
        hasToolUsage = messages.contains { $0.type == .toolUse || $0.type == .toolResult }
        hasErrors = messages.contains { $0.type == .error }
    }
}

// MARK: - Session Continuation Options

enum SessionContinuationChoice {
    case continueSession
    case startFresh
    case viewHistory
    case cancel
}

struct SessionContinuationInfo {
    let projectName: String
    let messageCount: Int
    let lastMessageDate: Date
    let sessionDuration: TimeInterval

    var formattedLastMessageDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastMessageDate, relativeTo: Date())
    }

    var formattedDuration: String {
        let hours = Int(sessionDuration) / 3600
        let minutes = (Int(sessionDuration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Storage Configuration

struct ProjectMessageStorageConfig {
    static let maxMessagesPerProject = 1000
    static let messageRetentionDays = 30
    static let autoSaveInterval: TimeInterval = 5.0
    static let storageVersion = 1
}

// MARK: - Project Extension

extension Project {
    var storageId: UUID {
        // Generate stable UUID from project path for consistent storage
        let namespace = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        return UUID(hashing: path, namespace: namespace)
    }
}

// MARK: - UUID Extension for Namespace-based Generation

extension UUID {
    init(hashing string: String, namespace: UUID) {
        let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let stringData = string.data(using: .utf8)!

        // Create a mutable array for the UUID bytes
        var uuidBytes = [UInt8](repeating: 0, count: 16)

        // Hash the string with namespace
        for (index, byte) in namespaceBytes.enumerated() {
            uuidBytes[index] = byte
        }

        stringData.withUnsafeBytes { bytes in
            for (index, byte) in bytes.enumerated() {
                uuidBytes[index % 16] ^= byte
            }
        }

        // Set version (5) and variant bits
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50  // Version 5
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80  // Variant 10

        // Create UUID from bytes
        let uuid = uuidBytes.withUnsafeBytes { bytes in
            return bytes.bindMemory(to: uuid_t.self).baseAddress!.pointee
        }

        self = UUID(uuid: uuid)
    }
}
