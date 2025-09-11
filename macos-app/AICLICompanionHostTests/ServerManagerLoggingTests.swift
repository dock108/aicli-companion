//
//  ServerManagerLoggingTests.swift
//  AICLICompanionHostTests
//
//  Tests for ServerManager's logging functionality
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ServerManagerLoggingTests: XCTestCase {
    var serverManager: ServerManager!

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        serverManager.logs.removeAll()
    }

    override func tearDown() async throws {
        serverManager.logs.removeAll()
        try await super.tearDown()
    }

    // MARK: - Log Level Tests

    func testLogLevels() {
        serverManager.addLog(.debug, "Debug message")
        serverManager.addLog(.info, "Info message")
        serverManager.addLog(.warning, "Warning message")
        serverManager.addLog(.error, "Error message")

        XCTAssertEqual(serverManager.logs.count, 4)

        XCTAssertTrue(serverManager.logs.contains { $0.level == .debug && $0.message == "Debug message" })
        XCTAssertTrue(serverManager.logs.contains { $0.level == .info && $0.message == "Info message" })
        XCTAssertTrue(serverManager.logs.contains { $0.level == .warning && $0.message == "Warning message" })
        XCTAssertTrue(serverManager.logs.contains { $0.level == .error && $0.message == "Error message" })
    }

    // MARK: - Log Rotation Tests

    func testMaxLogEntries() {
        let maxEntries = SettingsManager.shared.maxLogEntries

        // Add more than max entries
        for i in 0..<(maxEntries + 100) {
            serverManager.addLog(.info, "Log entry \(i)")
        }

        // Should not exceed max entries
        XCTAssertLessThanOrEqual(serverManager.logs.count, maxEntries)

        // Latest logs should be kept
        XCTAssertTrue(serverManager.logs.last?.message.contains("Log entry \(maxEntries + 99)") ?? false)
    }

    func testLogRotationKeepsNewestEntries() {
        let maxEntries = 100
        SettingsManager.shared.maxLogEntries = maxEntries

        // Add exactly max entries
        for i in 0..<maxEntries {
            serverManager.addLog(.info, "Initial \(i)")
        }

        XCTAssertEqual(serverManager.logs.count, maxEntries)

        // Add one more
        serverManager.addLog(.info, "New entry")

        // Should still have max entries
        XCTAssertEqual(serverManager.logs.count, maxEntries)

        // Newest entry should be present
        XCTAssertTrue(serverManager.logs.contains { $0.message == "New entry" })

        // Oldest entry should be removed
        XCTAssertFalse(serverManager.logs.contains { $0.message == "Initial 0" })
    }

    // MARK: - Log Filtering Tests

    func testFilterLogsByLevel() {
        serverManager.addLog(.debug, "Debug 1")
        serverManager.addLog(.info, "Info 1")
        serverManager.addLog(.warning, "Warning 1")
        serverManager.addLog(.error, "Error 1")
        serverManager.addLog(.debug, "Debug 2")
        serverManager.addLog(.error, "Error 2")

        let debugLogs = serverManager.logs.filter { $0.level == .debug }
        XCTAssertEqual(debugLogs.count, 2)

        let errorLogs = serverManager.logs.filter { $0.level == .error }
        XCTAssertEqual(errorLogs.count, 2)

        let warningAndAbove = serverManager.logs.filter {
            $0.level == .warning || $0.level == .error
        }
        XCTAssertEqual(warningAndAbove.count, 3)
    }

    func testFilterLogsByMessage() {
        serverManager.addLog(.info, "Server started")
        serverManager.addLog(.info, "Server stopped")
        serverManager.addLog(.error, "Server crashed")
        serverManager.addLog(.info, "Client connected")

        let serverLogs = serverManager.logs.filter { $0.message.contains("Server") }
        XCTAssertEqual(serverLogs.count, 3)

        let startedLogs = serverManager.logs.filter { $0.message.contains("started") }
        XCTAssertEqual(startedLogs.count, 1)
    }

    // MARK: - Log Export Tests

    func testExportLogs() {
        serverManager.addLog(.info, "Test log 1")
        serverManager.addLog(.error, "Test error")
        serverManager.addLog(.warning, "Test warning")

        let exportedLogs = serverManager.exportLogs()

        XCTAssertFalse(exportedLogs.isEmpty)
        XCTAssertTrue(exportedLogs.contains("Test log 1"))
        XCTAssertTrue(exportedLogs.contains("Test error"))
        XCTAssertTrue(exportedLogs.contains("Test warning"))

        // Should include log levels
        XCTAssertTrue(exportedLogs.contains("[INFO]") || exportedLogs.contains("INFO"))
        XCTAssertTrue(exportedLogs.contains("[ERROR]") || exportedLogs.contains("ERROR"))
    }

    func testExportLogsWithEmptyLogs() {
        serverManager.logs.removeAll()
        let exportedLogs = serverManager.exportLogs()

        // Should handle empty logs gracefully
        XCTAssertTrue(exportedLogs.isEmpty || exportedLogs == "No logs available")
    }

    // MARK: - Log Clearing Tests

    func testClearLogs() {
        serverManager.addLog(.info, "Log 1")
        serverManager.addLog(.info, "Log 2")
        serverManager.addLog(.info, "Log 3")

        XCTAssertEqual(serverManager.logs.count, 3)

        serverManager.clearLogs()

        XCTAssertEqual(serverManager.logs.count, 0)
    }

    // MARK: - Log Formatting Tests

    func testLogEntryFormatting() {
        let entry = LogEntry(level: .info, message: "Test message")

        XCTAssertNotNil(entry.timestamp)
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.message, "Test message")

        // Test log level icons
        XCTAssertEqual(LogLevel.debug.icon, "ladybug")
        XCTAssertEqual(LogLevel.info.icon, "info.circle")
        XCTAssertEqual(LogLevel.warning.icon, "exclamationmark.triangle")
        XCTAssertEqual(LogLevel.error.icon, "xmark.circle")
    }

    // MARK: - Concurrent Logging Tests

    func testConcurrentLogging() async {
        let expectation = XCTestExpectation(description: "Concurrent logging")

        // Add logs from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { [weak self] in
                    await self?.serverManager.addLog(.info, "Concurrent log \(i)")
                }
            }
        }

        // All logs should be added
        XCTAssertEqual(serverManager.logs.count, 10)

        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Performance Tests

    func testLoggingPerformance() {
        measure {
            for i in 0..<1000 {
                serverManager.addLog(.info, "Performance test log \(i)")
            }
            serverManager.logs.removeAll()
        }
    }
}
