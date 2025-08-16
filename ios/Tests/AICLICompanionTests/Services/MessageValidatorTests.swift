import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessageValidatorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - StreamChunk Validation Tests
    
    func testValidStreamChunkWithContent() throws {
        let validChunk = TestDataFactory.createStreamChunk(
            content: "Hello, this is valid content",
            type: "content",
            isFinal: false
        )
        
        XCTAssertTrue(MessageValidator.isValidStreamChunk(validChunk))
    }
    
    func testValidStreamChunkWithCode() throws {
        let codeChunk = TestDataFactory.createStreamChunk(
            content: "print('Hello, World!')",
            type: "code",
            isFinal: true
        )
        
        XCTAssertTrue(MessageValidator.isValidStreamChunk(codeChunk))
    }
    
    func testInvalidStreamChunkWithEmptyContent() throws {
        let emptyChunk = TestDataFactory.createStreamChunk(
            content: "",
            type: "content",
            isFinal: false
        )
        
        XCTAssertFalse(MessageValidator.isValidStreamChunk(emptyChunk))
    }
    
    func testInvalidStreamChunkWithWhitespaceOnlyContent() throws {
        let whitespaceChunk = TestDataFactory.createStreamChunk(
            content: "   \n\t  ",
            type: "text",
            isFinal: false
        )
        
        XCTAssertFalse(MessageValidator.isValidStreamChunk(whitespaceChunk))
    }
    
    func testValidToolUseChunk() throws {
        let toolMetadata = StreamChunkMetadata(toolName: "Read")
        let toolChunk = StreamChunk(
            id: UUID().uuidString,
            type: "tool_use",
            content: "Reading file...",
            isFinal: false,
            metadata: toolMetadata
        )
        
        XCTAssertTrue(MessageValidator.isValidStreamChunk(toolChunk))
    }
    
    func testInvalidToolUseChunkWithoutToolName() throws {
        let invalidToolMetadata = StreamChunkMetadata()
        let toolChunk = StreamChunk(
            id: UUID().uuidString,
            type: "tool_use",
            content: "Using tool...",
            isFinal: false,
            metadata: invalidToolMetadata
        )
        
        XCTAssertFalse(MessageValidator.isValidStreamChunk(toolChunk))
    }
    
    func testValidCompleteChunk() throws {
        let completeChunk = StreamChunk(
            id: UUID().uuidString,
            type: "complete",
            content: "",
            isFinal: true,
            metadata: nil
        )
        
        XCTAssertTrue(MessageValidator.isValidStreamChunk(completeChunk))
    }
    
    func testValidDividerChunk() throws {
        let dividerChunk = StreamChunk(
            id: UUID().uuidString,
            type: "divider",
            content: "",
            isFinal: false,
            metadata: nil
        )
        
        XCTAssertTrue(MessageValidator.isValidStreamChunk(dividerChunk))
    }
    
    func testUnknownChunkTypesAreAllowed() throws {
        let unknownChunk = StreamChunk(
            id: UUID().uuidString,
            type: "unknown_type",
            content: "unknown content",
            isFinal: false,
            metadata: nil
        )
        
        XCTAssertTrue(MessageValidator.isValidStreamChunk(unknownChunk))
    }
    
    // MARK: - WebSocket Message Validation Tests
    
    func testValidWebSocketMessageWithStreamChunk() throws {
        let validChunk = TestDataFactory.createStreamChunk(content: "Valid content")
        let chunkResponse = StreamChunkResponse(sessionId: "test-session", chunk: validChunk)
        let webSocketMessage = WebSocketMessage(
            type: .streamChunk,
            requestId: "req-123",
            timestamp: Date(),
            data: .streamChunk(chunkResponse)
        )
        
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testInvalidWebSocketMessageWithInvalidChunk() throws {
        let invalidChunk = TestDataFactory.createStreamChunk(content: "")
        let chunkResponse = StreamChunkResponse(sessionId: "test-session", chunk: invalidChunk)
        let webSocketMessage = WebSocketMessage(
            type: .streamChunk,
            requestId: "req-123",
            timestamp: Date(),
            data: .streamChunk(chunkResponse)
        )
        
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testValidAssistantMessage() throws {
        let assistantResponse = AssistantMessageResponse(
            type: "assistant_message",
            messageId: "msg-123",
            content: [MessageContentBlock(type: "text", text: "Hello!", toolName: nil, toolInput: nil, toolId: nil)],
            model: "claude-3-sonnet",
            usage: TestDataFactory.createUsage(),
            claudeSessionId: "session-123",
            deliverables: nil,
            aggregated: false,
            messageCount: 1,
            isComplete: true,
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .assistantMessage,
            requestId: "req-123",
            timestamp: Date(),
            data: .assistantMessage(assistantResponse)
        )
        
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testInvalidAssistantMessageWithEmptyContent() throws {
        let emptyAssistantResponse = AssistantMessageResponse(
            type: "assistant_message",
            messageId: "msg-123",
            content: [MessageContentBlock(type: "text", text: "", toolName: nil, toolInput: nil, toolId: nil)],
            model: "claude-3-sonnet",
            usage: nil,
            claudeSessionId: "session-123",
            deliverables: nil,
            aggregated: false,
            messageCount: 1,
            isComplete: true,
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .assistantMessage,
            requestId: "req-123",
            timestamp: Date(),
            data: .assistantMessage(emptyAssistantResponse)
        )
        
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testValidToolUseMessage() throws {
        let toolUseResponse = ToolUseResponse(
            type: "tool_use",
            toolName: "Read",
            toolInput: ["file_path": AnyCodable("/test/file.txt")],
            toolId: "tool-123",
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .toolUse,
            requestId: "req-123",
            timestamp: Date(),
            data: .toolUse(toolUseResponse)
        )
        
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testInvalidToolUseMessageWithEmptyName() throws {
        let invalidToolUseResponse = ToolUseResponse(
            type: "tool_use",
            toolName: "",
            toolInput: ["file_path": AnyCodable("/test/file.txt")],
            toolId: "tool-123",
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .toolUse,
            requestId: "req-123",
            timestamp: Date(),
            data: .toolUse(invalidToolUseResponse)
        )
        
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testValidToolResultMessage() throws {
        let toolResultResponse = ToolResultResponse(
            type: "tool_result",
            toolName: "Read",
            toolId: "tool-123",
            result: "File content here",
            success: true,
            error: nil,
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .toolResult,
            requestId: "req-123",
            timestamp: Date(),
            data: .toolResult(toolResultResponse)
        )
        
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testValidToolResultMessageWithError() throws {
        let errorToolResultResponse = ToolResultResponse(
            type: "tool_result",
            toolName: "Write",
            toolId: "tool-456",
            result: nil,
            success: false,
            error: "Permission denied",
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .toolResult,
            requestId: "req-123",
            timestamp: Date(),
            data: .toolResult(errorToolResultResponse)
        )
        
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testInvalidToolResultMessageWithoutResultOrError() throws {
        let invalidToolResultResponse = ToolResultResponse(
            type: "tool_result",
            toolName: "Edit",
            toolId: "tool-789",
            result: nil,
            success: false,
            error: nil,
            timestamp: Date()
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .toolResult,
            requestId: "req-123",
            timestamp: Date(),
            data: .toolResult(invalidToolResultResponse)
        )
        
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testValidErrorMessage() throws {
        let errorResponse = ErrorResponse(
            code: "network_error",
            message: "Connection failed",
            details: nil
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .error,
            requestId: "req-123",
            timestamp: Date(),
            data: .error(errorResponse)
        )
        
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    func testInvalidErrorMessageWithEmptyMessage() throws {
        let invalidErrorResponse = ErrorResponse(
            code: "unknown_error",
            message: "",
            details: nil
        )
        
        let webSocketMessage = WebSocketMessage(
            type: .error,
            requestId: "req-123",
            timestamp: Date(),
            data: .error(invalidErrorResponse)
        )
        
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(webSocketMessage))
    }
    
    // MARK: - Message Duplicate Filtering Tests
    
    func testFilterDuplicatesRemovesSameContentSameSender() throws {
        let baseTime = Date()
        let message1 = TestDataFactory.createUserMessage(
            content: "Hello",
            timestamp: baseTime
        )
        let message2 = TestDataFactory.createUserMessage(
            content: "Hello",
            timestamp: baseTime.addingTimeInterval(0.5) // Within 1 second window
        )
        let message3 = TestDataFactory.createAssistantMessage(
            content: "Hi there!",
            timestamp: baseTime.addingTimeInterval(1)
        )
        
        let messages = [message1, message2, message3]
        let filtered = MessageValidator.filterDuplicates(messages: messages)
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == message1.id })
        XCTAssertFalse(filtered.contains { $0.id == message2.id })
        XCTAssertTrue(filtered.contains { $0.id == message3.id })
    }
    
    func testFilterDuplicatesKeepsSameContentDifferentSenders() throws {
        let baseTime = Date()
        let userMessage = TestDataFactory.createUserMessage(
            content: "Hello",
            timestamp: baseTime
        )
        let assistantMessage = TestDataFactory.createAssistantMessage(
            content: "Hello", // Same content, different sender
            timestamp: baseTime.addingTimeInterval(0.5)
        )
        
        let messages = [userMessage, assistantMessage]
        let filtered = MessageValidator.filterDuplicates(messages: messages)
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == userMessage.id })
        XCTAssertTrue(filtered.contains { $0.id == assistantMessage.id })
    }
    
    func testFilterDuplicatesKeepsMessagesOutsideTimeWindow() throws {
        let baseTime = Date()
        let message1 = TestDataFactory.createUserMessage(
            content: "Hello",
            timestamp: baseTime
        )
        let message2 = TestDataFactory.createUserMessage(
            content: "Hello",
            timestamp: baseTime.addingTimeInterval(2) // Outside 1 second window
        )
        
        let messages = [message1, message2]
        let filtered = MessageValidator.filterDuplicates(messages: messages)
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == message1.id })
        XCTAssertTrue(filtered.contains { $0.id == message2.id })
    }
    
    func testFilterDuplicatesWithCustomTimeWindow() throws {
        let baseTime = Date()
        let message1 = TestDataFactory.createUserMessage(
            content: "Test",
            timestamp: baseTime
        )
        let message2 = TestDataFactory.createUserMessage(
            content: "Test",
            timestamp: baseTime.addingTimeInterval(2.5) // Within 3 second window
        )
        
        let messages = [message1, message2]
        let filtered = MessageValidator.filterDuplicates(messages: messages, within: 3.0)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(filtered.contains { $0.id == message1.id })
    }
    
    // MARK: - Message Order Tests
    
    func testEnsureMessageOrderSortsCorrectly() throws {
        let baseTime = Date()
        let message1 = TestDataFactory.createUserMessage(
            content: "First",
            timestamp: baseTime.addingTimeInterval(10) // Latest timestamp
        )
        let message2 = TestDataFactory.createAssistantMessage(
            content: "Second",
            timestamp: baseTime.addingTimeInterval(5)
        )
        let message3 = TestDataFactory.createUserMessage(
            content: "Third",
            timestamp: baseTime // Earliest timestamp
        )
        
        let unorderedMessages = [message1, message2, message3]
        let orderedMessages = MessageValidator.ensureMessageOrder(messages: unorderedMessages)
        
        XCTAssertEqual(orderedMessages.count, 3)
        XCTAssertEqual(orderedMessages[0].id, message3.id) // Earliest first
        XCTAssertEqual(orderedMessages[1].id, message2.id)
        XCTAssertEqual(orderedMessages[2].id, message1.id) // Latest last
    }
    
    func testEnsureMessageOrderWithAlreadyOrderedMessages() throws {
        let orderedMessages = TestDataFactory.createMessageHistory(count: 3)
        let reorderedMessages = MessageValidator.ensureMessageOrder(messages: orderedMessages)
        
        XCTAssertEqual(reorderedMessages.count, orderedMessages.count)
        
        // Should maintain the same order if already ordered
        for i in 0..<orderedMessages.count {
            XCTAssertEqual(reorderedMessages[i].id, orderedMessages[i].id)
        }
    }
    
    // MARK: - Content Cleaning Tests
    
    func testCleanMessageContentRemovesExcessiveWhitespace() throws {
        let messyContent = "  Hello  \n\n\n\n\nWorld  \t\n  "
        let cleaned = MessageValidator.cleanMessageContent(messyContent)
        
        XCTAssertEqual(cleaned, "Hello  \n\nWorld")
    }
    
    func testCleanMessageContentRemovesControlCharacters() throws {
        let contentWithControlChars = "Hello\u{0001}World\u{0002}Test\u{007F}"
        let cleaned = MessageValidator.cleanMessageContent(contentWithControlChars)
        
        XCTAssertEqual(cleaned, "HelloWorldTest")
    }
    
    func testCleanMessageContentPreservesNewlinesAndTabs() throws {
        let contentWithValidWhitespace = "Line 1\nLine 2\n\tIndented line"
        let cleaned = MessageValidator.cleanMessageContent(contentWithValidWhitespace)
        
        XCTAssertEqual(cleaned, "Line 1\nLine 2\n\tIndented line")
    }
    
    func testCleanMessageContentWithEmptyString() throws {
        let cleaned = MessageValidator.cleanMessageContent("")
        XCTAssertEqual(cleaned, "")
    }
    
    func testCleanMessageContentWithOnlyWhitespace() throws {
        let cleaned = MessageValidator.cleanMessageContent("   \n\t  ")
        XCTAssertEqual(cleaned, "")
    }
    
    // MARK: - Display Message Filtering Tests
    
    func testShouldDisplayMessageWithValidContent() throws {
        let validMessage = TestDataFactory.createUserMessage(content: "This is a valid message")
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(validMessage))
    }
    
    func testShouldDisplayMessageWithEmptyContent() throws {
        let emptyMessage = TestDataFactory.createUserMessage(content: "")
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(emptyMessage))
    }
    
    func testShouldDisplayMessageWithWhitespaceOnlyContent() throws {
        let whitespaceMessage = TestDataFactory.createUserMessage(content: "   \n\t  ")
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(whitespaceMessage))
    }
    
    func testShouldDisplaySystemMessage() throws {
        let systemMessage = TestDataFactory.createSystemMessage(content: "System status: Online")
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(systemMessage))
    }
    
    func testShouldNotDisplayInternalSystemMessage() throws {
        let internalMessage1 = TestDataFactory.createSystemMessage(content: "[System] Internal process started")
        let internalMessage2 = TestDataFactory.createSystemMessage(content: "[Debug] Connection established")
        let internalMessage3 = TestDataFactory.createSystemMessage(content: "[Internal] Cache cleared")
        
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(internalMessage1))
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(internalMessage2))
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(internalMessage3))
    }
    
    func testShouldDisplayValidSystemMessage() throws {
        let validSystemMessage = TestDataFactory.createSystemMessage(content: "Connection established")
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(validSystemMessage))
    }
    
    // MARK: - Performance Tests
    
    func testValidationPerformanceWithLargeMessageSet() throws {
        let messages = TestDataFactory.createMessageHistory(count: 1000)
        
        measure {
            for message in messages {
                _ = MessageValidator.shouldDisplayMessage(message)
            }
        }
    }
    
    func testDuplicateFilteringPerformanceWithLargeSet() throws {
        // Create messages with some duplicates
        var messages: [Message] = []
        let baseTime = Date()
        
        for i in 0..<500 {
            let message = TestDataFactory.createUserMessage(
                content: "Message \(i % 100)", // Creates duplicates
                timestamp: baseTime.addingTimeInterval(TimeInterval(i))
            )
            messages.append(message)
        }
        
        measure {
            _ = MessageValidator.filterDuplicates(messages: messages)
        }
    }
    
    func testContentCleaningPerformanceWithLargeText() throws {
        let largeContent = String(repeating: "Hello World\n\n\n\n", count: 1000)
        
        measure {
            _ = MessageValidator.cleanMessageContent(largeContent)
        }
    }
}