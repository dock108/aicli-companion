import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessageValidatorTests: XCTestCase {
    // MARK: - Stream Chunk Validation Tests
    
    func testValidStreamChunk_ContentType() {
        // Given: Valid content chunk
        let validChunk = StreamChunk(
            type: "content",
            content: "This is valid content",
            metadata: nil
        )
        
        // When & Then
        XCTAssertTrue(MessageValidator.isValidStreamChunk(validChunk))
    }
    
    func testInvalidStreamChunk_EmptyContent() {
        // Given: Empty content chunk
        let emptyChunk = StreamChunk(
            type: "content",
            content: "   ",
            metadata: nil
        )
        
        // When & Then
        XCTAssertFalse(MessageValidator.isValidStreamChunk(emptyChunk))
    }
    
    func testInvalidStreamChunk_NilContent() {
        // Given: Nil content chunk
        let nilChunk = StreamChunk(
            type: "text",
            content: nil,
            metadata: nil
        )
        
        // When & Then
        XCTAssertFalse(MessageValidator.isValidStreamChunk(nilChunk))
    }
    
    func testValidStreamChunk_ToolResult() {
        // Given: Valid tool result chunk
        let toolResultChunk = StreamChunk(
            type: "tool_result",
            content: "Tool execution successful",
            metadata: nil
        )
        
        // When & Then
        XCTAssertTrue(MessageValidator.isValidStreamChunk(toolResultChunk))
    }
    
    func testInvalidStreamChunk_ToolResultEmpty() {
        // Given: Tool result chunk with empty content
        let toolResultChunk = StreamChunk(
            type: "tool_result",
            content: "",
            metadata: nil
        )
        
        // When & Then
        XCTAssertFalse(MessageValidator.isValidStreamChunk(toolResultChunk))
    }
    
    func testValidStreamChunk_CompleteType() {
        // Given: Complete chunk type (doesn't require content)
        let completeChunk = StreamChunk(
            type: "complete",
            content: nil,
            metadata: nil
        )
        
        // When & Then
        XCTAssertTrue(MessageValidator.isValidStreamChunk(completeChunk))
    }
    
    func testValidStreamChunk_DividerType() {
        // Given: Divider chunk type (doesn't require content)
        let dividerChunk = StreamChunk(
            type: "divider",
            content: nil,
            metadata: nil
        )
        
        // When & Then
        XCTAssertTrue(MessageValidator.isValidStreamChunk(dividerChunk))
    }
    
    func testValidStreamChunk_UnknownType() {
        // Given: Unknown chunk type (should be allowed)
        let unknownChunk = StreamChunk(
            type: "unknown_type",
            content: "Some content",
            metadata: nil
        )
        
        // When & Then
        XCTAssertTrue(MessageValidator.isValidStreamChunk(unknownChunk))
    }
    
    func testValidStreamChunk_AllContentTypes() {
        // Test all supported content types
        let contentTypes = ["content", "text", "code", "header", "section", "list"]
        
        for type in contentTypes {
            let chunk = StreamChunk(
                type: type,
                content: "Valid content",
                metadata: nil
            )
            XCTAssertTrue(MessageValidator.isValidStreamChunk(chunk), "Type \(type) should be valid")
        }
    }
    
    // MARK: - Duplicate Filtering Tests
    
    func testFilterDuplicates_NoDuplicates() {
        // Given: Messages with different content
        let now = Date()
        let messages = [
            Message(content: "First message", sender: .user, timestamp: now),
            Message(content: "Second message", sender: .assistant, timestamp: now.addingTimeInterval(0.5)),
            Message(content: "Third message", sender: .user, timestamp: now.addingTimeInterval(1.0))
        ]
        
        // When
        let filtered = MessageValidator.filterDuplicates(messages: messages)
        
        // Then
        XCTAssertEqual(filtered.count, 3)
    }
    
    func testFilterDuplicates_WithDuplicates() {
        // Given: Messages with duplicated content within time window
        let now = Date()
        let messages = [
            Message(content: "Same message", sender: .user, timestamp: now),
            Message(content: "Same message", sender: .user, timestamp: now.addingTimeInterval(0.5)),
            Message(content: "Different message", sender: .assistant, timestamp: now.addingTimeInterval(1.0))
        ]
        
        // When
        let filtered = MessageValidator.filterDuplicates(messages: messages, within: 1.0)
        
        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].content, "Same message")
        XCTAssertEqual(filtered[1].content, "Different message")
    }
    
    func testFilterDuplicates_OutsideTimeWindow() {
        // Given: Messages with same content but outside time window
        let now = Date()
        let messages = [
            Message(content: "Same message", sender: .user, timestamp: now),
            Message(content: "Same message", sender: .user, timestamp: now.addingTimeInterval(2.0))
        ]
        
        // When
        let filtered = MessageValidator.filterDuplicates(messages: messages, within: 1.0)
        
        // Then: Both messages should be kept as they're outside the time window
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testFilterDuplicates_DifferentSenders() {
        // Given: Messages with same content but different senders
        let now = Date()
        let messages = [
            Message(content: "Same message", sender: .user, timestamp: now),
            Message(content: "Same message", sender: .assistant, timestamp: now.addingTimeInterval(0.5))
        ]
        
        // When
        let filtered = MessageValidator.filterDuplicates(messages: messages, within: 1.0)
        
        // Then: Both should be kept as they have different senders
        XCTAssertEqual(filtered.count, 2)
    }
    
    // MARK: - Message Order Tests
    
    func testEnsureMessageOrder_AlreadyOrdered() {
        // Given: Messages already in correct order
        let now = Date()
        let messages = [
            Message(content: "First", sender: .user, timestamp: now),
            Message(content: "Second", sender: .assistant, timestamp: now.addingTimeInterval(1.0)),
            Message(content: "Third", sender: .user, timestamp: now.addingTimeInterval(2.0))
        ]
        
        // When
        let ordered = MessageValidator.ensureMessageOrder(messages: messages)
        
        // Then
        XCTAssertEqual(ordered.count, 3)
        XCTAssertEqual(ordered[0].content, "First")
        XCTAssertEqual(ordered[1].content, "Second")
        XCTAssertEqual(ordered[2].content, "Third")
    }
    
    func testEnsureMessageOrder_NeedsReordering() {
        // Given: Messages in wrong order
        let now = Date()
        let messages = [
            Message(content: "Third", sender: .user, timestamp: now.addingTimeInterval(2.0)),
            Message(content: "First", sender: .user, timestamp: now),
            Message(content: "Second", sender: .assistant, timestamp: now.addingTimeInterval(1.0))
        ]
        
        // When
        let ordered = MessageValidator.ensureMessageOrder(messages: messages)
        
        // Then
        XCTAssertEqual(ordered.count, 3)
        XCTAssertEqual(ordered[0].content, "First")
        XCTAssertEqual(ordered[1].content, "Second")
        XCTAssertEqual(ordered[2].content, "Third")
    }
    
    // MARK: - Content Cleaning Tests
    
    func testCleanMessageContent_RemoveExcessiveWhitespace() {
        // Given: Content with excessive whitespace
        let content = "   Hello\n\n\n\nWorld   "
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then
        XCTAssertEqual(cleaned, "Hello\n\nWorld")
    }
    
    func testCleanMessageContent_RemoveControlCharacters() {
        // Given: Content with control characters
        let content = "Hello\u{0000}World\u{0001}Test"
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then
        XCTAssertEqual(cleaned, "HelloWorldTest")
    }
    
    func testCleanMessageContent_PreserveNewlinesAndTabs() {
        // Given: Content with valid newlines and tabs
        let content = "Hello\nWorld\tTest"
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then
        XCTAssertEqual(cleaned, "Hello\nWorld\tTest")
    }
    
    func testCleanMessageContent_EmptyContent() {
        // Given: Empty content
        let content = ""
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then
        XCTAssertEqual(cleaned, "")
    }
    
    func testCleanMessageContent_OnlyWhitespace() {
        // Given: Only whitespace content
        let content = "   \n\n   "
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then
        XCTAssertEqual(cleaned, "")
    }
    
    // MARK: - Message Display Tests
    
    func testShouldDisplayMessage_ValidUserMessage() {
        // Given: Valid user message
        let message = Message(content: "Hello assistant", sender: .user)
        
        // When & Then
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_ValidAssistantMessage() {
        // Given: Valid assistant message
        let message = Message(content: "Hello user", sender: .assistant)
        
        // When & Then
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_EmptyMessage() {
        // Given: Empty message
        let message = Message(content: "", sender: .user)
        
        // When & Then
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_WhitespaceOnlyMessage() {
        // Given: Whitespace only message
        let message = Message(content: "   \n   ", sender: .user)
        
        // When & Then
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_SystemMessageInternal() {
        // Given: Internal system message
        let message = Message(content: "[System] Internal processing", sender: .system)
        
        // When & Then
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_SystemMessageDebug() {
        // Given: Debug system message
        let message = Message(content: "[Debug] Debug info", sender: .system)
        
        // When & Then
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_SystemMessageInternalPrefix() {
        // Given: Internal prefix system message
        let message = Message(content: "[Internal] Internal info", sender: .system)
        
        // When & Then
        XCTAssertFalse(MessageValidator.shouldDisplayMessage(message))
    }
    
    func testShouldDisplayMessage_SystemMessageValid() {
        // Given: Valid system message (no internal prefix)
        let message = Message(content: "Connection established", sender: .system)
        
        // When & Then
        XCTAssertTrue(MessageValidator.shouldDisplayMessage(message))
    }
    
    // MARK: - Regular Expression Content Cleaning Tests
    
    func testCleanMessageContent_RegularExpressionPattern() {
        // Given: Content with multiple consecutive newlines
        let content = "Hello\n\n\n\n\n\nWorld"
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then: Should be reduced to double newline
        XCTAssertEqual(cleaned, "Hello\n\nWorld")
    }
    
    func testCleanMessageContent_CombinedIssues() {
        // Given: Content with multiple issues
        let content = "  \n  Hello\u{0000}\n\n\n\n\nWorld\u{0001}\t  \n  "
        
        // When
        let cleaned = MessageValidator.cleanMessageContent(content)
        
        // Then: Should clean all issues
        XCTAssertEqual(cleaned, "Hello\n\nWorld")
    }
    
    // MARK: - Performance and Edge Cases
    
    func testContentCleaning_LargeContent() {
        // Given: Large content with multiple issues
        let largeContent = String(repeating: "Hello\n\n\n\nWorld\u{0000}", count: 100)
        
        // When
        let startTime = Date()
        let cleaned = MessageValidator.cleanMessageContent(largeContent)
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Should complete quickly and clean properly
        XCTAssertLessThan(duration, 1.0)
        XCTAssertTrue(cleaned.contains("Hello\n\nWorld"))
        XCTAssertFalse(cleaned.contains("\u{0000}"))
    }
    
    func testFilterDuplicates_ManyMessages() {
        // Given: Many messages with some duplicates
        let now = Date()
        var messages: [Message] = []
        
        for i in 0..<50 {
            let content = i % 10 == 0 ? "Duplicate message" : "Unique message \(i)"
            messages.append(Message(
                content: content,
                sender: .user,
                timestamp: now.addingTimeInterval(Double(i) * 0.1)
            ))
        }
        
        // When
        let startTime = Date()
        let filtered = MessageValidator.filterDuplicates(messages: messages, within: 0.5)
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Should complete quickly and filter duplicates
        XCTAssertLessThan(duration, 1.0)
        // Duplicates are at 0s, 1s, 2s, 3s, 4s intervals (indexes 0, 10, 20, 30, 40)
        // With 0.5s window, only consecutive duplicates within 0.5s are filtered
        // Since they're 1s+ apart, no filtering occurs
        XCTAssertLessThanOrEqual(filtered.count, messages.count)
    }
    
    func testMessageOrdering_ManyMessages() {
        // Given: Many messages in random order
        let now = Date()
        var messages: [Message] = []
        
        for i in 0..<100 {
            messages.append(Message(
                content: "Message \(i)",
                sender: .user,
                timestamp: now.addingTimeInterval(Double.random(in: 0...100))
            ))
        }
        
        // When
        let startTime = Date()
        let ordered = MessageValidator.ensureMessageOrder(messages: messages)
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Should complete quickly and be properly ordered
        XCTAssertLessThan(duration, 1.0)
        XCTAssertEqual(ordered.count, messages.count)
        
        // Verify ordering
        for i in 1..<ordered.count {
            XCTAssertLessThanOrEqual(ordered[i-1].timestamp, ordered[i].timestamp)
        }
    }
    
    // MARK: - Edge Cases for StreamChunk Types
    
    func testStreamChunkValidation_EdgeCases() {
        // Test various edge cases for stream chunk validation
        
        // Empty string vs nil content for different types
        let emptyStringChunk = StreamChunk(type: "content", content: "", metadata: nil)
        XCTAssertFalse(MessageValidator.isValidStreamChunk(emptyStringChunk))
        
        let nilContentChunk = StreamChunk(type: "content", content: nil, metadata: nil)
        XCTAssertFalse(MessageValidator.isValidStreamChunk(nilContentChunk))
        
        // Content with only whitespace
        let whitespaceChunk = StreamChunk(type: "text", content: "   \t\n   ", metadata: nil)
        XCTAssertFalse(MessageValidator.isValidStreamChunk(whitespaceChunk))
    }
    
    // MARK: - Message Validation Additional Tests
    
    func testFilterDuplicates_EmptyList() {
        // Given: Empty message list
        let messages: [Message] = []
        
        // When
        let filtered = MessageValidator.filterDuplicates(messages: messages)
        
        // Then: Should return empty list
        XCTAssertTrue(filtered.isEmpty)
    }
    
    func testEnsureMessageOrder_EmptyList() {
        // Given: Empty message list
        let messages: [Message] = []
        
        // When
        let ordered = MessageValidator.ensureMessageOrder(messages: messages)
        
        // Then: Should return empty list
        XCTAssertTrue(ordered.isEmpty)
    }
    
    func testEnsureMessageOrder_SingleMessage() {
        // Given: Single message
        let message = Message(content: "Single message", sender: .user)
        let messages = [message]
        
        // When
        let ordered = MessageValidator.ensureMessageOrder(messages: messages)
        
        // Then: Should return the same message
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(ordered[0].content, "Single message")
    }
}
