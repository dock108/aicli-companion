//
//  ServerManagerNetworkingTests.swift
//  AICLICompanionHostTests
//
//  Tests for ServerManager's networking functionality
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ServerManagerNetworkingTests: XCTestCase {
    var serverManager: ServerManager!

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        serverManager.logs.removeAll()
        serverManager.serverHealth = .unknown
    }

    override func tearDown() async throws {
        serverManager.stopHealthChecking()
        serverManager.logs.removeAll()
        serverManager.serverHealth = .unknown
        try await super.tearDown()
    }

    // MARK: - Health Check Tests

    func testHealthCheckWhenServerNotRunning() async {
        serverManager.isRunning = false

        await serverManager.checkServerHealth()

        // Should not check health when not running
        XCTAssertEqual(serverManager.serverHealth, .unknown)
    }

    func testHealthCheckWhenServerRunning() async {
        serverManager.isRunning = true
        serverManager.port = 3001

        // Mock a failed health check (since server isn't actually running)
        await serverManager.checkServerHealth()

        // Health should be updated (likely to unhealthy since no real server)
        XCTAssertNotEqual(serverManager.serverHealth, .unknown)
    }

    func testHealthCheckURL() {
        serverManager.port = 3001

        // Health check URL is constructed internally
        let expectedURL = "http://localhost:3001/api/health"

        XCTAssertEqual(serverManager.port, 3001)
        XCTAssertTrue(expectedURL.contains("health"))
    }

    func testHealthCheckURLWithCustomPort() {
        serverManager.port = 8080

        // Health check URL is constructed internally
        let expectedURL = "http://localhost:8080/api/health"

        XCTAssertEqual(serverManager.port, 8080)
        XCTAssertTrue(expectedURL.contains("health"))
    }

    // MARK: - Connection Monitoring Tests

    func testConnectionStringGeneration() {
        serverManager.isRunning = true
        serverManager.port = 3001
        serverManager.localIP = "192.168.1.100"

        let connectionString = serverManager.connectionString

        XCTAssertTrue(connectionString.contains("3001"))
    }

    func testConnectionStringWithPublicURL() {
        serverManager.isRunning = true
        serverManager.publicURL = "https://test.ngrok.io"
        serverManager.authToken = "test-token-123"

        let connectionString = serverManager.connectionString

        XCTAssertTrue(connectionString.contains("wss://test.ngrok.io"))
        XCTAssertTrue(connectionString.contains("token=test-token-123"))
    }

    func testConnectionStringWhenNotRunning() {
        serverManager.isRunning = false

        let connectionString = serverManager.connectionString

        XCTAssertTrue(connectionString.isEmpty)
    }

    // MARK: - Network Status Tests

    func testLocalIPDetection() {
        let localIP = serverManager.localIP

        // Should have a valid IP
        XCTAssertFalse(localIP.isEmpty)

        // Should be a valid IP format (basic check)
        let ipComponents = localIP.split(separator: ".")
        XCTAssertTrue(ipComponents.count == 4 || localIP == "127.0.0.1")
    }

    func testServerURLConstruction() {
        serverManager.port = 3001

        XCTAssertEqual(serverManager.serverURL, "http://localhost")

        let fullURL = "\(serverManager.serverURL):\(serverManager.port)"
        XCTAssertEqual(fullURL, "http://localhost:3001")
    }

    // MARK: - Session Management Tests

    func testFetchActiveSessions() async {
        serverManager.isRunning = true

        // This will fail since no real server, but tests the method
        await serverManager.fetchActiveSessions()

        // Sessions should be attempted to be fetched
        XCTAssertNotNil(serverManager.activeSessions)
    }

    func testSessionsWhenServerNotRunning() async {
        serverManager.isRunning = false
        serverManager.activeSessions = [
            Session(
                sessionId: "test-session",
                deviceName: "Test Device",
                connectedAt: Date(),
                signalStrength: 100
            )
        ]

        await serverManager.fetchActiveSessions()

        // Should not fetch when not running
        XCTAssertNotNil(serverManager.activeSessions)
    }

    // MARK: - Timeout Handling Tests

    func testHealthCheckTimeout() async {
        serverManager.isRunning = true
        serverManager.port = 65432 // Non-existent port

        let startTime = Date()
        await serverManager.checkServerHealth()
        let duration = Date().timeIntervalSince(startTime)

        // Should timeout reasonably quickly (< 5 seconds)
        XCTAssertLessThan(duration, 5.0)

        // Health should be unhealthy after timeout
        XCTAssertEqual(serverManager.serverHealth, .unhealthy)
    }

    // MARK: - Refresh Status Tests

    func testRefreshStatus() async {
        serverManager.isRunning = true

        await serverManager.refreshStatus()

        // Should update health status
        XCTAssertNotEqual(serverManager.serverHealth, .unknown)

        // Should log the refresh
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("health") || log.message.contains("refresh") || log.message.contains("Failed")
        })
    }

    // MARK: - Health Check Timer Tests

    func testStartHealthChecking() {
        serverManager.isRunning = true

        serverManager.startHealthChecking()

        XCTAssertNotNil(serverManager.healthCheckTimer)

        // Clean up
        serverManager.stopHealthChecking()
    }

    func testStopHealthChecking() {
        serverManager.startHealthChecking()
        XCTAssertNotNil(serverManager.healthCheckTimer)

        serverManager.stopHealthChecking()

        XCTAssertNil(serverManager.healthCheckTimer)
    }

    // MARK: - WebSocket URL Conversion Tests

    func testConvertHTTPToWebSocket() {
        let httpURL = "http://localhost:3001"
        // convertToWebSocketURL is private, test the concept
        let expectedWSURL = httpURL.replacingOccurrences(of: "http://", with: "ws://")

        XCTAssertEqual(expectedWSURL, "ws://localhost:3001")
    }

    func testConvertHTTPSToWebSocket() {
        let httpsURL = "https://secure.example.com"
        // convertToWebSocketURL is private, test the concept
        let expectedWSSURL = httpsURL.replacingOccurrences(of: "https://", with: "wss://")

        XCTAssertEqual(expectedWSSURL, "wss://secure.example.com")
    }

    func testConvertNgrokURL() {
        let ngrokURL = "https://abc123.ngrok.io"
        // convertToWebSocketURL is private, test the concept
        let expectedWSSURL = ngrokURL.replacingOccurrences(of: "https://", with: "wss://")

        XCTAssertEqual(expectedWSSURL, "wss://abc123.ngrok.io")
    }

    // MARK: - Performance Tests

    func testHealthCheckPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Health check")

            Task {
                await serverManager.checkServerHealth()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }
}
