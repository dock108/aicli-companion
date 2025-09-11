import Foundation

/// Unified factory for creating test data objects across iOS and macOS
public struct MockFactory {

    // MARK: - Common Message Creation

    public static func createMessage(
        id: UUID = UUID(),
        content: String = "Test message",
        sender: MessageSender = .user,
        timestamp: Date = Date(),
        sessionId: String = "test-session-123"
    ) -> MockMessage {
        MockMessage(
            id: id,
            content: content,
            sender: sender,
            timestamp: timestamp,
            sessionId: sessionId
        )
    }

    public static func createUserMessage(
        content: String = "Hello, Claude!",
        timestamp: Date = Date(),
        id: UUID = UUID(),
        sessionId: String = "test-session-123"
    ) -> MockMessage {
        createMessage(
            id: id,
            content: content,
            sender: .user,
            timestamp: timestamp,
            sessionId: sessionId
        )
    }

    public static func createAssistantMessage(
        content: String = "Hello! How can I help you today?",
        timestamp: Date = Date(),
        id: UUID = UUID(),
        sessionId: String = "test-session-123"
    ) -> MockMessage {
        createMessage(
            id: id,
            content: content,
            sender: .assistant,
            timestamp: timestamp,
            sessionId: sessionId
        )
    }

    public static func createSystemMessage(
        content: String = "System initialized",
        timestamp: Date = Date(),
        id: UUID = UUID()
    ) -> MockMessage {
        createMessage(
            id: id,
            content: content,
            sender: .system,
            timestamp: timestamp,
            sessionId: "system"
        )
    }

    // MARK: - Session Creation

    public static func createSession(
        sessionId: String? = nil,
        deviceName: String = "Test Device",
        connectedAt: Date = Date(),
        projectPath: String = "/test/project"
    ) -> MockSession {
        MockSession(
            sessionId: sessionId ?? UUID().uuidString,
            deviceName: deviceName,
            connectedAt: connectedAt,
            projectPath: projectPath
        )
    }

    // MARK: - Conversation Creation

    public static func createConversation(
        id: UUID = UUID(),
        projectPath: String = "/test/project",
        messages: [MockMessage]? = nil,
        createdAt: Date = Date()
    ) -> MockConversation {
        MockConversation(
            id: id,
            projectPath: projectPath,
            messages: messages ?? [
                createUserMessage(),
                createAssistantMessage()
            ],
            createdAt: createdAt,
            lastModified: createdAt
        )
    }

    // MARK: - Log Entry Creation (macOS specific)

    #if os(macOS)
    public static func createLogEntry(
        level: LogLevel = .info,
        message: String = "Test log message",
        category: String = "Test"
    ) -> MockLogEntry {
        MockLogEntry(
            level: level,
            message: message,
            category: category,
            timestamp: Date()
        )
    }

    public static func createLogEntries(count: Int) -> [MockLogEntry] {
        (0..<count).map { index in
            let levels: [LogLevel] = [.debug, .info, .warning, .error]
            let level = levels[index % levels.count]
            return createLogEntry(
                level: level,
                message: "Test log message \(index + 1)"
            )
        }
    }
    #endif

    // MARK: - Batch Creation

    public static func createMessageHistory(count: Int = 10) -> [MockMessage] {
        (0..<count).map { index in
            let isUserMessage = index % 2 == 0
            return isUserMessage
                ? createUserMessage(content: "User message \(index + 1)")
                : createAssistantMessage(content: "Assistant response \(index + 1)")
        }
    }
}

// MARK: - Mock Data Types

public enum MessageSender {
    case user
    case assistant
    case system
}

public struct MockMessage {
    public let id: UUID
    public let content: String
    public let sender: MessageSender
    public let timestamp: Date
    public let sessionId: String
}

public struct MockSession {
    public let sessionId: String
    public let deviceName: String
    public let connectedAt: Date
    public let projectPath: String
}

public struct MockConversation {
    public let id: UUID
    public let projectPath: String
    public let messages: [MockMessage]
    public let createdAt: Date
    public let lastModified: Date
}

#if os(macOS)
public enum LogLevel {
    case debug
    case info
    case warning
    case error
}

public struct MockLogEntry {
    public let level: LogLevel
    public let message: String
    public let category: String
    public let timestamp: Date
}
#endif
