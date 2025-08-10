//
//  ServerManagerTests.swift
//  AICLICompanionHostTests
//
//  Unit tests for ServerManager
//

import XCTest
import Combine
@testable import AICLICompanionHost

@MainActor
final class ServerManagerTests: XCTestCase {
    
    var mockServerManager: MockServerManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockServerManager = MockServerManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        mockServerManager.reset()
        cancellables.removeAll()
        mockServerManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testServerManagerInitialState() throws {
        XCTAssertFalse(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.port, 3001)
        XCTAssertEqual(mockServerManager.localIP, "127.0.0.1")
        XCTAssertNil(mockServerManager.authToken)
        XCTAssertTrue(mockServerManager.activeSessions.isEmpty)
        XCTAssertFalse(mockServerManager.isProcessing)
        XCTAssertEqual(mockServerManager.serverHealth, .unknown)
        XCTAssertTrue(mockServerManager.logs.isEmpty)
        XCTAssertNil(mockServerManager.publicURL)
    }
    
    // MARK: - Server Start Tests
    
    func testStartServerSuccess() async throws {
        // Arrange
        XCTAssertFalse(mockServerManager.isRunning)
        
        // Act
        try await mockServerManager.startServer()
        
        // Assert
        XCTAssertTrue(mockServerManager.startServerCalled)
        XCTAssertEqual(mockServerManager.startServerCallCount, 1)
        XCTAssertTrue(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.serverHealth, .healthy)
        XCTAssertFalse(mockServerManager.isProcessing)
        XCTAssertFalse(mockServerManager.logs.isEmpty)
    }
    
    func testStartServerFailure() async throws {
        // Arrange
        let expectedError = ServerError.processSpawnFailed
        mockServerManager.startServerShouldThrow = expectedError
        
        // Act & Assert
        do {
            try await mockServerManager.startServer()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(mockServerManager.startServerCalled)
            XCTAssertFalse(mockServerManager.isRunning)
        }
    }
    
    func testStartServerMultipleTimes() async throws {
        // First start
        try await mockServerManager.startServer()
        XCTAssertTrue(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.startServerCallCount, 1)
        
        // Second start should not throw but track the call
        try await mockServerManager.startServer()
        XCTAssertTrue(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.startServerCallCount, 2)
    }
    
    // MARK: - Server Stop Tests
    
    func testStopServerSuccess() async throws {
        // Arrange - Start server first
        try await mockServerManager.startServer()
        XCTAssertTrue(mockServerManager.isRunning)
        
        // Act
        await mockServerManager.stopServer()
        
        // Assert
        XCTAssertTrue(mockServerManager.stopServerCalled)
        XCTAssertEqual(mockServerManager.stopServerCallCount, 1)
        XCTAssertFalse(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.serverHealth, .unknown)
        XCTAssertTrue(mockServerManager.activeSessions.isEmpty)
        XCTAssertNil(mockServerManager.publicURL)
        XCTAssertFalse(mockServerManager.isProcessing)
    }
    
    func testStopServerWhenNotRunning() async throws {
        // Arrange
        XCTAssertFalse(mockServerManager.isRunning)
        
        // Act
        await mockServerManager.stopServer()
        
        // Assert
        XCTAssertTrue(mockServerManager.stopServerCalled)
        XCTAssertFalse(mockServerManager.isRunning)
    }
    
    // MARK: - Server Restart Tests
    
    func testRestartServerSuccess() async throws {
        // Arrange - Start server first
        try await mockServerManager.startServer()
        let initialStartCount = mockServerManager.startServerCallCount
        
        // Act
        try await mockServerManager.restartServerWithCurrentConfig()
        
        // Assert
        XCTAssertTrue(mockServerManager.restartServerCalled)
        XCTAssertEqual(mockServerManager.restartServerCallCount, 1)
        XCTAssertTrue(mockServerManager.stopServerCalled)
        XCTAssertEqual(mockServerManager.startServerCallCount, initialStartCount + 1)
        XCTAssertTrue(mockServerManager.isRunning)
    }
    
    func testRestartServerFailure() async throws {
        // Arrange
        try await mockServerManager.startServer()
        mockServerManager.restartServerShouldThrow = ServerError.processSpawnFailed
        
        // Act & Assert
        do {
            try await mockServerManager.restartServerWithCurrentConfig()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(mockServerManager.restartServerCalled)
        }
    }
    
    // MARK: - Auth Token Tests
    
    func testGenerateAuthToken() throws {
        // Arrange
        XCTAssertNil(mockServerManager.authToken)
        
        // Act
        mockServerManager.generateAuthToken()
        
        // Assert
        XCTAssertTrue(mockServerManager.generateAuthTokenCalled)
        XCTAssertEqual(mockServerManager.generateAuthTokenCallCount, 1)
        XCTAssertNotNil(mockServerManager.authToken)
        
        // Verify token format (UUID without dashes, lowercase)
        let token = mockServerManager.authToken!
        XCTAssertFalse(token.contains("-"))
        XCTAssertEqual(token, token.lowercased())
        XCTAssertEqual(token.count, 32) // UUID without dashes is 32 characters
    }
    
    func testGenerateAuthTokenMultipleTimes() throws {
        // Generate first token
        mockServerManager.generateAuthToken()
        let firstToken = mockServerManager.authToken
        
        // Generate second token
        mockServerManager.generateAuthToken()
        let secondToken = mockServerManager.authToken
        
        // Tokens should be different
        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertEqual(mockServerManager.generateAuthTokenCallCount, 2)
    }
    
    // MARK: - Connection String Tests
    
    func testConnectionStringWhenNotRunning() throws {
        XCTAssertFalse(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.connectionString, "")
    }
    
    func testConnectionStringLocalWithoutAuth() async throws {
        // Start server without auth token
        try await mockServerManager.startServer()
        
        let connectionString = mockServerManager.connectionString
        XCTAssertEqual(connectionString, "ws://127.0.0.1:3001/ws")
    }
    
    func testConnectionStringLocalWithAuth() async throws {
        // Generate auth token and start server
        mockServerManager.generateAuthToken()
        let token = mockServerManager.authToken!
        try await mockServerManager.startServer()
        
        let connectionString = mockServerManager.connectionString
        XCTAssertEqual(connectionString, "ws://127.0.0.1:3001/ws?token=\(token)")
    }
    
    func testConnectionStringWithPublicURL() async throws {
        // Start server with public URL
        try await mockServerManager.startServer()
        mockServerManager.publicURL = "https://example.ngrok.io"
        
        let connectionString = mockServerManager.connectionString
        XCTAssertEqual(connectionString, "wss://example.ngrok.io/ws")
    }
    
    func testConnectionStringWithPublicURLAndAuth() async throws {
        // Generate auth token and start server with public URL
        mockServerManager.generateAuthToken()
        let token = mockServerManager.authToken!
        try await mockServerManager.startServer()
        mockServerManager.publicURL = "https://example.ngrok.io"
        
        let connectionString = mockServerManager.connectionString
        XCTAssertEqual(connectionString, "wss://example.ngrok.io/ws?token=\(token)")
    }
    
    // MARK: - Server Status Tests
    
    func testRefreshStatus() async throws {
        // Start server first
        try await mockServerManager.startServer()
        
        // Clear tracking
        mockServerManager.refreshStatusCalled = false
        
        // Act
        await mockServerManager.refreshStatus()
        
        // Assert
        XCTAssertTrue(mockServerManager.refreshStatusCalled)
        XCTAssertEqual(mockServerManager.refreshStatusCallCount, 1)
        XCTAssertFalse(mockServerManager.isProcessing)
        XCTAssertEqual(mockServerManager.serverHealth, .healthy)
        XCTAssertEqual(mockServerManager.activeSessions.count, 2) // Mock returns 2 sessions
    }
    
    func testRefreshStatusWhenNotRunning() async throws {
        // Act
        await mockServerManager.refreshStatus()
        
        // Assert
        XCTAssertTrue(mockServerManager.refreshStatusCalled)
        XCTAssertFalse(mockServerManager.isProcessing)
        // Health should remain unknown when not running
        XCTAssertEqual(mockServerManager.serverHealth, .unknown)
    }
    
    // MARK: - Server PID Tests
    
    func testServerPIDWhenRunning() async throws {
        try await mockServerManager.startServer()
        XCTAssertNotNil(mockServerManager.serverPID)
        XCTAssertEqual(mockServerManager.serverPID, 12345)
    }
    
    func testServerPIDWhenNotRunning() throws {
        XCTAssertNil(mockServerManager.serverPID)
    }
    
    // MARK: - Logging Tests
    
    func testAddLogEntry() throws {
        // Act
        mockServerManager.addLog(.info, "Test log message")
        
        // Assert
        XCTAssertEqual(mockServerManager.logs.count, 1)
        let log = mockServerManager.logs.first!
        XCTAssertEqual(log.level, .info)
        XCTAssertEqual(log.message, "Test log message")
    }
    
    func testAddMultipleLogEntries() throws {
        // Add various log levels
        mockServerManager.addLog(.debug, "Debug message")
        mockServerManager.addLog(.info, "Info message")
        mockServerManager.addLog(.warning, "Warning message")
        mockServerManager.addLog(.error, "Error message")
        
        // Assert
        XCTAssertEqual(mockServerManager.logs.count, 4)
        XCTAssertEqual(mockServerManager.logs[0].level, .debug)
        XCTAssertEqual(mockServerManager.logs[1].level, .info)
        XCTAssertEqual(mockServerManager.logs[2].level, .warning)
        XCTAssertEqual(mockServerManager.logs[3].level, .error)
    }
    
    // MARK: - Published Properties Tests
    
    func testPublishedPropertiesUpdates() async throws {
        let expectation = XCTestExpectation(description: "isRunning should publish changes")
        var receivedValues: [Bool] = []
        
        mockServerManager.$isRunning
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Start server to trigger isRunning change
        try await mockServerManager.startServer()
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedValues.first, false) // Initial value
        XCTAssertEqual(receivedValues.last, true)   // After start
    }
    
    // MARK: - Server URL Tests
    
    func testServerFullURLLocal() throws {
        mockServerManager.localIP = "192.168.1.100"
        mockServerManager.port = 3001
        
        XCTAssertEqual(mockServerManager.serverFullURL, "http://192.168.1.100:3001")
    }
    
    func testServerFullURLWithPublicURL() throws {
        mockServerManager.publicURL = "https://example.ngrok.io"
        
        XCTAssertEqual(mockServerManager.serverFullURL, "https://example.ngrok.io")
    }
    
    // MARK: - Reset Tests
    
    func testResetClearsAllState() async throws {
        // Setup complex state
        mockServerManager.generateAuthToken()
        try await mockServerManager.startServer()
        mockServerManager.publicURL = "https://test.com"
        await mockServerManager.refreshStatus()
        
        // Act
        mockServerManager.reset()
        
        // Assert everything is reset
        XCTAssertFalse(mockServerManager.isRunning)
        XCTAssertEqual(mockServerManager.port, 3001)
        XCTAssertEqual(mockServerManager.localIP, "127.0.0.1")
        XCTAssertNil(mockServerManager.authToken)
        XCTAssertTrue(mockServerManager.activeSessions.isEmpty)
        XCTAssertFalse(mockServerManager.isProcessing)
        XCTAssertEqual(mockServerManager.serverHealth, .unknown)
        XCTAssertTrue(mockServerManager.logs.isEmpty)
        XCTAssertNil(mockServerManager.publicURL)
        
        // Assert tracking is reset
        XCTAssertFalse(mockServerManager.startServerCalled)
        XCTAssertEqual(mockServerManager.startServerCallCount, 0)
        XCTAssertFalse(mockServerManager.stopServerCalled)
        XCTAssertEqual(mockServerManager.stopServerCallCount, 0)
        XCTAssertFalse(mockServerManager.restartServerCalled)
        XCTAssertEqual(mockServerManager.restartServerCallCount, 0)
        XCTAssertFalse(mockServerManager.generateAuthTokenCalled)
        XCTAssertEqual(mockServerManager.generateAuthTokenCallCount, 0)
        XCTAssertFalse(mockServerManager.refreshStatusCalled)
        XCTAssertEqual(mockServerManager.refreshStatusCallCount, 0)
    }
}