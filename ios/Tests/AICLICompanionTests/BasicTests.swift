import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class BasicTests: XCTestCase {
    // MARK: - Basic Functionality Tests
    
    func testBasicAssertions() throws {
        XCTAssertTrue(true)
        XCTAssertFalse(false)
        XCTAssertEqual(1 + 1, 2)
    }
    
    func testMessageSenderEnum() throws {
        XCTAssertEqual(MessageSender.user.rawValue, "user")
        XCTAssertEqual(MessageSender.assistant.rawValue, "assistant")
        XCTAssertEqual(MessageSender.system.rawValue, "system")
        
        XCTAssertEqual(MessageSender.allCases.count, 3)
    }
    
    func testMessageTypeEnum() throws {
        XCTAssertEqual(MessageType.text.rawValue, "text")
        XCTAssertEqual(MessageType.markdown.rawValue, "markdown")
        XCTAssertEqual(MessageType.code.rawValue, "code")
        
        XCTAssertEqual(MessageType.allCases.count, 11)
    }
    
    func testBasicMessageCreation() throws {
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
    }
    
    func testProjectCreation() throws {
        let project = Project(
            name: "Test Project",
            path: "/test/path",
            type: "Swift"
        )
        
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.path, "/test/path")
        XCTAssertEqual(project.type, "Swift")
        XCTAssertEqual(project.id, "/test/path") // id should equal path
    }
    
    func testProjectSessionCreation() throws {
        let session = ProjectSession(
            sessionId: "test-session-123",
            projectName: "Test Project",
            projectPath: "/test/path",
            status: "active",
            startedAt: "2023-01-01T00:00:00Z"
        )
        
        XCTAssertEqual(session.sessionId, "test-session-123")
        XCTAssertEqual(session.projectName, "Test Project")
        XCTAssertEqual(session.projectPath, "/test/path")
        XCTAssertEqual(session.status, "active")
        XCTAssertEqual(session.startedAt, "2023-01-01T00:00:00Z")
    }
    
    func testServerConnectionCreation() throws {
        let connection = ServerConnection(
            name: "Test Server",
            address: "localhost",
            port: 3000,
            authToken: "test-token",
            isSecure: false
        )
        
        XCTAssertEqual(connection.address, "localhost")
        XCTAssertEqual(connection.port, 3000)
        XCTAssertEqual(connection.authToken, "test-token")
        XCTAssertFalse(connection.isSecure)
    }
    
    func testServerConnectionURL() throws {
        let connection = ServerConnection(
            name: "Example Server",
            address: "example.com",
            port: 8080,
            isSecure: false
        )
        
        let url = connection.url
        XCTAssertEqual(url, "http://example.com:8080")
    }
    
    func testServerConnectionSecureURL() throws {
        let connection = ServerConnection(
            name: "Secure Server",
            address: "secure.example.com",
            port: 443,
            isSecure: true
        )
        
        let url = connection.url
        XCTAssertEqual(url, "https://secure.example.com:443")
    }
    
    func testAICLICompanionErrorEnum() throws {
        let networkError = AICLICompanionError.networkError("Test error")
        XCTAssertNotNil(networkError.errorDescription)
        
        let authError = AICLICompanionError.authenticationFailed
        XCTAssertNotNil(authError.errorDescription)
        
        let serverError = AICLICompanionError.serverError("Server error")
        XCTAssertNotNil(serverError.errorDescription)
    }
    
    // MARK: - Performance Tests
    
    func testBasicPerformance() throws {
        measure {
            for _ in 0..<1000 {
                _ = Message(
                    content: "Performance test",
                    sender: .user,
                    type: .text
                )
            }
        }
    }
}
