import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class MessageCoreTests: XCTestCase {
    // MARK: - Message Tests
    
    func testMessageInitialization() {
        let id = UUID()
        let content = "Test message content"
        let sender = MessageSender.user
        let timestamp = Date()
        let type = MessageType.text
        
        let message = Message(
            id: id,
            content: content,
            sender: sender,
            timestamp: timestamp,
            type: type
        )
        
        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.content, content)
        XCTAssertEqual(message.sender, sender)
        XCTAssertEqual(message.timestamp, timestamp)
        XCTAssertEqual(message.type, type)
        XCTAssertNil(message.metadata)
        XCTAssertNil(message.streamingState)
        XCTAssertNil(message.requestId)
        XCTAssertNil(message.richContent)
    }
    
    func testMessageWithDefaults() {
        let message = Message(
            content: "Test",
            sender: .assistant,
            type: .markdown
        )
        
        XCTAssertNotNil(message.id)
        XCTAssertEqual(message.content, "Test")
        XCTAssertEqual(message.sender, .assistant)
        XCTAssertNotNil(message.timestamp)
        XCTAssertEqual(message.type, .markdown)
    }
    
    func testMessageWithAttachments() {
        let attachmentData = AttachmentData(
            id: UUID(),
            type: .image,
            name: "test.jpg",
            data: Data("test data".utf8),
            mimeType: "image/jpeg",
            size: 100
        )
        
        let message = Message(
            content: "Message with attachment",
            sender: .user,
            attachments: [attachmentData]
        )
        
        XCTAssertNotNil(message.richContent)
        if case .attachments(let attachmentsData) = message.richContent?.data {
            XCTAssertEqual(attachmentsData.attachments.count, 1)
            XCTAssertEqual(attachmentsData.attachments[0].name, "test.jpg")
            XCTAssertEqual(attachmentsData.attachments[0].mimeType, "image/jpeg")
        } else {
            XCTFail("Rich content should contain attachments")
        }
    }
    
    func testMessageCodable() throws {
        let original = Message(
            content: "Codable test",
            sender: .system,
            type: .error,
            requestId: "req-123"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Message.self, from: data)
        
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.sender, original.sender)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.requestId, original.requestId)
    }
    
    // MARK: - MessageSender Tests
    
    func testMessageSenderAllCases() {
        XCTAssertEqual(MessageSender.allCases.count, 3)
        XCTAssertTrue(MessageSender.allCases.contains(.user))
        XCTAssertTrue(MessageSender.allCases.contains(.assistant))
        XCTAssertTrue(MessageSender.allCases.contains(.system))
    }
    
    func testMessageSenderRawValues() {
        XCTAssertEqual(MessageSender.user.rawValue, "user")
        XCTAssertEqual(MessageSender.assistant.rawValue, "assistant")
        XCTAssertEqual(MessageSender.system.rawValue, "system")
    }
    
    func testMessageSenderCodable() throws {
        let senders: [MessageSender] = [.user, .assistant, .system]
        
        for sender in senders {
            let encoder = JSONEncoder()
            let data = try encoder.encode(sender)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MessageSender.self, from: data)
            
            XCTAssertEqual(decoded, sender)
        }
    }
    
    // MARK: - MessageType Tests
    
    func testMessageTypeAllCases() {
        XCTAssertEqual(MessageType.allCases.count, 11)
        
        let expectedTypes: [MessageType] = [
            .text, .markdown, .code, .error, .system,
            .file, .command, .audio, .stream, .toolUse, .toolResult
        ]
        
        for type in expectedTypes {
            XCTAssertTrue(MessageType.allCases.contains(type))
        }
    }
    
    func testMessageTypeRawValues() {
        XCTAssertEqual(MessageType.text.rawValue, "text")
        XCTAssertEqual(MessageType.markdown.rawValue, "markdown")
        XCTAssertEqual(MessageType.code.rawValue, "code")
        XCTAssertEqual(MessageType.error.rawValue, "error")
        XCTAssertEqual(MessageType.system.rawValue, "system")
        XCTAssertEqual(MessageType.file.rawValue, "file")
        XCTAssertEqual(MessageType.command.rawValue, "command")
        XCTAssertEqual(MessageType.audio.rawValue, "audio")
        XCTAssertEqual(MessageType.stream.rawValue, "stream")
        XCTAssertEqual(MessageType.toolUse.rawValue, "toolUse")
        XCTAssertEqual(MessageType.toolResult.rawValue, "toolResult")
    }
    
    // MARK: - StreamingState Tests
    
    func testStreamingStateAllCases() {
        XCTAssertEqual(StreamingState.allCases.count, 4)
        XCTAssertTrue(StreamingState.allCases.contains(.none))
        XCTAssertTrue(StreamingState.allCases.contains(.streaming))
        XCTAssertTrue(StreamingState.allCases.contains(.complete))
        XCTAssertTrue(StreamingState.allCases.contains(.error))
    }
    
    func testStreamingStateRawValues() {
        XCTAssertEqual(StreamingState.none.rawValue, "none")
        XCTAssertEqual(StreamingState.streaming.rawValue, "streaming")
        XCTAssertEqual(StreamingState.complete.rawValue, "complete")
        XCTAssertEqual(StreamingState.error.rawValue, "error")
    }
    
    // MARK: - Metadata Tests
    
    func testAICLIMessageMetadataInitialization() {
        let sessionId = "session-123"
        let duration: TimeInterval = 5.5
        let queuedAt = Date()
        let deliveredAt = Date().addingTimeInterval(1)
        
        let metadata = AICLIMessageMetadata(
            sessionId: sessionId,
            duration: duration,
            queuedAt: queuedAt,
            deliveredAt: deliveredAt
        )
        
        XCTAssertEqual(metadata.sessionId, sessionId)
        XCTAssertEqual(metadata.duration, duration)
        XCTAssertEqual(metadata.queuedAt, queuedAt)
        XCTAssertEqual(metadata.deliveredAt, deliveredAt)
        XCTAssertNil(metadata.additionalInfo)
        XCTAssertNil(metadata.statusMetadata)
    }
    
    func testMessageWithMetadata() {
        let metadata = AICLIMessageMetadata(
            sessionId: "test-session",
            duration: 2.5
        )
        
        let message = Message(
            content: "Message with metadata",
            sender: .assistant,
            metadata: metadata
        )
        
        XCTAssertNotNil(message.metadata)
        XCTAssertEqual(message.metadata?.sessionId, "test-session")
        XCTAssertEqual(message.metadata?.duration, 2.5)
    }
    
    func testMessageWithStreamingState() {
        let message = Message(
            content: "Streaming message",
            sender: .assistant,
            streamingState: .streaming
        )
        
        XCTAssertEqual(message.streamingState, .streaming)
    }
    
    // MARK: - Integration Tests
    
    func testComplexMessage() {
        let metadata = AICLIMessageMetadata(
            sessionId: "complex-session",
            duration: 10.5
        )
        
        let message = Message(
            content: "Complex message",
            sender: .assistant,
            type: .markdown,
            metadata: metadata,
            streamingState: .complete,
            requestId: "req-456"
        )
        
        XCTAssertEqual(message.content, "Complex message")
        XCTAssertEqual(message.sender, .assistant)
        XCTAssertEqual(message.type, .markdown)
        XCTAssertEqual(message.metadata?.sessionId, "complex-session")
        XCTAssertEqual(message.streamingState, .complete)
        XCTAssertEqual(message.requestId, "req-456")
    }
    
    func testMessageArrayOperations() {
        var messages: [Message] = []
        
        let message1 = Message(content: "First", sender: .user)
        let message2 = Message(content: "Second", sender: .assistant)
        let message3 = Message(content: "Third", sender: .system, type: .system)
        
        messages.append(message1)
        messages.append(message2)
        messages.append(message3)
        
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].content, "First")
        XCTAssertEqual(messages[1].sender, .assistant)
        XCTAssertEqual(messages[2].type, .system)
        
        // Test filtering
        let userMessages = messages.filter { $0.sender == .user }
        XCTAssertEqual(userMessages.count, 1)
        
        let systemMessages = messages.filter { $0.type == .system }
        XCTAssertEqual(systemMessages.count, 1)
    }
}
