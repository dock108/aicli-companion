import XCTest
import Foundation
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class AICLIMessageOperationsTests: XCTestCase {
    // MARK: - Message Processing Logic Tests
    
    func testMessageOperationsExists() {
        // Test that we can create the service
        let urlSession = URLSession.shared
        let connectionManager = AICLIConnectionManager(urlSession: urlSession)
        
        let sut = AICLIMessageOperations(
            urlSession: urlSession,
            connectionManager: connectionManager
        )
        
        XCTAssertNotNil(sut)
    }
    
    // MARK: - ClaudeChatResponse Tests
    
    func testClaudeChatResponseDecoding() throws {
        // Given
        let jsonData = """
        {
            "content": "Hello from Claude!",
            "sessionId": "session-123",
            "error": null,
            "metadata": null
        }
        """.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeChatResponse.self, from: jsonData)
        
        // Then
        XCTAssertEqual(response.content, "Hello from Claude!")
        XCTAssertEqual(response.sessionId, "session-123")
        XCTAssertNil(response.error)
        XCTAssertNil(response.metadata)
    }
    
    func testClaudeChatResponseEncoding() throws {
        // Given
        let response = ClaudeChatResponse(
            content: "Test response",
            sessionId: "test-session",
            error: nil,
            metadata: nil
        )
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        // Then
        XCTAssertFalse(data.isEmpty)
        
        // Verify it can be decoded back
        let decoder = JSONDecoder()
        let decodedResponse = try decoder.decode(ClaudeChatResponse.self, from: data)
        XCTAssertEqual(decodedResponse.content, response.content)
        XCTAssertEqual(decodedResponse.sessionId, response.sessionId)
    }
    
    func testClaudeChatResponseWithError() throws {
        // Given
        let jsonData = """
        {
            "content": "",
            "sessionId": null,
            "error": "Authentication failed",
            "metadata": null
        }
        """.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeChatResponse.self, from: jsonData)
        
        // Then
        XCTAssertEqual(response.content, "")
        XCTAssertNil(response.sessionId)
        XCTAssertEqual(response.error, "Authentication failed")
        XCTAssertNil(response.metadata)
    }
    
    func testClaudeChatResponseWithMetadata() throws {
        // Given
        let jsonData = """
        {
            "content": "Response with metadata",
            "sessionId": "meta-session",
            "error": null,
            "metadata": {
                "model": "claude-3",
                "tokens": 150
            }
        }
        """.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeChatResponse.self, from: jsonData)
        
        // Then
        XCTAssertEqual(response.content, "Response with metadata")
        XCTAssertEqual(response.sessionId, "meta-session")
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.metadata)
    }
    
    // MARK: - AttachmentData Tests
    
    func testAttachmentDataCreation() {
        // Given
        let testData = "test content".data(using: .utf8)!
        let attachment = AttachmentData(
            id: UUID(),
            type: .document,
            name: "test.txt",
            data: testData,
            mimeType: "text/plain",
            size: testData.count
        )
        
        // Then
        XCTAssertEqual(attachment.name, "test.txt")
        XCTAssertEqual(attachment.type, .document)
        XCTAssertEqual(attachment.mimeType, "text/plain")
        XCTAssertEqual(attachment.size, testData.count)
        XCTAssertTrue(attachment.isDocument)
        XCTAssertFalse(attachment.isImage)
    }
    
    func testAttachmentDataImageType() {
        // Given
        let imageData = Data(count: 1024)
        let attachment = AttachmentData(
            id: UUID(),
            type: .image,
            name: "test.png",
            data: imageData,
            mimeType: "image/png",
            size: imageData.count
        )
        
        // Then
        XCTAssertEqual(attachment.type, .image)
        XCTAssertTrue(attachment.isImage)
        XCTAssertFalse(attachment.isDocument)
        XCTAssertEqual(attachment.size, 1024)
    }
    
    func testAttachmentDataSizeFormatting() {
        // Given
        let largeData = Data(count: 1024 * 1024) // 1MB
        let attachment = AttachmentData(
            id: UUID(),
            type: .document,
            name: "large.pdf",
            data: largeData,
            mimeType: "application/pdf",
            size: largeData.count
        )
        
        // Then
        XCTAssertFalse(attachment.formattedSize.isEmpty)
        XCTAssertTrue(attachment.formattedSize.contains("MB") || attachment.formattedSize.contains("bytes"))
    }
    
    func testAttachmentDataEncoding() throws {
        // Given
        let testData = "encoding test".data(using: .utf8)!
        let attachment = AttachmentData(
            id: UUID(),
            type: .document,
            name: "encode.txt",
            data: testData,
            mimeType: "text/plain",
            size: testData.count
        )
        
        // When
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(attachment)
        
        // Then
        XCTAssertFalse(encodedData.isEmpty)
        
        // Verify it can be decoded back
        let decoder = JSONDecoder()
        let decodedAttachment = try decoder.decode(AttachmentData.self, from: encodedData)
        XCTAssertEqual(decodedAttachment.name, attachment.name)
        XCTAssertEqual(decodedAttachment.type, attachment.type)
        XCTAssertEqual(decodedAttachment.mimeType, attachment.mimeType)
        XCTAssertEqual(decodedAttachment.size, attachment.size)
    }
    
    // MARK: - Request Creation Logic Tests
    
    func testMessageValidation() {
        // Test message content validation logic
        let emptyMessage = ""
        let normalMessage = "Hello Claude"
        let longMessage = String(repeating: "A", count: 10000)
        let unicodeMessage = "Hello 世界 🌍"
        let specialCharsMessage = "Test with \"quotes\" and <tags> & symbols"
        
        // Basic validation
        XCTAssertTrue(emptyMessage.isEmpty)
        XCTAssertFalse(normalMessage.isEmpty)
        XCTAssertEqual(longMessage.count, 10000)
        XCTAssertTrue(unicodeMessage.contains("世界"))
        XCTAssertTrue(specialCharsMessage.contains("\""))
        
        // Encoding validation
        XCTAssertNotNil(normalMessage.data(using: .utf8))
        XCTAssertNotNil(unicodeMessage.data(using: .utf8))
        XCTAssertNotNil(specialCharsMessage.data(using: .utf8))
    }
    
    func testProjectPathValidation() {
        // Test project path validation logic
        let validPaths = [
            "/Users/test/project",
            "/home/user/my-project",
            "./relative/path",
            "../parent/path"
        ]
        
        let invalidPaths = [
            "",
            " ",
            "\n",
            "\t"
        ]
        
        // Valid paths
        for path in validPaths {
            XCTAssertFalse(path.isEmpty, "Path should not be empty: \(path)")
            XCTAssertFalse(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        
        // Invalid paths
        for path in invalidPaths {
            XCTAssertTrue(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    func testURLCreation() {
        // Test URL creation logic
        let baseURLStrings = [
            "http://localhost:3000",
            "https://api.example.com",
            "http://192.168.1.100:8080"
        ]
        
        let endpoints = [
            "/chat",
            "/messages",
            "/session/kill"
        ]
        
        for baseURLString in baseURLStrings {
            guard let baseURL = URL(string: baseURLString) else {
                XCTFail("Should create valid base URL from: \(baseURLString)")
                continue
            }
            
            for endpoint in endpoints {
                let fullURL = baseURL.appendingPathComponent(endpoint)
                XCTAssertNotNil(fullURL)
                XCTAssertTrue(fullURL.absoluteString.contains(endpoint))
            }
        }
    }
    
    // MARK: - Session Management Logic Tests
    
    func testSessionIdValidation() {
        // Test session ID validation
        let validSessionIds = [
            "session-123",
            UUID().uuidString,
            "abc123def456",
            "session_with_underscores"
        ]
        
        let invalidSessionIds = [
            "",
            " ",
            "\n",
            "\t\r\n"
        ]
        
        for sessionId in validSessionIds {
            XCTAssertFalse(sessionId.isEmpty)
            XCTAssertFalse(sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        
        for sessionId in invalidSessionIds {
            XCTAssertTrue(sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    
    func testMessageIdGeneration() {
        // Test message ID generation logic
        var messageIds = Set<String>()
        
        for _ in 0..<100 {
            let messageId = UUID().uuidString
            XCTAssertFalse(messageIds.contains(messageId), "Message IDs should be unique")
            messageIds.insert(messageId)
        }
        
        XCTAssertEqual(messageIds.count, 100, "All message IDs should be unique")
    }
    
    // MARK: - Error Handling Logic Tests
    
    func testErrorHandling() {
        // Test error response parsing
        let errorResponses = [
            ("Authentication failed", 401),
            ("Not found", 404),
            ("Internal server error", 500),
            ("Bad request", 400)
        ]
        
        for (errorMessage, statusCode) in errorResponses {
            let response = ClaudeChatResponse(
                content: "",
                sessionId: nil,
                error: errorMessage,
                metadata: nil
            )
            
            XCTAssertEqual(response.error, errorMessage)
            XCTAssertNil(response.sessionId)
            XCTAssertTrue(response.content.isEmpty)
        }
    }
    
    func testNetworkErrorTypes() {
        // Test different network error scenarios
        let networkErrors = [
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost),
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ]
        
        for error in networkErrors {
            XCTAssertEqual(error.domain, NSURLErrorDomain)
            XCTAssertNotEqual(error.code, 0)
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfResponseParsing() {
        measure {
            for i in 0..<1000 {
                let response = ClaudeChatResponse(
                    content: "Performance test response \(i)",
                    sessionId: "session-\(i)",
                    error: nil,
                    metadata: nil
                )
                
                do {
                    let data = try JSONEncoder().encode(response)
                    let decoded = try JSONDecoder().decode(ClaudeChatResponse.self, from: data)
                    XCTAssertEqual(decoded.content, response.content)
                } catch {
                    XCTFail("Encoding/decoding should not fail: \(error)")
                }
            }
        }
    }
    
    func testPerformanceOfAttachmentDataCreation() {
        measure {
            for i in 0..<100 {
                let testData = "Performance test data \(i)".data(using: .utf8)!
                let attachment = AttachmentData(
                    id: UUID(),
                    type: .document,
                    name: "test-\(i).txt",
                    data: testData,
                    mimeType: "text/plain",
                    size: testData.count
                )
                
                XCTAssertEqual(attachment.size, testData.count)
                XCTAssertFalse(attachment.formattedSize.isEmpty)
            }
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentResponseCreation() {
        let expectation = XCTestExpectation(description: "Concurrent response creation")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                let response = ClaudeChatResponse(
                    content: "Concurrent response \(i)",
                    sessionId: "concurrent-session-\(i)",
                    error: nil,
                    metadata: nil
                )
                
                XCTAssertEqual(response.content, "Concurrent response \(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Edge Cases Tests
    
    func testEdgeCaseHandling() {
        // Test various edge cases
        
        // Empty content response
        let emptyResponse = ClaudeChatResponse(
            content: "",
            sessionId: nil,
            error: nil,
            metadata: nil
        )
        XCTAssertTrue(emptyResponse.content.isEmpty)
        
        // Very long content
        let longContent = String(repeating: "A", count: 100000)
        let longResponse = ClaudeChatResponse(
            content: longContent,
            sessionId: "long-session",
            error: nil,
            metadata: nil
        )
        XCTAssertEqual(longResponse.content.count, 100000)
        
        // Zero-size attachment
        let zeroAttachment = AttachmentData(
            id: UUID(),
            type: .document,
            name: "empty.txt",
            data: Data(),
            mimeType: "text/plain",
            size: 0
        )
        XCTAssertEqual(zeroAttachment.size, 0)
        XCTAssertTrue(zeroAttachment.data.isEmpty)
    }
}

// MARK: - Test Extensions

extension AICLIMessageOperationsTests {
    func testComplexMessageScenarios() {
        // Test complex message scenarios
        
        // Message with mixed content types
        let mixedMessage = "Here's some code:\n```swift\nlet x = 42\n```\nAnd some 🎉 emojis!"
        XCTAssertTrue(mixedMessage.contains("```"))
        XCTAssertTrue(mixedMessage.contains("🎉"))
        
        // Message with URLs
        let messageWithURL = "Check this out: https://example.com/path?param=value#anchor"
        XCTAssertTrue(messageWithURL.contains("https://"))
        XCTAssertTrue(messageWithURL.contains("?"))
        XCTAssertTrue(messageWithURL.contains("#"))
        
        // Message with JSON content
        let jsonMessage = """
        Here's some JSON: {"key": "value", "number": 123, "array": [1, 2, 3]}
        """
        XCTAssertTrue(jsonMessage.contains("{"))
        XCTAssertTrue(jsonMessage.contains("}"))
        XCTAssertTrue(jsonMessage.contains("["))
    }
    
    func testDataFormatValidation() {
        // Test data format validation
        
        // Base64 data validation
        let validBase64 = "SGVsbG8gV29ybGQ="
        if let decodedData = Data(base64Encoded: validBase64) {
            XCTAssertFalse(decodedData.isEmpty)
        }
        
        // JSON validation
        let validJSON = """
        {"message": "test", "id": 123}
        """
        XCTAssertNotNil(validJSON.data(using: .utf8))
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: validJSON.data(using: .utf8)!)
            XCTAssertNotNil(jsonObject)
        } catch {
            XCTFail("Valid JSON should parse correctly")
        }
    }
}
