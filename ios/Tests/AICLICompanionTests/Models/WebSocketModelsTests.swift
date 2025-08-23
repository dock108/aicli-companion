import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class WebSocketModelsTests: XCTestCase {
    
    // MARK: - WebSocketMessage Tests
    
    func testWebSocketMessageInitialization() {
        let timestamp = Date()
        let message = WebSocketMessage(
            type: .ask,
            data: .ask(AskRequest(message: "Hello", options: nil)),
            id: "msg-001",
            requestId: "req-001",
            error: nil,
            timestamp: timestamp
        )
        
        XCTAssertEqual(message.type, .ask)
        XCTAssertNotNil(message.data)
        XCTAssertEqual(message.id, "msg-001")
        XCTAssertEqual(message.requestId, "req-001")
        XCTAssertNil(message.error)
        XCTAssertEqual(message.timestamp, timestamp)
    }
    
    func testWebSocketMessageWithError() {
        let message = WebSocketMessage(
            type: .error,
            data: nil,
            id: nil,
            requestId: nil,
            error: "Something went wrong"
        )
        
        XCTAssertEqual(message.type, .error)
        XCTAssertNil(message.data)
        XCTAssertEqual(message.error, "Something went wrong")
    }
    
    func testWebSocketMessageCodable() throws {
        let original = WebSocketMessage(
            type: .ping,
            data: .ping(PingRequest()),
            id: "test-id",
            requestId: "test-req",
            error: nil,
            timestamp: Date()
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WebSocketMessage.self, from: data)
        
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.requestId, original.requestId)
    }
    
    // MARK: - WebSocketMessageType Tests
    
    func testWebSocketMessageTypeRawValues() {
        // Request types
        XCTAssertEqual(WebSocketMessageType.ask.rawValue, "ask")
        XCTAssertEqual(WebSocketMessageType.streamStart.rawValue, "stream_start")
        XCTAssertEqual(WebSocketMessageType.streamSend.rawValue, "stream_send")
        XCTAssertEqual(WebSocketMessageType.streamClose.rawValue, "stream_close")
        XCTAssertEqual(WebSocketMessageType.permission.rawValue, "permission")
        XCTAssertEqual(WebSocketMessageType.ping.rawValue, "ping")
        XCTAssertEqual(WebSocketMessageType.subscribe.rawValue, "subscribe")
        XCTAssertEqual(WebSocketMessageType.setWorkingDirectory.rawValue, "set_working_directory")
        XCTAssertEqual(WebSocketMessageType.claudeCommand.rawValue, "claude_command")
        XCTAssertEqual(WebSocketMessageType.getMessageHistory.rawValue, "get_message_history")
        XCTAssertEqual(WebSocketMessageType.acknowledgeMessages.rawValue, "acknowledge_messages")
        XCTAssertEqual(WebSocketMessageType.clearChat.rawValue, "clear_chat")
        
        // Response types
        XCTAssertEqual(WebSocketMessageType.welcome.rawValue, "welcome")
        XCTAssertEqual(WebSocketMessageType.askResponse.rawValue, "ask_response")
        XCTAssertEqual(WebSocketMessageType.streamStarted.rawValue, "stream_started")
        XCTAssertEqual(WebSocketMessageType.streamData.rawValue, "stream_data")
        XCTAssertEqual(WebSocketMessageType.streamToolUse.rawValue, "stream_tool_use")
        XCTAssertEqual(WebSocketMessageType.streamChunk.rawValue, "stream_chunk")
        XCTAssertEqual(WebSocketMessageType.permissionRequest.rawValue, "permission_request")
        XCTAssertEqual(WebSocketMessageType.streamComplete.rawValue, "stream_complete")
        XCTAssertEqual(WebSocketMessageType.error.rawValue, "error")
        XCTAssertEqual(WebSocketMessageType.sessionStatus.rawValue, "session_status")
        XCTAssertEqual(WebSocketMessageType.pong.rawValue, "pong")
        XCTAssertEqual(WebSocketMessageType.subscribed.rawValue, "subscribed")
        XCTAssertEqual(WebSocketMessageType.systemInit.rawValue, "system_init")
        XCTAssertEqual(WebSocketMessageType.assistantMessage.rawValue, "assistant_message")
        XCTAssertEqual(WebSocketMessageType.toolUse.rawValue, "tool_use")
        XCTAssertEqual(WebSocketMessageType.toolResult.rawValue, "tool_result")
        XCTAssertEqual(WebSocketMessageType.conversationResult.rawValue, "conversation_result")
        XCTAssertEqual(WebSocketMessageType.workingDirectorySet.rawValue, "working_directory_set")
        XCTAssertEqual(WebSocketMessageType.claudeCommandResponse.rawValue, "claude_command_response")
        XCTAssertEqual(WebSocketMessageType.messageHistory.rawValue, "message_history")
        XCTAssertEqual(WebSocketMessageType.messagesAcknowledged.rawValue, "messages_acknowledged")
        XCTAssertEqual(WebSocketMessageType.chatCleared.rawValue, "chat_cleared")
        XCTAssertEqual(WebSocketMessageType.progress.rawValue, "progress")
    }
    
    // MARK: - Request Model Tests
    
    func testAskRequest() {
        let options = AskOptions(includeHistory: true)
        let request = AskRequest(message: "What is the weather?", options: options)
        
        XCTAssertEqual(request.message, "What is the weather?")
        XCTAssertNotNil(request.options)
        XCTAssertTrue(request.options?.includeHistory ?? false)
    }
    
    func testStreamStartRequest() {
        let options = StreamOptions(includeHistory: false)
        let request = StreamStartRequest(message: "Start streaming", options: options)
        
        XCTAssertEqual(request.message, "Start streaming")
        XCTAssertNotNil(request.options)
        XCTAssertFalse(request.options?.includeHistory ?? true)
    }
    
    func testStreamSendRequest() {
        let request = StreamSendRequest(message: "Continue streaming")
        XCTAssertEqual(request.message, "Continue streaming")
    }
    
    func testPermissionResponse() {
        let response = PermissionResponse(response: "approved", requestId: "perm-001")
        
        XCTAssertEqual(response.response, "approved")
        XCTAssertEqual(response.requestId, "perm-001")
    }
    
    func testStreamCloseRequest() {
        let request = StreamCloseRequest(reason: "User cancelled")
        XCTAssertEqual(request.reason, "User cancelled")
        
        let requestNoReason = StreamCloseRequest(reason: nil)
        XCTAssertNil(requestNoReason.reason)
    }
    
    func testSubscribeRequest() {
        let request = SubscribeRequest(events: ["message", "status", "error"])
        
        XCTAssertEqual(request.events.count, 3)
        XCTAssertTrue(request.events.contains("message"))
        XCTAssertTrue(request.events.contains("status"))
        XCTAssertTrue(request.events.contains("error"))
    }
    
    func testSetWorkingDirectoryRequest() {
        let request = SetWorkingDirectoryRequest(path: "/Users/test/project")
        XCTAssertEqual(request.path, "/Users/test/project")
    }
    
    func testClaudeCommandRequest() {
        let request = ClaudeCommandRequest(
            command: "run",
            args: ["--verbose", "--output", "file.txt"]
        )
        
        XCTAssertEqual(request.command, "run")
        XCTAssertNotNil(request.args)
        XCTAssertEqual(request.args?.count, 3)
        XCTAssertEqual(request.args?[0], "--verbose")
    }
    
    func testGetMessageHistoryRequest() {
        let request = GetMessageHistoryRequest(limit: 50, offset: 10)
        
        XCTAssertEqual(request.limit, 50)
        XCTAssertEqual(request.offset, 10)
    }
    
    func testAcknowledgeMessagesRequest() {
        let request = AcknowledgeMessagesRequest(
            messageIds: ["msg1", "msg2", "msg3"]
        )
        
        XCTAssertEqual(request.messageIds.count, 3)
        XCTAssertTrue(request.messageIds.contains("msg1"))
    }
    
    func testClearChatRequest() {
        let request = ClearChatRequest(confirm: true)
        XCTAssertTrue(request.confirm)
    }
    
    // MARK: - Response Model Tests
    
    func testWelcomeResponse() {
        let response = WelcomeResponse(
            serverVersion: "1.0.0",
            supportedFeatures: ["streaming", "history", "permissions"],
            sessionId: "session-123"
        )
        
        XCTAssertEqual(response.serverVersion, "1.0.0")
        XCTAssertEqual(response.supportedFeatures.count, 3)
        XCTAssertTrue(response.supportedFeatures.contains("streaming"))
        XCTAssertEqual(response.sessionId, "session-123")
    }
    
    func testAskResponseData() {
        let response = AskResponseData(
            response: "The weather is sunny",
            sessionId: "session-456"
        )
        
        XCTAssertEqual(response.response, "The weather is sunny")
        XCTAssertEqual(response.sessionId, "session-456")
    }
    
    func testStreamStartedResponse() {
        let response = StreamStartedResponse(
            streamId: "stream-001",
            sessionId: "session-789"
        )
        
        XCTAssertEqual(response.streamId, "stream-001")
        XCTAssertEqual(response.sessionId, "session-789")
    }
    
    func testStreamDataResponse() {
        let content1 = StreamContent(type: "text", text: "Hello")
        let content2 = StreamContent(type: "code", text: "print('world')")
        
        let response = StreamDataResponse(
            content: [content1, content2],
            streamId: "stream-002"
        )
        
        XCTAssertEqual(response.content.count, 2)
        XCTAssertEqual(response.content[0].type, "text")
        XCTAssertEqual(response.content[0].text, "Hello")
        XCTAssertEqual(response.streamId, "stream-002")
    }
    
    func testStreamChunk() {
        let metadata = StreamChunkMetadata(
            toolName: "Bash",
            toolId: "tool-001",
            isPartial: true,
            index: 1,
            total: 10,
            progress: 0.1,
            estimatedTimeRemaining: 30.0,
            status: "processing",
            details: ["key": AnyCodable("value")],
            sessionId: "session-123",
            requestId: "req-123",
            duration: 5.0,
            usage: nil,
            model: "claude-3",
            finishReason: nil,
            stopSequence: nil,
            inputTokens: 100,
            outputTokens: 50,
            cacheCreationInputTokens: 10,
            cacheReadInputTokens: 5
        )
        
        let chunk = StreamChunk(
            type: "tool_use",
            content: "Running command",
            metadata: metadata
        )
        
        XCTAssertEqual(chunk.type, "tool_use")
        XCTAssertEqual(chunk.content, "Running command")
        XCTAssertNotNil(chunk.metadata)
        XCTAssertEqual(chunk.metadata?.toolName, "Bash")
        XCTAssertEqual(chunk.metadata?.progress, 0.1)
    }
    
    func testPermissionRequestData() {
        let request = PermissionRequestData(
            prompt: "Allow access to file?",
            options: ["yes", "no", "always"],
            requestId: "perm-req-001"
        )
        
        XCTAssertEqual(request.prompt, "Allow access to file?")
        XCTAssertEqual(request.options.count, 3)
        XCTAssertTrue(request.options.contains("yes"))
        XCTAssertEqual(request.requestId, "perm-req-001")
    }
    
    func testStreamCompleteResponse() {
        let response = StreamCompleteResponse(
            streamId: "stream-003",
            finalResponse: "Task completed successfully",
            sessionId: "session-final"
        )
        
        XCTAssertEqual(response.streamId, "stream-003")
        XCTAssertEqual(response.finalResponse, "Task completed successfully")
        XCTAssertEqual(response.sessionId, "session-final")
    }
    
    func testErrorResponse() {
        let response = ErrorResponse(
            message: "Connection failed",
            code: "CONN_ERR_001"
        )
        
        XCTAssertEqual(response.message, "Connection failed")
        XCTAssertEqual(response.code, "CONN_ERR_001")
    }
    
    func testSessionStatusResponse() {
        let startTime = Date()
        let lastActivity = Date()
        
        let response = SessionStatusResponse(
            isActive: true,
            sessionId: "session-status",
            startTime: startTime,
            lastActivity: lastActivity,
            messageCount: 42,
            workingDirectory: "/Users/test",
            serverVersion: "2.0.0"
        )
        
        XCTAssertTrue(response.isActive)
        XCTAssertEqual(response.sessionId, "session-status")
        XCTAssertEqual(response.startTime, startTime)
        XCTAssertEqual(response.lastActivity, lastActivity)
        XCTAssertEqual(response.messageCount, 42)
        XCTAssertEqual(response.workingDirectory, "/Users/test")
        XCTAssertEqual(response.serverVersion, "2.0.0")
    }
    
    func testPongResponse() {
        let timestamp = Date()
        let response = PongResponse(timestamp: timestamp)
        
        XCTAssertEqual(response.timestamp, timestamp)
    }
    
    func testSubscribedResponse() {
        let response = SubscribedResponse(
            events: ["message", "error"],
            success: true
        )
        
        XCTAssertEqual(response.events.count, 2)
        XCTAssertTrue(response.events.contains("message"))
        XCTAssertTrue(response.success)
    }
    
    func testSystemInitResponse() {
        let response = SystemInitResponse(
            system: "macOS",
            version: "14.0",
            features: ["notifications", "file-access"],
            workingDirectory: "/Users/test/workspace"
        )
        
        XCTAssertEqual(response.system, "macOS")
        XCTAssertEqual(response.version, "14.0")
        XCTAssertEqual(response.features.count, 2)
        XCTAssertTrue(response.features.contains("notifications"))
        XCTAssertEqual(response.workingDirectory, "/Users/test/workspace")
    }
    
    // MARK: - WebSocketMessageData Tests
    
    func testWebSocketMessageDataWithAsk() throws {
        let askRequest = AskRequest(message: "Test", options: nil)
        let data = WebSocketMessageData.ask(askRequest)
        
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WebSocketMessageData.self, from: encoded)
        
        if case .ask(let decodedRequest) = decoded {
            XCTAssertEqual(decodedRequest.message, "Test")
        } else {
            XCTFail("Expected ask data")
        }
    }
    
    func testWebSocketMessageDataWithError() throws {
        let errorResponse = ErrorResponse(message: "Test error", code: "TEST001")
        let data = WebSocketMessageData.error(errorResponse)
        
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WebSocketMessageData.self, from: encoded)
        
        if case .error(let decodedResponse) = decoded {
            XCTAssertEqual(decodedResponse.message, "Test error")
            XCTAssertEqual(decodedResponse.code, "TEST001")
        } else {
            XCTFail("Expected error data")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteWebSocketMessage() throws {
        let welcomeResponse = WelcomeResponse(
            serverVersion: "1.5.0",
            supportedFeatures: ["all"],
            sessionId: "integration-test"
        )
        
        let message = WebSocketMessage(
            type: .welcome,
            data: .welcome(welcomeResponse),
            id: "welcome-msg",
            requestId: nil,
            error: nil,
            timestamp: Date()
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WebSocketMessage.self, from: data)
        
        XCTAssertEqual(decoded.type, .welcome)
        XCTAssertEqual(decoded.id, "welcome-msg")
        
        if case .welcome(let decodedWelcome) = decoded.data {
            XCTAssertEqual(decodedWelcome.serverVersion, "1.5.0")
            XCTAssertEqual(decodedWelcome.sessionId, "integration-test")
        } else {
            XCTFail("Expected welcome data")
        }
    }
}