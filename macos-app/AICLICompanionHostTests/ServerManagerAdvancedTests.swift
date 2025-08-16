//
//  ServerManagerAdvancedTests.swift
//  AICLICompanionHostTests
//
//  Advanced tests for ServerManager to improve coverage
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ServerManagerAdvancedTests: XCTestCase {

    var serverManager: ServerManager!
    var settingsManager: SettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        settingsManager = SettingsManager.shared

        // Reset state
        if serverManager.isRunning {
            await serverManager.stopServer()
        }
        serverManager.logs.removeAll()
        serverManager.activeSessions.removeAll()
    }

    override func tearDown() async throws {
        if serverManager.isRunning {
            await serverManager.stopServer()
        }
        try await super.tearDown()
    }

    // MARK: - Error Handling Tests

    func testStartServerWithInvalidPort() async {
        settingsManager.serverPort = -1

        do {
            try await serverManager.startServer()
            XCTFail("Should have thrown error for invalid port")
        } catch {
            XCTAssertTrue(error is ServerError)
        }
    }

    func testStartServerAlreadyRunning() async {
        // Start server first
        settingsManager.serverPort = 3002
        try? await serverManager.startServer()

        // Try to start again
        do {
            try await serverManager.startServer()
            XCTFail("Should have thrown error when already running")
        } catch {
            XCTAssertTrue(error is ServerError)
        }
    }

    func testStopServerNotRunning() async {
        // Ensure server is not running
        XCTAssertFalse(serverManager.isRunning)

        // Should not throw error when stopping non-running server
        await serverManager.stopServer()
        XCTAssertFalse(serverManager.isRunning)
    }

    // MARK: - Health Check Tests

    func testHealthCheckWithServerStopped() {
        let health = serverManager.serverHealth
        // When stopped, health should be unknown or unhealthy
        XCTAssertTrue(health == .unknown || health == .unhealthy)
    }

    func testUpdateServerHealth() {
        serverManager.serverHealth = .healthy
        XCTAssertEqual(serverManager.serverHealth, .healthy)

        serverManager.serverHealth = .unhealthy
        XCTAssertEqual(serverManager.serverHealth, .unhealthy)

        serverManager.serverHealth = .unknown
        XCTAssertEqual(serverManager.serverHealth, .unknown)
    }

    // MARK: - Session Management Tests

    func testAddSession() {
        let session = Session(
            sessionId: "test-session",
            deviceName: "Test Device",
            connectedAt: Date(),
            signalStrength: 100
        )

        serverManager.activeSessions.append(session)

        XCTAssertEqual(serverManager.activeSessions.count, 1)
        XCTAssertEqual(serverManager.activeSessions.first?.sessionId, "test-session")
    }

    func testRemoveSession() {
        let session1 = Session(
            sessionId: "test-session-1",
            deviceName: "Test Device 1",
            connectedAt: Date(),
            signalStrength: 100
        )

        let session2 = Session(
            sessionId: "test-session-2",
            deviceName: "Test Device 2",
            connectedAt: Date(),
            signalStrength: 90
        )

        serverManager.activeSessions = [session1, session2]
        XCTAssertEqual(serverManager.activeSessions.count, 2)

        // Remove first session
        serverManager.activeSessions.removeAll { $0.sessionId == "test-session-1" }

        XCTAssertEqual(serverManager.activeSessions.count, 1)
        XCTAssertEqual(serverManager.activeSessions.first?.sessionId, "test-session-2")
    }

    func testClearAllSessions() {
        let sessions = [
            Session(sessionId: "1", deviceName: "Device 1", connectedAt: Date(), signalStrength: 100),
            Session(sessionId: "2", deviceName: "Device 2", connectedAt: Date(), signalStrength: 90),
            Session(sessionId: "3", deviceName: "Device 3", connectedAt: Date(), signalStrength: 80)
        ]

        serverManager.activeSessions = sessions
        XCTAssertEqual(serverManager.activeSessions.count, 3)

        serverManager.activeSessions.removeAll()
        XCTAssertEqual(serverManager.activeSessions.count, 0)
    }

    // MARK: - Logging Edge Cases

    func testAddLogWithVeryLongMessage() {
        let longMessage = String(repeating: "A", count: 10000)
        serverManager.addLog(.info, longMessage)

        XCTAssertEqual(serverManager.logs.count, 1)
        XCTAssertEqual(serverManager.logs.first?.message, longMessage)
    }

    func testAddLogWithEmptyMessage() {
        serverManager.addLog(.info, "")

        XCTAssertEqual(serverManager.logs.count, 1)
        XCTAssertEqual(serverManager.logs.first?.message, "")
    }

    func testAddLogWithSpecialCharacters() {
        let specialMessage = "Special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?"
        serverManager.addLog(.warning, specialMessage)

        XCTAssertEqual(serverManager.logs.count, 1)
        XCTAssertEqual(serverManager.logs.first?.message, specialMessage)
    }

    func testAddLogWithUnicodeCharacters() {
        let unicodeMessage = "Unicode: 🚀 💻 🔥 中文 日本語"
        serverManager.addLog(.error, unicodeMessage)

        XCTAssertEqual(serverManager.logs.count, 1)
        XCTAssertEqual(serverManager.logs.first?.message, unicodeMessage)
    }

    func testLogRotationAtExactLimit() {
        let maxEntries = 5
        settingsManager.maxLogEntries = maxEntries

        // Add exactly max entries
        for i in 1...maxEntries {
            serverManager.addLog(.info, "Log \(i)")
        }

        XCTAssertEqual(serverManager.logs.count, maxEntries)

        // Add one more - should trigger rotation
        serverManager.addLog(.info, "Log \(maxEntries + 1)")

        XCTAssertEqual(serverManager.logs.count, maxEntries)
        XCTAssertEqual(serverManager.logs.last?.message, "Log \(maxEntries + 1)")
        XCTAssertEqual(serverManager.logs.first?.message, "Log 2") // First log should be removed
    }

    func testClearLogsAndAddAfter() {
        // Add some logs
        for i in 1...3 {
            serverManager.addLog(.info, "Log \(i)")
        }

        XCTAssertEqual(serverManager.logs.count, 3)

        // Clear logs (this adds a "Logs cleared" message)
        serverManager.clearLogs()
        XCTAssertEqual(serverManager.logs.count, 1)
        XCTAssertEqual(serverManager.logs.first?.message, "Logs cleared")

        // Add more logs
        serverManager.addLog(.info, "New log")
        XCTAssertEqual(serverManager.logs.count, 2)
    }

    // MARK: - Log Filtering Tests

    func testGetFilteredLogsByLevel() {
        serverManager.addLog(.debug, "Debug message")
        serverManager.addLog(.info, "Info message")
        serverManager.addLog(.warning, "Warning message")
        serverManager.addLog(.error, "Error message")

        let debugLogs = serverManager.getFilteredLogs(level: .debug)
        XCTAssertEqual(debugLogs.count, 1)
        XCTAssertEqual(debugLogs.first?.level, .debug)

        let errorLogs = serverManager.getFilteredLogs(level: .error)
        XCTAssertEqual(errorLogs.count, 1)
        XCTAssertEqual(errorLogs.first?.level, .error)
    }

    func testGetFilteredLogsBySearchText() {
        serverManager.addLog(.info, "Server started successfully")
        serverManager.addLog(.info, "Client connected")
        serverManager.addLog(.error, "Server error occurred")
        serverManager.addLog(.warning, "Client disconnected")

        let serverLogs = serverManager.getFilteredLogs(searchText: "server")
        XCTAssertEqual(serverLogs.count, 2)

        let clientLogs = serverManager.getFilteredLogs(searchText: "client")
        XCTAssertEqual(clientLogs.count, 2)

        let errorLogs = serverManager.getFilteredLogs(searchText: "error")
        XCTAssertEqual(errorLogs.count, 1)
    }

    func testGetFilteredLogsByLevelAndSearchText() {
        serverManager.addLog(.info, "Server started")
        serverManager.addLog(.error, "Server failed")
        serverManager.addLog(.info, "Client connected")
        serverManager.addLog(.error, "Client error")

        let serverErrorLogs = serverManager.getFilteredLogs(level: .error, searchText: "server")
        XCTAssertEqual(serverErrorLogs.count, 1)
        XCTAssertEqual(serverErrorLogs.first?.message, "Server failed")

        let infoClientLogs = serverManager.getFilteredLogs(level: .info, searchText: "client")
        XCTAssertEqual(infoClientLogs.count, 1)
        XCTAssertEqual(infoClientLogs.first?.message, "Client connected")
    }

    func testGetFilteredLogsWithNoMatches() {
        serverManager.addLog(.info, "Server started")
        serverManager.addLog(.warning, "Client warning")

        let noMatchLogs = serverManager.getFilteredLogs(searchText: "nonexistent")
        XCTAssertEqual(noMatchLogs.count, 0)

        let noMatchLevel = serverManager.getFilteredLogs(level: .error)
        XCTAssertEqual(noMatchLevel.count, 0)
    }

    // MARK: - Log Export Tests

    func testExportLogsWithNoLogs() {
        serverManager.logs.removeAll()
        let exported = serverManager.exportLogs()
        XCTAssertTrue(exported.isEmpty)
    }

    func testExportLogsWithSingleLog() {
        serverManager.addLog(.info, "Single log message")
        let exported = serverManager.exportLogs()

        XCTAssertTrue(exported.contains("[INFO]"))
        XCTAssertTrue(exported.contains("Single log message"))
    }

    func testExportLogsWithMultipleLevels() {
        serverManager.addLog(.debug, "Debug message")
        serverManager.addLog(.info, "Info message")
        serverManager.addLog(.warning, "Warning message")
        serverManager.addLog(.error, "Error message")

        let exported = serverManager.exportLogs()

        XCTAssertTrue(exported.contains("[DEBUG]"))
        XCTAssertTrue(exported.contains("[INFO]"))
        XCTAssertTrue(exported.contains("[WARNING]"))
        XCTAssertTrue(exported.contains("[ERROR]"))
    }

    // MARK: - URL Generation Tests

    func testConnectionStringGeneration() {
        settingsManager.serverPort = 3001
        serverManager.isRunning = true

        // Test localhost URL
        let expectedURL = "http://localhost:3001"
        XCTAssertTrue(serverManager.connectionString.contains("3001"))
    }

    func testPublicURLHandling() {
        let testURL = "https://test.ngrok.io"
        serverManager.publicURL = testURL

        XCTAssertEqual(serverManager.publicURL, testURL)

        // Clear public URL
        serverManager.publicURL = nil
        XCTAssertNil(serverManager.publicURL)
    }

    // MARK: - Processing State Tests

    func testProcessingState() {
        XCTAssertFalse(serverManager.isProcessing)

        serverManager.isProcessing = true
        XCTAssertTrue(serverManager.isProcessing)

        serverManager.isProcessing = false
        XCTAssertFalse(serverManager.isProcessing)
    }

    // MARK: - Server Start Time Tests

    func testServerStartTime() {
        // Initially should be nil
        XCTAssertNil(serverManager.serverStartTime)

        let testDate = Date()
        serverManager.serverStartTime = testDate
        XCTAssertEqual(serverManager.serverStartTime, testDate)

        serverManager.serverStartTime = nil
        XCTAssertNil(serverManager.serverStartTime)
    }

    // MARK: - Performance Tests

    func testAddLogPerformance() {
        measure {
            for i in 0..<1000 {
                serverManager.addLog(.info, "Performance test log \(i)")
            }
            serverManager.logs.removeAll()
        }
    }

    func testFilterLogsPerformance() {
        // Add many logs
        for i in 0..<1000 {
            serverManager.addLog(i % 2 == 0 ? .info : .error, "Test log \(i)")
        }

        measure {
            _ = serverManager.getFilteredLogs(level: .info)
        }

        serverManager.logs.removeAll()
    }

    func testExportLogsPerformance() {
        // Add many logs
        for i in 0..<1000 {
            serverManager.addLog(.info, "Performance test log \(i)")
        }

        measure {
            _ = serverManager.exportLogs()
        }

        serverManager.logs.removeAll()
    }
}
