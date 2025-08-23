import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class ServerModelsTests: XCTestCase {
    
    // MARK: - ConnectionStatus Tests
    
    func testConnectionStatusCases() {
        let disconnected = ConnectionStatus.disconnected
        let connecting = ConnectionStatus.connecting
        let connected = ConnectionStatus.connected
        let reconnecting = ConnectionStatus.reconnecting
        let authenticating = ConnectionStatus.authenticating
        let unauthorized = ConnectionStatus.unauthorized
        let error = ConnectionStatus.error("Test error")
        
        XCTAssertFalse(disconnected.isConnected)
        XCTAssertFalse(connecting.isConnected)
        XCTAssertTrue(connected.isConnected)
        XCTAssertFalse(reconnecting.isConnected)
        XCTAssertFalse(authenticating.isConnected)
        XCTAssertFalse(unauthorized.isConnected)
        XCTAssertFalse(error.isConnected)
    }
    
    func testConnectionStatusEquality() {
        XCTAssertEqual(ConnectionStatus.disconnected, ConnectionStatus.disconnected)
        XCTAssertEqual(ConnectionStatus.connected, ConnectionStatus.connected)
        XCTAssertEqual(ConnectionStatus.error("test"), ConnectionStatus.error("test"))
        XCTAssertNotEqual(ConnectionStatus.error("test1"), ConnectionStatus.error("test2"))
        XCTAssertNotEqual(ConnectionStatus.connected, ConnectionStatus.disconnected)
    }
    
    // MARK: - ServerConnection Tests
    
    func testServerConnectionInitialization() {
        let connection = ServerConnection(
            name: "Test Server",
            address: "192.168.1.100",
            port: 3000,
            authToken: "test-token",
            isSecure: true,
            lastConnected: Date(),
            isDefault: true
        )
        
        XCTAssertEqual(connection.name, "Test Server")
        XCTAssertEqual(connection.address, "192.168.1.100")
        XCTAssertEqual(connection.port, 3000)
        XCTAssertEqual(connection.authToken, "test-token")
        XCTAssertTrue(connection.isSecure)
        XCTAssertNotNil(connection.lastConnected)
        XCTAssertTrue(connection.isDefault)
    }
    
    func testServerConnectionDefaults() {
        let connection = ServerConnection(
            name: "Basic Server",
            address: "localhost",
            port: 8080
        )
        
        XCTAssertNotNil(connection.id)
        XCTAssertNil(connection.authToken)
        XCTAssertFalse(connection.isSecure)
        XCTAssertNil(connection.lastConnected)
        XCTAssertFalse(connection.isDefault)
    }
    
    func testServerConnectionURLs() {
        let httpConnection = ServerConnection(
            name: "HTTP Server",
            address: "example.com",
            port: 8080,
            isSecure: false
        )
        
        XCTAssertEqual(httpConnection.url, "http://example.com:8080")
        XCTAssertEqual(httpConnection.wsUrl, "ws://example.com:8080/ws")
        
        let httpsConnection = ServerConnection(
            name: "HTTPS Server",
            address: "secure.example.com",
            port: 443,
            isSecure: true
        )
        
        XCTAssertEqual(httpsConnection.url, "https://secure.example.com:443")
        XCTAssertEqual(httpsConnection.wsUrl, "wss://secure.example.com:443/ws")
    }
    
    func testServerConnectionDisplayName() {
        let namedConnection = ServerConnection(
            name: "My Server",
            address: "localhost",
            port: 3000
        )
        XCTAssertEqual(namedConnection.displayName, "My Server")
        
        let unnamedConnection = ServerConnection(
            name: "",
            address: "192.168.1.1",
            port: 8080
        )
        XCTAssertEqual(unnamedConnection.displayName, "192.168.1.1:8080")
    }
    
    func testServerConnectionCodable() throws {
        let original = ServerConnection(
            name: "Codable Test",
            address: "test.server.com",
            port: 9000,
            authToken: "secret-token",
            isSecure: true,
            lastConnected: Date(),
            isDefault: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ServerConnection.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.address, original.address)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.authToken, original.authToken)
        XCTAssertEqual(decoded.isSecure, original.isSecure)
        XCTAssertEqual(decoded.isDefault, original.isDefault)
    }
    
    // MARK: - DiscoveredServer Tests
    
    func testDiscoveredServerInitialization() {
        let lastSeen = Date()
        let server = DiscoveredServer(
            name: "Found Server",
            address: "10.0.0.1",
            port: 3000,
            isSecure: false,
            lastSeen: lastSeen
        )
        
        XCTAssertEqual(server.name, "Found Server")
        XCTAssertEqual(server.address, "10.0.0.1")
        XCTAssertEqual(server.port, 3000)
        XCTAssertFalse(server.isSecure)
        XCTAssertEqual(server.lastSeen, lastSeen)
        XCTAssertEqual(server.url, "http://10.0.0.1:3000")
    }
    
    func testDiscoveredServerSecureURL() {
        let server = DiscoveredServer(
            name: "Secure Server",
            address: "secure.local",
            port: 443,
            isSecure: true,
            lastSeen: Date()
        )
        
        XCTAssertEqual(server.url, "https://secure.local:443")
    }
    
    // MARK: - AICLIResponse Tests
    
    func testAICLIResponseSuccessfulInit() {
        let response = AICLIResponse(
            success: true,
            content: "Response content",
            sessionId: "session-123",
            claudeSessionId: "claude-456",
            duration: 2.5,
            result: "Success"
        )
        
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.content, "Response content")
        XCTAssertNil(response.error)
        XCTAssertEqual(response.sessionId, "session-123")
        XCTAssertEqual(response.claudeSessionId, "claude-456")
        XCTAssertEqual(response.duration, 2.5)
        XCTAssertEqual(response.result, "Success")
    }
    
    func testAICLIResponseErrorInit() {
        let response = AICLIResponse(
            success: false,
            error: "Something went wrong"
        )
        
        XCTAssertFalse(response.success)
        XCTAssertNil(response.content)
        XCTAssertEqual(response.error, "Something went wrong")
    }
    
    func testAICLIResponseWithUsage() {
        let usage = Usage(
            inputTokens: 100,
            outputTokens: 200,
            cacheCreationInputTokens: 50,
            cacheReadInputTokens: 25
        )
        
        let response = AICLIResponse(
            success: true,
            content: "Test",
            usage: usage
        )
        
        XCTAssertNotNil(response.usage)
        XCTAssertEqual(response.usage?.inputTokens, 100)
        XCTAssertEqual(response.usage?.outputTokens, 200)
        XCTAssertEqual(response.usage?.cacheCreationInputTokens, 50)
        XCTAssertEqual(response.usage?.cacheReadInputTokens, 25)
    }
    
    func testAICLIResponseCodable() throws {
        let usage = Usage(inputTokens: 150, outputTokens: 300)
        let original = AICLIResponse(
            success: true,
            content: "Codable test",
            sessionId: "test-session",
            usage: usage,
            duration: 1.5
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AICLIResponse.self, from: data)
        
        XCTAssertEqual(decoded.success, original.success)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.sessionId, original.sessionId)
        XCTAssertEqual(decoded.usage?.inputTokens, original.usage?.inputTokens)
        XCTAssertEqual(decoded.duration, original.duration)
    }
    
    // MARK: - Usage Tests
    
    func testUsageInitialization() {
        let usage = Usage(
            inputTokens: 500,
            outputTokens: 1000,
            cacheCreationInputTokens: 100,
            cacheReadInputTokens: 50
        )
        
        XCTAssertEqual(usage.inputTokens, 500)
        XCTAssertEqual(usage.outputTokens, 1000)
        XCTAssertEqual(usage.cacheCreationInputTokens, 100)
        XCTAssertEqual(usage.cacheReadInputTokens, 50)
    }
    
    func testUsagePartialInit() {
        let usage = Usage(inputTokens: 100)
        
        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertNil(usage.outputTokens)
        XCTAssertNil(usage.cacheCreationInputTokens)
        XCTAssertNil(usage.cacheReadInputTokens)
    }
    
    // MARK: - Deliverable Tests
    
    func testDeliverableInitialization() {
        let deliverable = Deliverable(
            artifact: "file.txt",
            content: "File content here"
        )
        
        XCTAssertEqual(deliverable.artifact, "file.txt")
        XCTAssertEqual(deliverable.content, "File content here")
    }
    
    func testDeliverableCodable() throws {
        let original = Deliverable(
            artifact: "test.md",
            content: "# Test Content"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Deliverable.self, from: data)
        
        XCTAssertEqual(decoded.artifact, original.artifact)
        XCTAssertEqual(decoded.content, original.content)
    }
    
    // MARK: - AICLICompanionError Tests
    
    func testErrorDescriptions() {
        XCTAssertEqual(
            AICLICompanionError.networkError("Connection failed").errorDescription,
            "Network error: Connection failed"
        )
        
        XCTAssertEqual(
            AICLICompanionError.authenticationFailed.errorDescription,
            "Authentication failed"
        )
        
        XCTAssertEqual(
            AICLICompanionError.serverError("Internal error").errorDescription,
            "Server error: Internal error"
        )
        
        XCTAssertEqual(
            AICLICompanionError.invalidResponse.errorDescription,
            "Invalid response from server"
        )
        
        XCTAssertEqual(
            AICLICompanionError.connectionTimeout.errorDescription,
            "Connection timeout"
        )
        
        XCTAssertEqual(
            AICLICompanionError.websocketError("Socket closed").errorDescription,
            "WebSocket error: Socket closed"
        )
        
        XCTAssertEqual(
            AICLICompanionError.invalidURL.errorDescription,
            "Invalid URL"
        )
        
        XCTAssertEqual(
            AICLICompanionError.noProjectSelected.errorDescription,
            "No project selected"
        )
        
        XCTAssertEqual(
            AICLICompanionError.fileNotFound("/path/to/file").errorDescription,
            "File not found: /path/to/file"
        )
        
        XCTAssertEqual(
            AICLICompanionError.permissionDenied.errorDescription,
            "Permission denied"
        )
        
        XCTAssertEqual(
            AICLICompanionError.invalidInput("Bad format").errorDescription,
            "Invalid input: Bad format"
        )
        
        XCTAssertEqual(
            AICLICompanionError.sessionExpired.errorDescription,
            "Session expired"
        )
        
        XCTAssertEqual(
            AICLICompanionError.rateLimited.errorDescription,
            "Rate limited"
        )
        
        XCTAssertEqual(
            AICLICompanionError.serverUnavailable.errorDescription,
            "Server unavailable"
        )
        
        XCTAssertEqual(
            AICLICompanionError.notFound("Resource").errorDescription,
            "Not found: Resource"
        )
        
        XCTAssertEqual(
            AICLICompanionError.alreadyExists("Item").errorDescription,
            "Already exists: Item"
        )
        
        XCTAssertEqual(
            AICLICompanionError.unknown("Mystery").errorDescription,
            "Unknown error: Mystery"
        )
    }
    
    func testErrorEquality() {
        XCTAssertEqual(
            AICLICompanionError.networkError("test"),
            AICLICompanionError.networkError("test")
        )
        
        XCTAssertNotEqual(
            AICLICompanionError.networkError("test1"),
            AICLICompanionError.networkError("test2")
        )
        
        XCTAssertEqual(
            AICLICompanionError.authenticationFailed,
            AICLICompanionError.authenticationFailed
        )
        
        XCTAssertNotEqual(
            AICLICompanionError.authenticationFailed,
            AICLICompanionError.permissionDenied
        )
        
        XCTAssertEqual(
            AICLICompanionError.fileNotFound("/path"),
            AICLICompanionError.fileNotFound("/path")
        )
        
        XCTAssertNotEqual(
            AICLICompanionError.fileNotFound("/path1"),
            AICLICompanionError.fileNotFound("/path2")
        )
    }
    
    func testErrorAllCases() {
        // Test that all error cases are properly handled
        let errors: [AICLICompanionError] = [
            .networkError("test"),
            .authenticationFailed,
            .serverError("test"),
            .invalidResponse,
            .connectionTimeout,
            .websocketError("test"),
            .invalidURL,
            .noProjectSelected,
            .fileNotFound("test"),
            .permissionDenied,
            .invalidInput("test"),
            .sessionExpired,
            .rateLimited,
            .serverUnavailable,
            .notFound("test"),
            .alreadyExists("test"),
            .unknown("test")
        ]
        
        // Verify each error has a description
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
        
        // Verify equality implementation covers all cases
        for error in errors {
            XCTAssertEqual(error, error)
        }
    }
}