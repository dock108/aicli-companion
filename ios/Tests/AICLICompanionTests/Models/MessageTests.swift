import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessageTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - Message Initialization Tests
    
    func testMessageInitializationWithDefaults() throws {
        let message = Message(
            content: "Test message",
            sender: .user,
            type: .text
        )
        
        XCTAssertEqual(message.content, "Test message")
        XCTAssertEqual(message.sender, .user)
        XCTAssertEqual(message.type, .text)
        XCTAssertNotNil(message.id)
        XCTAssertNotNil(message.timestamp)
        XCTAssertNil(message.metadata)
        XCTAssertNil(message.streamingState)
        XCTAssertNil(message.requestId)
        XCTAssertNil(message.richContent)
        
        XCTAssertNil(message.cloudKitRecordID)
        XCTAssertEqual(message.readByDevices, [])
        XCTAssertEqual(message.deletedByDevices, [])
        XCTAssertNil(message.syncedAt)
        XCTAssertTrue(message.needsSync)
    }
    
    func testMessageInitializationWithAllParameters() throws {
        let id = UUID()
        let timestamp = Date()
        let metadata = TestDataFactory.createMessageMetadata()
        let streamingState = StreamingState.streaming
        let requestId = "test-request-123"
        
        let message = Message(
            id: id,
            content: "Full test message",
            sender: .assistant,
            timestamp: timestamp,
            type: .markdown,
            metadata: metadata,
            streamingState: streamingState,
            requestId: requestId,
            richContent: nil
        )
        
        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.content, "Full test message")
        XCTAssertEqual(message.sender, .assistant)
        XCTAssertEqual(message.timestamp, timestamp)
        XCTAssertEqual(message.type, .markdown)
        XCTAssertEqual(message.metadata?.sessionId, metadata.sessionId)
        XCTAssertEqual(message.streamingState, streamingState)
        XCTAssertEqual(message.requestId, requestId)
    }
    
    // MARK: - Message Codable Tests
    
    func testMessageEncodingAndDecoding() throws {
        let originalMessage = TestDataFactory.createUserMessage(
            content: "Test encoding message",
            sessionId: "encode-session-123"
        )
        
        // Encode message
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalMessage)
        
        // Decode message
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(Message.self, from: data)
        
        // Verify all coded properties are preserved
        XCTAssertEqual(decodedMessage.id, originalMessage.id)
        XCTAssertEqual(decodedMessage.content, originalMessage.content)
        XCTAssertEqual(decodedMessage.sender, originalMessage.sender)
        XCTAssertEqual(decodedMessage.timestamp.timeIntervalSince1970, originalMessage.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedMessage.type, originalMessage.type)
        XCTAssertEqual(decodedMessage.metadata?.sessionId, originalMessage.metadata?.sessionId)
        XCTAssertNil(decodedMessage.streamingState) // Not in original test message
        XCTAssertNil(decodedMessage.requestId) // Not in original test message
        XCTAssertNil(decodedMessage.richContent) // Not in original test message
        
        XCTAssertNil(decodedMessage.cloudKitRecordID)
        XCTAssertEqual(decodedMessage.readByDevices, [])
        XCTAssertEqual(decodedMessage.deletedByDevices, [])
        XCTAssertNil(decodedMessage.syncedAt)
        XCTAssertTrue(decodedMessage.needsSync)
    }
    
    func testMessageCodingExcludesCloudKitProperties() throws {
        var message = TestDataFactory.createAssistantMessage()
        
        // Set CloudKit properties
        message.readByDevices = ["device1", "device2"]
        message.deletedByDevices = ["device3"]
        message.syncedAt = Date()
        message.needsSync = false
        
        // Encode and decode
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(Message.self, from: data)
        
        XCTAssertEqual(decodedMessage.readByDevices, [])
        XCTAssertEqual(decodedMessage.deletedByDevices, [])
        XCTAssertNil(decodedMessage.syncedAt)
        XCTAssertTrue(decodedMessage.needsSync)
    }
    
    // MARK: - Rich Content Tests
    
    func testMessageWithCodeBlockRichContent() throws {
        let codeMessage = TestDataFactory.createCodeMessage(
            code: "def hello():\n    print('Hello, World!')",
            language: "python"
        )
        
        XCTAssertNotNil(codeMessage.richContent)
        XCTAssertEqual(codeMessage.richContent?.contentType, .codeBlock)
        
        if case .codeBlock(let codeBlock) = codeMessage.richContent?.data {
            XCTAssertEqual(codeBlock.code, "def hello():\n    print('Hello, World!')")
            XCTAssertEqual(codeBlock.language, "python")
            XCTAssertNil(codeBlock.filename)
            XCTAssertNil(codeBlock.startLine)
            XCTAssertNil(codeBlock.endLine)
        } else {
            XCTFail("Rich content should contain code block data")
        }
    }
    
    func testMessageWithToolResultRichContent() throws {
        let toolMessage = TestDataFactory.createToolResultMessage(
            toolName: "Read",
            output: "File content loaded successfully",
            success: true
        )
        
        XCTAssertNotNil(toolMessage.richContent)
        XCTAssertEqual(toolMessage.richContent?.contentType, .toolResult)
        
        if case .toolResult(let toolResult) = toolMessage.richContent?.data {
            XCTAssertEqual(toolResult.toolName, "Read")
            XCTAssertEqual(toolResult.output, "File content loaded successfully")
            XCTAssertTrue(toolResult.success)
            XCTAssertNil(toolResult.error)
        } else {
            XCTFail("Rich content should contain tool result data")
        }
    }
    
    // MARK: - Message Metadata Tests
    
    func testAICLIMessageMetadataInitialization() throws {
        let metadata = AICLIMessageMetadata(
            sessionId: "meta-session-123",
            duration: 2.5,
            cost: 0.002,
            tools: ["Read", "Write", "Edit"],
            queuedAt: Date().addingTimeInterval(-5),
            deliveredAt: Date().addingTimeInterval(-2),
            queuePriority: 2
        )
        
        XCTAssertEqual(metadata.sessionId, "meta-session-123")
        XCTAssertEqual(metadata.duration, 2.5, accuracy: 0.001)
        XCTAssertEqual(metadata.cost, 0.002)
        XCTAssertEqual(metadata.tools, ["Read", "Write", "Edit"])
        XCTAssertNotNil(metadata.queuedAt)
        XCTAssertNotNil(metadata.deliveredAt)
        XCTAssertEqual(metadata.queuePriority, 2)
        XCTAssertNil(metadata.additionalInfo)
    }
    
    func testAICLIMessageMetadataWithAdditionalInfo() throws {
        var metadata = TestDataFactory.createMessageMetadata()
        metadata.additionalInfo = [
            "model": "claude-3-sonnet",
            "temperature": 0.7,
            "maxTokens": 1000
        ]
        
        XCTAssertNotNil(metadata.additionalInfo)
        XCTAssertEqual(metadata.additionalInfo?["model"] as? String, "claude-3-sonnet")
        XCTAssertEqual(metadata.additionalInfo?["temperature"] as? Double, 0.7)
        XCTAssertEqual(metadata.additionalInfo?["maxTokens"] as? Int, 1000)
    }
    
    func testAICLIMessageMetadataCodable() throws {
        let metadata = TestDataFactory.createMessageMetadata(
            sessionId: "codable-session",
            duration: 1.8,
            cost: 0.0015
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)
        
        let decoder = JSONDecoder()
        let decodedMetadata = try decoder.decode(AICLIMessageMetadata.self, from: data)
        
        XCTAssertEqual(decodedMetadata.sessionId, metadata.sessionId)
        XCTAssertEqual(decodedMetadata.duration, metadata.duration, accuracy: 0.001)
        XCTAssertEqual(decodedMetadata.cost, metadata.cost)
        XCTAssertEqual(decodedMetadata.tools, metadata.tools)
    }
    
    // MARK: - Message Sender and Type Tests
    
    func testMessageSenderEnum() throws {
        XCTAssertEqual(MessageSender.user.rawValue, "user")
        XCTAssertEqual(MessageSender.assistant.rawValue, "assistant")
        XCTAssertEqual(MessageSender.system.rawValue, "system")
        
        // Test all cases are covered
        XCTAssertEqual(MessageSender.allCases.count, 3)
        XCTAssertTrue(MessageSender.allCases.contains(.user))
        XCTAssertTrue(MessageSender.allCases.contains(.assistant))
        XCTAssertTrue(MessageSender.allCases.contains(.system))
    }
    
    func testMessageTypeEnum() throws {
        XCTAssertEqual(MessageType.text.rawValue, "text")
        XCTAssertEqual(MessageType.markdown.rawValue, "markdown")
        XCTAssertEqual(MessageType.code.rawValue, "code")
        XCTAssertEqual(MessageType.fileContent.rawValue, "file_content")
        XCTAssertEqual(MessageType.commandOutput.rawValue, "command_output")
        XCTAssertEqual(MessageType.toolResult.rawValue, "tool_result")
        XCTAssertEqual(MessageType.error.rawValue, "error")
        XCTAssertEqual(MessageType.permission.rawValue, "permission")
        XCTAssertEqual(MessageType.toolUse.rawValue, "tool_use")
        XCTAssertEqual(MessageType.system.rawValue, "system")
        
        // Test all cases are covered
        XCTAssertEqual(MessageType.allCases.count, 10)
    }
    
    func testStreamingStateEnum() throws {
        XCTAssertEqual(StreamingState.pending.rawValue, "pending")
        XCTAssertEqual(StreamingState.streaming.rawValue, "streaming")
        XCTAssertEqual(StreamingState.completed.rawValue, "completed")
        XCTAssertEqual(StreamingState.failed.rawValue, "failed")
        
        // Test all cases are covered
        XCTAssertEqual(StreamingState.allCases.count, 4)
    }
    
    // MARK: - Rich Content Data Tests
    
    func testCodeBlockDataInitialization() throws {
        let codeBlock = CodeBlockData(
            code: "function test() { return true; }",
            language: "javascript",
            filename: "test.js",
            startLine: 10,
            endLine: 12
        )
        
        XCTAssertEqual(codeBlock.code, "function test() { return true; }")
        XCTAssertEqual(codeBlock.language, "javascript")
        XCTAssertEqual(codeBlock.filename, "test.js")
        XCTAssertEqual(codeBlock.startLine, 10)
        XCTAssertEqual(codeBlock.endLine, 12)
    }
    
    func testFileContentDataInitialization() throws {
        let fileContent = FileContentData(
            filename: "example.swift",
            filePath: "/path/to/example.swift",
            content: "import Foundation\n\nclass Example {}",
            language: "swift",
            lineCount: 3,
            size: 45
        )
        
        XCTAssertEqual(fileContent.filename, "example.swift")
        XCTAssertEqual(fileContent.filePath, "/path/to/example.swift")
        XCTAssertEqual(fileContent.content, "import Foundation\n\nclass Example {}")
        XCTAssertEqual(fileContent.language, "swift")
        XCTAssertEqual(fileContent.lineCount, 3)
        XCTAssertEqual(fileContent.size, 45)
    }
    
    func testToolResultDataWithSuccess() throws {
        let toolResult = ToolResultData(
            toolName: "Write",
            input: ["file_path": AnyCodable("/test/file.txt"), "content": AnyCodable("test content")],
            output: "File written successfully",
            success: true,
            error: nil,
            duration: 0.3
        )
        
        XCTAssertEqual(toolResult.toolName, "Write")
        XCTAssertNotNil(toolResult.input)
        XCTAssertEqual(toolResult.output, "File written successfully")
        XCTAssertTrue(toolResult.success)
        XCTAssertNil(toolResult.error)
        XCTAssertEqual(toolResult.duration, 0.3)
    }
    
    func testToolResultDataWithError() throws {
        let toolResult = ToolResultData(
            toolName: "Read",
            input: ["file_path": AnyCodable("/nonexistent/file.txt")],
            output: "",
            success: false,
            error: "File not found",
            duration: 0.1
        )
        
        XCTAssertEqual(toolResult.toolName, "Read")
        XCTAssertEqual(toolResult.output, "")
        XCTAssertFalse(toolResult.success)
        XCTAssertEqual(toolResult.error, "File not found")
        XCTAssertEqual(toolResult.duration, 0.1)
    }
    
    // MARK: - AnyCodable Tests
    
    func testAnyCodableWithString() throws {
        let stringValue = AnyCodable("test string")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(stringValue)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        XCTAssertEqual(decoded.value as? String, "test string")
    }
    
    func testAnyCodableWithNumber() throws {
        let numberValue = AnyCodable(42)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(numberValue)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        XCTAssertEqual(decoded.value as? Int, 42)
    }
    
    func testAnyCodableWithDictionary() throws {
        let dictValue = AnyCodable(["key1": "value1", "key2": 123])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(dictValue)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyCodable.self, from: data)
        
        guard let decodedDict = decoded.value as? [String: Any] else {
            XCTFail("Decoded value should be a dictionary")
            return
        }
        
        XCTAssertEqual(decodedDict["key1"] as? String, "value1")
        XCTAssertEqual(decodedDict["key2"] as? Int, 123)
    }
    
    // MARK: - Error Handling Tests
    
    func testMessageWithInvalidData() throws {
        // Test message with empty content
        let emptyMessage = Message(
            content: "",
            sender: .user,
            type: .text
        )
        
        XCTAssertEqual(emptyMessage.content, "")
        XCTAssertEqual(emptyMessage.sender, .user)
        XCTAssertEqual(emptyMessage.type, .text)
    }
    
    // MARK: - Performance Tests
    
    func testMessageCreationPerformance() throws {
        measure {
            for _ in 0..<1000 {
                _ = TestDataFactory.createUserMessage(
                    content: "Performance test message",
                    sessionId: "perf-session"
                )
            }
        }
    }
    
    func testMessageEncodingPerformance() throws {
        let messages = TestDataFactory.createMessageHistory(count: 100)
        let encoder = JSONEncoder()
        
        measure {
            for message in messages {
                _ = try? encoder.encode(message)
            }
        }
    }
}