//
//  ServerManagerProductionTests.swift
//  AICLICompanionHostTests
//
//  Tests for the actual ServerManager implementation
//

import XCTest
import Combine
@testable import AICLICompanionHost

@MainActor
final class ServerManagerProductionTests: XCTestCase {

    var serverManager: ServerManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        cancellables = Set<AnyCancellable>()

        // Reset state
        serverManager.isRunning = false
        serverManager.serverProcess = nil
        serverManager.publicURL = nil
        serverManager.authToken = nil
        serverManager.logs.removeAll()
        serverManager.activeSessions.removeAll()
    }

    override func tearDown() async throws {
        // Stop server if running
        if serverManager.isRunning {
            await serverManager.stopServer()
        }

        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - Connection String Tests

    func testConnectionStringWhenNotRunning() {
        serverManager.isRunning = false
        XCTAssertEqual(serverManager.connectionString, "")
    }

    func testConnectionStringLocalWithoutAuth() {
        serverManager.isRunning = true
        serverManager.localIP = "192.168.1.100"
        serverManager.port = 3001
        serverManager.authToken = nil

        let expected = "ws://192.168.1.100:3001/ws"
        XCTAssertEqual(serverManager.connectionString, expected)
    }

    func testConnectionStringLocalWithAuth() {
        // First ensure auth is enabled
        SettingsManager.shared.requireAuthentication = true

        serverManager.isRunning = true
        serverManager.localIP = "192.168.1.100"
        serverManager.port = 3001
        serverManager.authToken = "test-token-123"

        let expected = "ws://192.168.1.100:3001/ws?token=test-token-123"
        XCTAssertEqual(serverManager.connectionString, expected)

        // Clean up
        SettingsManager.shared.requireAuthentication = false
    }

    func testConnectionStringWithPublicHTTPSURL() {
        serverManager.isRunning = true
        serverManager.publicURL = "https://example.ngrok.io"
        serverManager.authToken = nil

        let expected = "wss://example.ngrok.io/ws"
        XCTAssertEqual(serverManager.connectionString, expected)
    }

    func testConnectionStringWithPublicHTTPURL() {
        serverManager.isRunning = true
        serverManager.publicURL = "http://example.ngrok.io"
        serverManager.authToken = nil

        let expected = "ws://example.ngrok.io/ws"
        XCTAssertEqual(serverManager.connectionString, expected)
    }

    func testConnectionStringWithPublicURLAndAuth() {
        SettingsManager.shared.requireAuthentication = true

        serverManager.isRunning = true
        serverManager.publicURL = "https://example.ngrok.io"
        serverManager.authToken = "abc123"

        let expected = "wss://example.ngrok.io/ws?token=abc123"
        XCTAssertEqual(serverManager.connectionString, expected)

        SettingsManager.shared.requireAuthentication = false
    }

    // MARK: - Server Full URL Tests

    func testServerFullURLWithPublicURL() {
        serverManager.publicURL = "https://example.ngrok.io"
        XCTAssertEqual(serverManager.serverFullURL, "https://example.ngrok.io")
    }

    func testServerFullURLWithoutPublicURL() {
        serverManager.publicURL = nil
        serverManager.localIP = "192.168.1.50"
        serverManager.port = 8080

        XCTAssertEqual(serverManager.serverFullURL, "http://192.168.1.50:8080")
    }

    // MARK: - Server PID Tests

    func testServerPIDWhenNoProcess() {
        serverManager.serverProcess = nil
        XCTAssertNil(serverManager.serverPID)
    }

    func testServerPIDWithMockProcess() {
        let mockProcess = MockProcess()
        serverManager.serverProcess = mockProcess

        XCTAssertEqual(serverManager.serverPID, 12345) // MockProcess default PID
    }

    // MARK: - Log Management Tests

    func testAddLogEntry() {
        let initialCount = serverManager.logs.count

        serverManager.addLog(.info, "Test log message")

        XCTAssertEqual(serverManager.logs.count, initialCount + 1)

        let lastLog = serverManager.logs.last
        XCTAssertNotNil(lastLog)
        XCTAssertEqual(lastLog?.level, .info)
        XCTAssertEqual(lastLog?.message, "Test log message")
    }

    func testAddMultipleLogEntries() {
        serverManager.logs.removeAll()

        serverManager.addLog(.debug, "Debug message")
        serverManager.addLog(.info, "Info message")
        serverManager.addLog(.warning, "Warning message")
        serverManager.addLog(.error, "Error message")

        XCTAssertEqual(serverManager.logs.count, 4)
        XCTAssertEqual(serverManager.logs[0].level, .debug)
        XCTAssertEqual(serverManager.logs[1].level, .info)
        XCTAssertEqual(serverManager.logs[2].level, .warning)
        XCTAssertEqual(serverManager.logs[3].level, .error)
    }

    func testClearLogs() {
        // Add some logs
        serverManager.addLog(.info, "Test 1")
        serverManager.addLog(.info, "Test 2")
        XCTAssertGreaterThan(serverManager.logs.count, 0)

        // Clear logs
        serverManager.logs.removeAll()

        XCTAssertEqual(serverManager.logs.count, 0)
    }

    // MARK: - Auth Token Tests

    func testGenerateAuthToken() {
        serverManager.authToken = nil
        serverManager.generateAuthToken()

        let token1 = serverManager.authToken
        XCTAssertNotNil(token1)
        XCTAssertFalse(token1?.isEmpty ?? true)
        XCTAssertEqual(token1?.count, 32) // UUID without hyphens

        // Generate another token - should be different
        serverManager.generateAuthToken()
        let token2 = serverManager.authToken
        XCTAssertNotEqual(token1, token2)
    }

    // MARK: - Published Properties Tests

    func testPublishedPropertiesUpdate() {
        let expectation = XCTestExpectation(description: "Properties updated")
        var receivedValues: [Bool] = []

        serverManager.$isRunning
            .dropFirst() // Skip initial value
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Trigger updates
        serverManager.isRunning = true
        serverManager.isRunning = false

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedValues, [true, false])
    }

    func testHealthStatusUpdates() {
        let expectation = XCTestExpectation(description: "Health status updated")
        var receivedHealth: [ServerHealth] = []

        serverManager.$serverHealth
            .dropFirst()
            .sink { health in
                receivedHealth.append(health)
                if receivedHealth.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.serverHealth = .healthy
        serverManager.serverHealth = .unhealthy
        serverManager.serverHealth = .unknown

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedHealth, [.healthy, .unhealthy, .unknown])
    }

    // MARK: - WebSocket URL Conversion Tests

    func testWebSocketURLConversionHTTPS() {
        serverManager.isRunning = true
        serverManager.publicURL = "https://test.example.com"

        let connectionString = serverManager.connectionString
        XCTAssertTrue(connectionString.hasPrefix("wss://"))
        XCTAssertTrue(connectionString.contains("/ws"))
    }

    func testWebSocketURLConversionHTTP() {
        serverManager.isRunning = true
        serverManager.publicURL = "http://test.example.com"

        let connectionString = serverManager.connectionString
        XCTAssertTrue(connectionString.hasPrefix("ws://"))
        XCTAssertTrue(connectionString.contains("/ws"))
    }

    func testWebSocketURLWithExistingPath() {
        serverManager.isRunning = true
        serverManager.publicURL = "https://test.example.com/ws"

        let connectionString = serverManager.connectionString
        // Should not add /ws again
        XCTAssertEqual(connectionString.components(separatedBy: "/ws").count - 1, 1)
    }

    // MARK: - Session Management Tests

    func testAddSession() {
        serverManager.activeSessions.removeAll()

        let session = Session(
            sessionId: "test-123",
            deviceName: "Test Device",
            connectedAt: Date(),
            signalStrength: 0.8
        )

        serverManager.activeSessions.append(session)

        XCTAssertEqual(serverManager.activeSessions.count, 1)
        XCTAssertEqual(serverManager.activeSessions.first?.sessionId, "test-123")
    }

    func testRemoveSession() {
        let session1 = Session(sessionId: "1", deviceName: "Device 1", connectedAt: Date(), signalStrength: 0.5)
        let session2 = Session(sessionId: "2", deviceName: "Device 2", connectedAt: Date(), signalStrength: 0.8)

        serverManager.activeSessions = [session1, session2]
        XCTAssertEqual(serverManager.activeSessions.count, 2)

        serverManager.activeSessions.removeAll { $0.sessionId == "1" }

        XCTAssertEqual(serverManager.activeSessions.count, 1)
        XCTAssertEqual(serverManager.activeSessions.first?.sessionId, "2")
    }
}
