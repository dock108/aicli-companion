import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessageValidatorTests: XCTestCase {
    
    // MARK: - Stream Chunk Validation Tests
    
    func testValidStreamChunk_ContentType() {
        let chunk = StreamChunk(
            type: "content",
            content: "Test content",
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_TextType() {
        let chunk = StreamChunk(
            type: "text",
            content: "Test text",
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testInvalidStreamChunk_EmptyContent() {
        let chunk = StreamChunk(
            type: "content",
            content: "",
            metadata: nil
        )
        XCTAssertFalse(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testInvalidStreamChunk_WhitespaceContent() {
        let chunk = StreamChunk(
            type: "text",
            content: "   \n\t   ",
            metadata: nil
        )
        XCTAssertFalse(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_ToolUse() {
        // Create metadata JSON and decode it
        let metadataJSON = """
        {
            "toolName": "TestTool"
        }
        """
        let metadata = try! JSONDecoder().decode(StreamChunkMetadata.self, from: metadataJSON.data(using: .utf8)!)
        
        let chunk = StreamChunk(
            type: "tool_use",
            content: nil,
            metadata: metadata
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testInvalidStreamChunk_ToolUseNoName() {
        // Create metadata JSON with empty tool name
        let metadataJSON = """
        {
            "toolName": ""
        }
        """
        let metadata = try! JSONDecoder().decode(StreamChunkMetadata.self, from: metadataJSON.data(using: .utf8)!)
        
        let chunk = StreamChunk(
            type: "tool_use",
            content: nil,
            metadata: metadata
        )
        XCTAssertFalse(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testInvalidStreamChunk_ToolUseNoMetadata() {
        let chunk = StreamChunk(
            type: "tool_use",
            content: nil,
            metadata: nil
        )
        XCTAssertFalse(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_ToolResult() {
        let chunk = StreamChunk(
            type: "tool_result",
            content: "Tool output",
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testInvalidStreamChunk_ToolResultEmpty() {
        let chunk = StreamChunk(
            type: "tool_result",
            content: "",
            metadata: nil
        )
        XCTAssertFalse(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_CompleteType() {
        let chunk = StreamChunk(
            type: "complete",
            content: nil,
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_DividerType() {
        let chunk = StreamChunk(
            type: "divider",
            content: nil,
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_CodeType() {
        let chunk = StreamChunk(
            type: "code",
            content: "print('hello')",
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    func testValidStreamChunk_UnknownType() {
        let chunk = StreamChunk(
            type: "future_type",
            content: nil,
            metadata: nil
        )
        XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk))
    }
    
    // MARK: - WebSocket Message Validation Tests
    
    func testValidWebSocketMessage_StreamChunk() {
        let chunk = StreamChunk(
            type: "content",
            content: "Test",
            metadata: nil
        )
        let response = StreamChunkResponse(chunk: chunk)
        let message = WebSocketMessage(
            type: .streamChunk,
            data: .streamChunk(response)
        )
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testInvalidWebSocketMessage_EmptyStreamChunk() {
        let chunk = StreamChunk(
            type: "content",
            content: "",
            metadata: nil
        )
        let response = StreamChunkResponse(chunk: chunk)
        let message = WebSocketMessage(
            type: .streamChunk,
            data: .streamChunk(response)
        )
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testValidWebSocketMessage_AssistantMessage() {
        let contentBlock = MessageContentBlock(
            type: "text",
            text: "Hello",
            source: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            isError: nil
        )
        let response = AssistantMessageResponse(
            content: [contentBlock],
            messageId: "msg123",
            sessionId: "123",
            model: nil,
            usage: nil,
            stopReason: nil,
            stopSequence: nil,
            type: "message",
            role: "assistant"
        )
        let message = WebSocketMessage(
            type: .assistantMessage,
            data: .assistantMessage(response)
        )
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testInvalidWebSocketMessage_EmptyAssistantMessage() {
        let response = AssistantMessageResponse(
            content: [],
            messageId: "msg123",
            sessionId: "123",
            model: nil,
            usage: nil,
            stopReason: nil,
            stopSequence: nil,
            type: "message",
            role: "assistant"
        )
        let message = WebSocketMessage(
            type: .assistantMessage,
            data: .assistantMessage(response)
        )
        // Empty content array should fail validation
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testValidWebSocketMessage_ToolUse() {
        let tool = ToolUseResponse(
            id: "tool123",
            name: "TestTool",
            input: [:]
        )
        let message = WebSocketMessage(
            type: .toolUse,
            data: .toolUse(tool)
        )
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testInvalidWebSocketMessage_EmptyToolName() {
        let tool = ToolUseResponse(
            id: "tool123",
            name: "",
            input: [:]
        )
        let message = WebSocketMessage(
            type: .toolUse,
            data: .toolUse(tool)
        )
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testValidWebSocketMessage_ToolResult() {
        let contentBlock = MessageContentBlock(
            type: "text",
            text: "Result",
            source: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            isError: nil
        )
        let result = ToolResultResponse(
            toolUseId: "tool123",
            content: [contentBlock],
            isError: false
        )
        let message = WebSocketMessage(
            type: .toolResult,
            data: .toolResult(result)
        )
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testInvalidWebSocketMessage_EmptyToolResult() {
        let result = ToolResultResponse(
            toolUseId: "tool123",
            content: [],
            isError: false
        )
        let message = WebSocketMessage(
            type: .toolResult,
            data: .toolResult(result)
        )
        // Empty content array should fail validation
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testValidWebSocketMessage_Error() {
        let error = ErrorResponse(
            message: "Error occurred",
            code: "ERR_001"
        )
        let message = WebSocketMessage(
            type: .error,
            data: .error(error)
        )
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testInvalidWebSocketMessage_EmptyError() {
        let error = ErrorResponse(
            message: "",
            code: nil
        )
        let message = WebSocketMessage(
            type: .error,
            data: .error(error)
        )
        XCTAssertFalse(MessageValidator.isValidWebSocketMessage(message))
    }
    
    func testValidWebSocketMessage_SessionStatus() {
        let status = SessionStatusResponse(
            isActive: true,
            sessionId: "123",
            startTime: Date(),
            lastActivity: Date(),
            messageCount: 5,
            workingDirectory: "/test",
            serverVersion: "1.0.0"
        )
        let message = WebSocketMessage(
            type: .sessionStatus,
            data: .sessionStatus(status)
        )
        XCTAssertTrue(MessageValidator.isValidWebSocketMessage(message))
    }
    
    // MARK: - Duplicate Filtering Tests
    
    func testFilterDuplicates_RemovesDuplicateContent() {
        let message1 = Message(
            content: "Hello",
            sender: .user,
            timestamp: Date()
        )
        let message2 = Message(
            content: "Hello",
            sender: .user,
            timestamp: Date().addingTimeInterval(0.5)
        )
        let message3 = Message(
            content: "World",
            sender: .user,
            timestamp: Date().addingTimeInterval(1.5)
        )
        
        let filtered = MessageValidator.filterDuplicates(messages: [message1, message2, message3])
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].content, "Hello")
        XCTAssertEqual(filtered[1].content, "World")
    }
    
    func testFilterDuplicates_KeepsDifferentSenders() {
        let message1 = Message(
            content: "Hello",
            sender: .user,
            timestamp: Date()
        )
        let message2 = Message(
            content: "Hello",
            sender: .assistant,
            timestamp: Date().addingTimeInterval(0.5)
        )
        
        let filtered = MessageValidator.filterDuplicates(messages: [message1, message2])
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testFilterDuplicates_KeepsMessagesOutsideTimeWindow() {
        let message1 = Message(
            content: "Hello",
            sender: .user,
            timestamp: Date()
        )
        let message2 = Message(
            content: "Hello",
            sender: .user,
            timestamp: Date().addingTimeInterval(2.0)
        )
        
        let filtered = MessageValidator.filterDuplicates(messages: [message1, message2], within: 1.0)
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testFilterDuplicates_EmptyArray() {
        let filtered = MessageValidator.filterDuplicates(messages: [])
        XCTAssertEqual(filtered.count, 0)
    }
    
    // MARK: - Message Order Tests
    
    func testEnsureMessageOrder_SortsCorrectly() {
        let date1 = Date()
        let date2 = date1.addingTimeInterval(1)
        let date3 = date1.addingTimeInterval(2)
        
        let message1 = Message(content: "First", sender: .user, timestamp: date1)
        let message2 = Message(content: "Second", sender: .assistant, timestamp: date2)
        let message3 = Message(content: "Third", sender: .user, timestamp: date3)
        
        let unordered = [message3, message1, message2]
        let ordered = MessageValidator.ensureMessageOrder(messages: unordered)
        
        XCTAssertEqual(ordered[0].content, "First")
        XCTAssertEqual(ordered[1].content, "Second")
        XCTAssertEqual(ordered[2].content, "Third")
    }
    
    func testEnsureMessageOrder_EmptyArray() {
        let ordered = MessageValidator.ensureMessageOrder(messages: [])
        XCTAssertEqual(ordered.count, 0)
    }
    
    func testEnsureMessageOrder_SingleMessage() {
        let message = Message(content: "Test", sender: .user)
        let ordered = MessageValidator.ensureMessageOrder(messages: [message])
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(ordered[0].content, "Test")
    }
    
    // MARK: - Content Cleaning Tests
    
    func testCleanMessageContent_RemovesExcessiveWhitespace() {
        let dirty = "  Hello   World  \n\n\n\n  Test  "
        let cleaned = MessageValidator.cleanMessageContent(dirty)
        XCTAssertEqual(cleaned, "Hello   World  \n\n  Test")
    }
    
    func testCleanMessageContent_RemovesControlCharacters() {
        let dirty = "Hello\u{0000}World\u{0001}Test"
        let cleaned = MessageValidator.cleanMessageContent(dirty)
        XCTAssertEqual(cleaned, "HelloWorldTest")
    }
    
    func testCleanMessageContent_KeepsNewlinesAndTabs() {
        let content = "Hello\nWorld\tTest"
        let cleaned = MessageValidator.cleanMessageContent(content)
        XCTAssertEqual(cleaned, "Hello\nWorld\tTest")
    }
    
    func testCleanMessageContent_ReplacesMultipleNewlines() {
        let dirty = "Hello\n\n\n\n\nWorld"
        let cleaned = MessageValidator.cleanMessageContent(dirty)
        XCTAssertEqual(cleaned, "Hello\n\nWorld")
    }
    
    func testCleanMessageContent_EmptyString() {
        let cleaned = MessageValidator.cleanMessageContent("")
        XCTAssertEqual(cleaned, "")
    }
    
    func testCleanMessageContent_OnlyWhitespace() {
        let cleaned = MessageValidator.cleanMessageContent("   \n\n\t   ")
        XCTAssertEqual(cleaned, "")
    }
    
    // MARK: - Display Message Tests
    
    func testShouldDisplayMessage_ValidUserMessage() {
        let message = Message(content: "Hello", sender: .user)
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_ValidAssistantMessage() {
        let message = Message(content: "Response", sender: .assistant)
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_EmptyContent() {
        let message = Message(content: "", sender: .user)
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_WhitespaceContent() {
        let message = Message(content: "   \n\t   ", sender: .user)
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_SystemMessage() {
        let message = Message(content: "System update", sender: .system)
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_InternalSystemMessage() {
        let message = Message(content: "[System] Internal log", sender: .system)
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_DebugMessage() {
        let message = Message(content: "[Debug] Memory usage", sender: .system)
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_InternalMessage() {
        let message = Message(content: "[Internal] State change", sender: .system)
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_NormalSystemMessage() {
        let message = Message(content: "Connection established", sender: .system)
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    // MARK: - Edge Cases and Performance Tests
    
    func testFilterDuplicates_LargeDataset() {
        var messages: [Message] = []
        let baseTime = Date()
        
        // Create 1000 messages with some actual duplicates
        for i in 0..<1000 {
            let content = i % 10 == 0 ? "Duplicate" : "Message \(i)"
            messages.append(Message(
                content: content,
                sender: .user,
                timestamp: baseTime.addingTimeInterval(Double(i) * 0.01) // 0.01 sec apart
            ))
            
            // Add actual duplicate within time window for every 10th message
            if i % 10 == 0 && i > 0 {
                messages.append(Message(
                    content: content,
                    sender: .user,
                    timestamp: baseTime.addingTimeInterval(Double(i) * 0.01 + 0.001) // Very close in time
                ))
            }
        }
        
        let startTime = Date()
        let filtered = MessageValidator.filterDuplicates(messages: messages, within: 0.5)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(duration, 1.0, "Filtering should complete in under 1 second")
        XCTAssertLessThan(filtered.count, messages.count, "Should filter out duplicate messages")
        XCTAssertGreaterThan(filtered.count, 900, "Should keep most messages")
    }
    
    func testCleanMessageContent_UnicodeEmoji() {
        let content = "Hello 👋 World 🌍 Test 🧪"
        let cleaned = MessageValidator.cleanMessageContent(content)
        XCTAssertEqual(cleaned, content)
    }
    
    func testCleanMessageContent_MixedLanguages() {
        let content = "Hello 你好 مرحبا こんにちは"
        let cleaned = MessageValidator.cleanMessageContent(content)
        XCTAssertEqual(cleaned, content)
    }
    
    func testValidStreamChunk_AllTypes() {
        let types = ["content", "text", "code", "header", "section", "list", "complete", "divider"]
        for type in types {
            let content = (type == "complete" || type == "divider") ? nil : "Test"
            let chunk = StreamChunk(type: type, content: content, metadata: nil)
            XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk), "Type \(type) should be valid")
        }
    }
}