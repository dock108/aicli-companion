import XCTest
import Foundation
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class WebSocketManagerTests: XCTestCase {
    
    // Helper to check if we're in CI
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
    }
    
    // MARK: - WebSocket Manager Creation Tests
    
    func testWebSocketManagerExists() {
        // Test that we can reference the WebSocketManager
        let managerType = WebSocketManager.self
        XCTAssertNotNil(managerType)
    }
    
    // MARK: - WebSocket Message Processing Tests
    
    func testWebSocketMessageCreation() {
        // Test WebSocket message structure with subscribe request
        let subscribeRequest = SubscribeRequest(events: ["heartbeat", "status"])
        let message = WebSocketMessage(
            type: .subscribe,
            data: .subscribe(subscribeRequest)
        )
        
        XCTAssertEqual(message.type.rawValue, "subscribe")
        if case .subscribe(let request) = message.data! {
            XCTAssertEqual(request.events, ["heartbeat", "status"])
        } else {
            XCTFail("Expected subscribe data")
        }
    }
    
    func testWebSocketMessageWithAskRequest() {
        // Test WebSocket message with ask request
        let askRequest = AskRequest(message: "Hello Claude", options: nil)
        let message = WebSocketMessage(
            type: .ask,
            data: .ask(askRequest)
        )
        
        XCTAssertEqual(message.type.rawValue, "ask")
        if case .ask(let request) = message.data! {
            XCTAssertEqual(request.message, "Hello Claude")
        } else {
            XCTFail("Expected ask data")
        }
    }
    
    func testWebSocketMessageTypes() {
        // Test WebSocket message types
        let requestTypes: [WebSocketMessageType] = [
            .ask, .streamStart, .streamSend, .streamClose, .permission,
            .ping, .subscribe, .setWorkingDirectory, .claudeCommand, 
            .getMessageHistory, .acknowledgeMessages, .clearChat
        ]
        
        let responseTypes: [WebSocketMessageType] = [
            .welcome, .askResponse, .streamStarted, .streamData, .streamComplete,
            .error, .sessionStatus, .pong, .subscribed, .systemInit,
            .assistantMessage, .toolUse, .toolResult, .conversationResult,
            .workingDirectorySet, .claudeCommandResponse, .messageHistory,
            .messagesAcknowledged, .chatCleared, .progress, .streamToolUse,
            .streamChunk, .permissionRequest
        ]
        
        for messageType in requestTypes + responseTypes {
            XCTAssertNotNil(messageType.rawValue)
            XCTAssertFalse(messageType.rawValue.isEmpty)
        }
        
        // Test specific values
        XCTAssertEqual(WebSocketMessageType.ask.rawValue, "ask")
        XCTAssertEqual(WebSocketMessageType.subscribe.rawValue, "subscribe")
        XCTAssertEqual(WebSocketMessageType.welcome.rawValue, "welcome")
        XCTAssertEqual(WebSocketMessageType.error.rawValue, "error")
    }
    
    // MARK: - Request Model Tests
    
    func testSubscribeRequest() throws {
        let request = SubscribeRequest(events: ["heartbeat", "status"])
        XCTAssertEqual(request.events, ["heartbeat", "status"])
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SubscribeRequest.self, from: data)
        XCTAssertEqual(decoded.events, request.events)
    }
    
    func testAskRequest() throws {
        let request = AskRequest(message: "Test question", options: nil)
        XCTAssertEqual(request.message, "Test question")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(AskRequest.self, from: data)
        XCTAssertEqual(decoded.message, request.message)
    }
    
    func testStreamStartRequest() throws {
        let request = StreamStartRequest(message: "Start streaming", options: nil)
        XCTAssertEqual(request.message, "Start streaming")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(StreamStartRequest.self, from: data)
        XCTAssertEqual(decoded.message, request.message)
    }
    
    func testStreamSendRequest() throws {
        let request = StreamSendRequest(message: "Stream content")
        XCTAssertEqual(request.message, "Stream content")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(StreamSendRequest.self, from: data)
        XCTAssertEqual(decoded.message, request.message)
    }
    
    func testStreamCloseRequest() throws {
        let request = StreamCloseRequest(reason: "User cancelled")
        XCTAssertEqual(request.reason, "User cancelled")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(StreamCloseRequest.self, from: data)
        XCTAssertEqual(decoded.reason, request.reason)
    }
    
    // MARK: - Response Model Tests
    
    func testStreamDataResponse() throws {
        let streamContent = StreamContent(type: "text", text: "Stream data chunk")
        let response = StreamDataResponse(
            content: [streamContent],
            streamId: "response-stream-123"
        )
        
        XCTAssertEqual(response.content.count, 1)
        XCTAssertEqual(response.content[0].type, "text")
        XCTAssertEqual(response.content[0].text, "Stream data chunk")
        XCTAssertEqual(response.streamId, "response-stream-123")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(StreamDataResponse.self, from: data)
        XCTAssertEqual(decoded.content.count, response.content.count)
        XCTAssertEqual(decoded.streamId, response.streamId)
    }
    
    func testErrorResponse() throws {
        let errorResponse = ErrorResponse(
            message: "Connection failed",
            code: "CONN_ERROR"
        )
        
        XCTAssertEqual(errorResponse.message, "Connection failed")
        XCTAssertEqual(errorResponse.code, "CONN_ERROR")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(errorResponse)
        let decoded = try JSONDecoder().decode(ErrorResponse.self, from: data)
        XCTAssertEqual(decoded.message, errorResponse.message)
        XCTAssertEqual(decoded.code, errorResponse.code)
    }
    
    func testWelcomeResponse() throws {
        let welcomeResponse = WelcomeResponse(
            serverVersion: "1.0.0",
            supportedFeatures: ["streaming", "attachments"],
            sessionId: "welcome-session"
        )
        
        XCTAssertEqual(welcomeResponse.serverVersion, "1.0.0")
        XCTAssertEqual(welcomeResponse.supportedFeatures, ["streaming", "attachments"])
        XCTAssertEqual(welcomeResponse.sessionId, "welcome-session")
        
        // Test encoding/decoding
        let data = try JSONEncoder().encode(welcomeResponse)
        let decoded = try JSONDecoder().decode(WelcomeResponse.self, from: data)
        XCTAssertEqual(decoded.serverVersion, welcomeResponse.serverVersion)
        XCTAssertEqual(decoded.supportedFeatures, welcomeResponse.supportedFeatures)
        XCTAssertEqual(decoded.sessionId, welcomeResponse.sessionId)
    }
    
    // MARK: - URL Validation Tests
    
    func testWebSocketURLValidation() {
        let validURLs = [
            "ws://localhost:3000/ws",
            "wss://secure.example.com/websocket", 
            "ws://192.168.1.100:8080/stream"
        ]
        
        let invalidURLs = [
            "",
            "not-a-url",
            "http://example.com", // Not WebSocket protocol
            "ftp://example.com"
        ]
        
        for urlString in validURLs {
            guard let url = URL(string: urlString) else {
                XCTFail("Should create valid WebSocket URL: \(urlString)")
                continue
            }
            XCTAssertTrue(url.scheme == "ws" || url.scheme == "wss")
        }
        
        for urlString in invalidURLs {
            if let url = URL(string: urlString) {
                XCTAssertFalse(url.scheme == "ws" || url.scheme == "wss")
            }
        }
    }
    
    // MARK: - Message Queue Logic Tests
    
    func testMessageQueueing() {
        // Test message queuing logic
        var messageQueue: [WebSocketMessage] = []
        
        let subscribeData = SubscribeRequest(events: ["heartbeat"])
        let askData = AskRequest(message: "Queue test", options: nil)
        let closeData = StreamCloseRequest(reason: "Test close")
        
        let messages = [
            WebSocketMessage(type: .subscribe, data: .subscribe(subscribeData)),
            WebSocketMessage(type: .ask, data: .ask(askData)),
            WebSocketMessage(type: .streamClose, data: .streamClose(closeData))
        ]
        
        // Add messages to queue
        for message in messages {
            messageQueue.append(message)
        }
        
        XCTAssertEqual(messageQueue.count, 3)
        XCTAssertEqual(messageQueue[0].type.rawValue, "subscribe")
        XCTAssertEqual(messageQueue[1].type.rawValue, "ask")
        XCTAssertEqual(messageQueue[2].type.rawValue, "stream_close")
        
        // Process queue (FIFO)
        let firstMessage = messageQueue.removeFirst()
        XCTAssertEqual(firstMessage.type.rawValue, "subscribe")
        XCTAssertEqual(messageQueue.count, 2)
    }
    
    // MARK: - Data Streaming Tests
    
    func testStreamContentTypes() {
        // Test different stream content types
        let textContent = StreamContent(type: "text", text: "Hello world")
        let codeContent = StreamContent(type: "code", text: "let x = 42")
        let toolContent = StreamContent(type: "tool_use", text: nil)
        
        XCTAssertEqual(textContent.type, "text")
        XCTAssertEqual(textContent.text, "Hello world")
        
        XCTAssertEqual(codeContent.type, "code")
        XCTAssertEqual(codeContent.text, "let x = 42")
        
        XCTAssertEqual(toolContent.type, "tool_use")
        XCTAssertNil(toolContent.text)
    }
    
    func testStreamDataAccumulation() {
        // Test accumulating stream data chunks
        var accumulatedContent = ""
        let streamChunks = [
            StreamContent(type: "text", text: "Hello "),
            StreamContent(type: "text", text: "streaming "),
            StreamContent(type: "text", text: "world!"),
            StreamContent(type: "text", text: " Complete.")
        ]
        
        for chunk in streamChunks {
            if let text = chunk.text {
                accumulatedContent += text
            }
        }
        
        XCTAssertEqual(accumulatedContent, "Hello streaming world! Complete.")
    }
    
    // MARK: - Error Handling Tests
    
    func testWebSocketErrorCodes() {
        // Test WebSocket error codes
        let errorCodes = [
            ("CONN_FAILED", "Connection failed"),
            ("AUTH_ERROR", "Authentication error"),
            ("TIMEOUT", "Request timeout"),
            ("INVALID_MESSAGE", "Invalid message format"),
            ("SERVER_ERROR", "Internal server error"),
            ("RATE_LIMITED", "Too many requests")
        ]
        
        for (code, message) in errorCodes {
            let error = ErrorResponse(message: message, code: code)
            XCTAssertEqual(error.code, code)
            XCTAssertEqual(error.message, message)
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertFalse(error.code?.isEmpty ?? true)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentMessageProcessing() throws {
        guard !isCI else {
            throw XCTSkip("Skipping concurrent test in CI environment")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent message processing")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue(label: "websocket.test.concurrent", attributes: .concurrent)
        var processedMessages: [String] = []
        let serialQueue = DispatchQueue(label: "websocket.test.serial")
        
        for i in 0..<10 {
            queue.async {
                let askData = AskRequest(message: "Concurrent message \(i)", options: nil)
                _ = WebSocketMessage(type: .ask, data: .ask(askData))
                
                serialQueue.async {
                    processedMessages.append("processed-\(i)")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 3.0)
        XCTAssertEqual(processedMessages.count, 10)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfMessageSerialization() throws {
        guard !isCI else {
            throw XCTSkip("Skipping performance test in CI environment")
        }
        
        measure {
            for i in 0..<100 {
                let askData = AskRequest(message: "Performance test message \(i)", options: nil)
                let message = WebSocketMessage(type: .ask, data: .ask(askData))
                
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(message)
                    XCTAssertFalse(data.isEmpty)
                } catch {
                    XCTFail("Serialization should not fail: \(error)")
                }
            }
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testEdgeCaseHandling() {
        // Empty message content
        let emptyAsk = AskRequest(message: "", options: nil)
        XCTAssertTrue(emptyAsk.message.isEmpty)
        
        // Very long message
        let longMessage = String(repeating: "A", count: 10000)
        let longAsk = AskRequest(message: longMessage, options: nil)
        XCTAssertEqual(longAsk.message.count, 10000)
        
        // Unicode content
        let unicodeAsk = AskRequest(message: "Hello 世界 🌍", options: nil)
        XCTAssertTrue(unicodeAsk.message.contains("世界"))
        XCTAssertTrue(unicodeAsk.message.contains("🌍"))
        
        // Special characters
        let specialAsk = AskRequest(message: "Test with \"quotes\", <tags>, & symbols", options: nil)
        XCTAssertTrue(specialAsk.message.contains("\""))
        XCTAssertTrue(specialAsk.message.contains("<"))
        XCTAssertTrue(specialAsk.message.contains("&"))
    }
    
    func testStreamIdGeneration() {
        // Test stream ID uniqueness
        var streamIds = Set<String>()
        
        for i in 0..<1000 {
            let streamId = "stream-\(i)-\(UUID().uuidString)"
            XCTAssertFalse(streamIds.contains(streamId), "Stream IDs should be unique")
            streamIds.insert(streamId)
        }
        
        XCTAssertEqual(streamIds.count, 1000, "All stream IDs should be unique")
    }
    
    func testMessageDataEnumCases() {
        // Test WebSocketMessageData enum cases
        let subscribeData = SubscribeRequest(events: ["data-test"])
        let askData = AskRequest(message: "Data test", options: nil)
        
        // Test enum case creation
        let subscribeCase = WebSocketMessageData.subscribe(subscribeData)
        let askCase = WebSocketMessageData.ask(askData)
        
        // Test in WebSocketMessage
        let subscribeMessage = WebSocketMessage(type: .subscribe, data: subscribeCase)
        let askMessage = WebSocketMessage(type: .ask, data: askCase)
        
        XCTAssertEqual(subscribeMessage.type.rawValue, "subscribe")
        XCTAssertEqual(askMessage.type.rawValue, "ask")
        XCTAssertNotNil(subscribeMessage.data)
        XCTAssertNotNil(askMessage.data)
    }
}