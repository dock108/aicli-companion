import Foundation
@testable import AICLICompanion

/// Factory for creating test data objects with realistic values
struct TestDataFactory {
    
    // MARK: - Messages
    
    static func createUserMessage(
        content: String = "Hello, Claude!",
        timestamp: Date = Date(),
        id: UUID = UUID(),
        sessionId: String = "test-session-123"
    ) -> Message {
        Message(
            id: id,
            content: content,
            sender: .user,
            timestamp: timestamp,
            type: .text,
            metadata: createMessageMetadata(sessionId: sessionId)
        )
    }
    
    static func createAssistantMessage(
        content: String = "Hello! How can I help you today?",
        timestamp: Date = Date(),
        id: UUID = UUID(),
        sessionId: String = "test-session-123"
    ) -> Message {
        Message(
            id: id,
            content: content,
            sender: .assistant,
            timestamp: timestamp,
            type: .text,
            metadata: createMessageMetadata(sessionId: sessionId)
        )
    }
    
    static func createSystemMessage(
        content: String = "System initialized",
        timestamp: Date = Date(),
        id: UUID = UUID()
    ) -> Message {
        Message(
            id: id,
            content: content,
            sender: .system,
            timestamp: timestamp,
            type: .system
        )
    }
    
    static func createCodeMessage(
        code: String = "print('Hello, World!')",
        language: String = "python",
        sessionId: String = "test-session-123"
    ) -> Message {
        let codeBlock = CodeBlockData(
            code: code,
            language: language,
            filename: nil,
            startLine: nil,
            endLine: nil
        )
        
        let richContent = RichContent(
            contentType: .codeBlock,
            data: .codeBlock(codeBlock)
        )
        
        return Message(
            content: code,
            sender: .assistant,
            type: .code,
            metadata: createMessageMetadata(sessionId: sessionId),
            richContent: richContent
        )
    }
    
    static func createToolResultMessage(
        toolName: String = "Read",
        output: String = "File content here",
        success: Bool = true,
        sessionId: String = "test-session-123"
    ) -> Message {
        let toolResult = ToolResultData(
            toolName: toolName,
            input: ["file_path": AnyCodable("/test/path")],
            output: output,
            success: success,
            error: success ? nil : "Tool execution failed",
            duration: 0.5
        )
        
        let richContent = RichContent(
            contentType: .toolResult,
            data: .toolResult(toolResult)
        )
        
        return Message(
            content: output,
            sender: .assistant,
            type: .toolResult,
            metadata: createMessageMetadata(sessionId: sessionId),
            richContent: richContent
        )
    }
    
    // MARK: - Generic Message Creation
    
    static func createTestMessage(
        content: String = "Test message",
        sender: MessageSender = .user,
        type: MessageType = .text,
        timestamp: Date = Date(),
        id: UUID = UUID(),
        metadata: AICLIMessageMetadata? = nil
    ) -> Message {
        Message(
            id: id,
            content: content,
            sender: sender,
            timestamp: timestamp,
            type: type,
            metadata: metadata
        )
    }
    
    static func createTestMetadata(
        sessionId: String = "test-session-123",
        duration: TimeInterval = 1.5,
        cost: Double? = 0.001
    ) -> AICLIMessageMetadata {
        AICLIMessageMetadata(
            sessionId: sessionId,
            duration: duration,
            cost: cost,
            tools: nil,
            queuedAt: nil,
            deliveredAt: nil,
            queuePriority: nil
        )
    }
    
    // MARK: - Message Metadata
    
    static func createMessageMetadata(
        sessionId: String = "test-session-123",
        duration: TimeInterval = 1.5,
        cost: Double? = 0.001,
        tools: [String]? = ["Read", "Write"]
    ) -> AICLIMessageMetadata {
        AICLIMessageMetadata(
            sessionId: sessionId,
            duration: duration,
            cost: cost,
            tools: tools,
            queuedAt: Date().addingTimeInterval(-2),
            deliveredAt: Date().addingTimeInterval(-1),
            queuePriority: 1
        )
    }
    
    // MARK: - WebSocket Messages
    
    static func createStreamChunk(
        content: String = "Hello",
        type: String = "content",
        isFinal: Bool = false,
        sessionId: String = "test-session-123"
    ) -> StreamChunk {
        StreamChunk(
            id: UUID().uuidString,
            type: type,
            content: content,
            isFinal: isFinal,
            metadata: StreamChunkMetadata(language: "markdown")
        )
    }
    
    static func createWebSocketMessage(
        type: WebSocketMessageType = .streamChunk,
        requestId: String? = "req-123",
        timestamp: Date = Date(),
        chunk: StreamChunk? = nil
    ) -> WebSocketMessage {
        let data: WebSocketMessage.Data
        
        if let chunk = chunk {
            data = .streamChunk(StreamChunkResponse(sessionId: "test-session-123", chunk: chunk))
        } else {
            data = .streamChunk(StreamChunkResponse(
                sessionId: "test-session-123",
                chunk: createStreamChunk()
            ))
        }
        
        return WebSocketMessage(
            type: type,
            requestId: requestId,
            timestamp: timestamp,
            data: data
        )
    }
    
    // MARK: - Server Connection
    
    static func createServerConnection(
        address: String = "localhost",
        port: Int = 3000,
        authToken: String? = nil,
        isSecure: Bool = false
    ) -> ServerConnection {
        ServerConnection(
            address: address,
            port: port,
            authToken: authToken,
            isSecure: isSecure
        )
    }
    
    // MARK: - Project Session
    
    static func createProjectSession(
        sessionId: String = "test-session-123",
        projectName: String = "Test Project",
        projectPath: String = "/test/project",
        status: String = "ready"
    ) -> ProjectSession {
        let dateFormatter = ISO8601DateFormatter()
        return ProjectSession(
            sessionId: sessionId,
            projectName: projectName,
            projectPath: projectPath,
            status: status,
            startedAt: dateFormatter.string(from: Date())
        )
    }
    
    // MARK: - AICLI Response
    
    static func createAICLIResponse(
        result: String = "Hello! How can I help you?",
        sessionId: String = "test-session-123",
        isError: Bool = false,
        duration: TimeInterval = 1500,
        cost: Double? = 0.001
    ) -> AICLIResponse {
        AICLIResponse(
            type: "conversation.result",
            subtype: "text",
            isError: isError,
            duration: duration,
            durationApiMs: duration * 0.8,
            numTurns: 1,
            result: result,
            sessionId: sessionId,
            totalCost: cost,
            usage: createUsage()
        )
    }
    
    static func createUsage(
        inputTokens: Int = 100,
        outputTokens: Int = 50
    ) -> Usage {
        Usage(
            inputTokens: inputTokens,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil,
            outputTokens: outputTokens,
            serverToolUse: nil,
            serviceTier: "default"
        )
    }
    
    // MARK: - Arrays for Testing
    
    static func createMessageHistory(count: Int = 5, sessionId: String = "test-session-123") -> [Message] {
        var messages: [Message] = []
        let baseTime = Date().addingTimeInterval(-3600) // 1 hour ago
        
        for i in 0..<count {
            let timestamp = baseTime.addingTimeInterval(TimeInterval(i * 60)) // 1 minute apart
            
            if i % 2 == 0 {
                messages.append(createUserMessage(
                    content: "User message \(i + 1)",
                    timestamp: timestamp,
                    sessionId: sessionId
                ))
            } else {
                messages.append(createAssistantMessage(
                    content: "Assistant response \(i + 1)",
                    timestamp: timestamp,
                    sessionId: sessionId
                ))
            }
        }
        
        return messages
    }
    
    static func createMixedMessageTypes(sessionId: String = "test-session-123") -> [Message] {
        let baseTime = Date().addingTimeInterval(-1800) // 30 minutes ago
        
        return [
            createUserMessage(content: "Hello", timestamp: baseTime, sessionId: sessionId),
            createAssistantMessage(content: "Hi there!", timestamp: baseTime.addingTimeInterval(30), sessionId: sessionId),
            createCodeMessage(code: "print('test')", language: "python", sessionId: sessionId),
            createToolResultMessage(toolName: "Read", output: "File content", sessionId: sessionId),
            createSystemMessage(content: "Session updated", timestamp: baseTime.addingTimeInterval(120))
        ]
    }
    
    // MARK: - Error Objects
    
    static func createNetworkError() -> AICLICompanionError {
        .networkError(URLError(.notConnectedToInternet))
    }
    
    static func createAuthError() -> AICLICompanionError {
        .authenticationFailed
    }
    
    static func createHTTPError(statusCode: Int = 500) -> AICLICompanionError {
        .httpError(statusCode)
    }
}

// MARK: - Test Project Data

extension TestDataFactory {
    struct TestProject {
        let name: String
        let path: String
        
        static let frontend = TestProject(name: "Frontend App", path: "/Users/test/frontend")
        static let backend = TestProject(name: "Backend API", path: "/Users/test/backend") 
        static let mobile = TestProject(name: "Mobile App", path: "/Users/test/mobile")
    }
}