import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class MinimalTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - Smoke Tests
    
    func testBasicAssertions() throws {
        XCTAssertTrue(true)
        XCTAssertFalse(false)
        XCTAssertEqual(1 + 1, 2)
        XCTAssertNotNil("test")
    }
    
    func testMessageCreation() throws {
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
        XCTAssertEqual(project.id, "/test/path")
    }
    
    func testServerConnectionURL() throws {
        let connection = ServerConnection(
            name: "Test Server",
            address: "localhost",
            port: 3000,
            isSecure: false
        )
        
        XCTAssertEqual(connection.url, "http://localhost:3000")
        XCTAssertEqual(connection.wsUrl, "ws://localhost:3000/ws")
    }
    
    func testErrorTypes() throws {
        let networkError = AICLICompanionError.networkError("Test")
        let authError = AICLICompanionError.authenticationFailed
        let serverError = AICLICompanionError.serverError("Error")
        
        XCTAssertNotNil(networkError)
        XCTAssertNotNil(authError)
        XCTAssertNotNil(serverError)
    }
}