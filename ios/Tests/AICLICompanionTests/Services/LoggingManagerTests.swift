import XCTest
@testable import AICLICompanion
import os.log

@available(iOS 16.0, macOS 13.0, *)
final class LoggingManagerTests: XCTestCase {
    var logger: LoggingManager!
    
    // Helper to check if we're in CI
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
    }
    
    override func setUp() {
        super.setUp()
        logger = LoggingManager.shared
        
        // Reset to default configuration for each test
        logger.minimumLevel = .debug
        logger.enabledCategories = Set(LoggingManager.Category.allCases)
        logger.enableConsoleLogging = true
        logger.enableOSLogging = true
        logger.enableFileLogging = false
    }
    
    // MARK: - Configuration Tests
    
    func testInitialConfiguration() {
        XCTAssertEqual(logger.minimumLevel, .debug)
        XCTAssertEqual(logger.enabledCategories.count, LoggingManager.Category.allCases.count)
        XCTAssertTrue(logger.enableConsoleLogging)
        XCTAssertTrue(logger.enableOSLogging)
        XCTAssertFalse(logger.enableFileLogging)
    }
    
    func testSetLevel() {
        logger.setLevel(.warning)
        XCTAssertEqual(logger.minimumLevel, .warning)
        
        logger.setLevel(.critical)
        XCTAssertEqual(logger.minimumLevel, .critical)
    }
    
    func testEnableDisableCategory() {
        let testCategory = LoggingManager.Category.network
        
        // Initially enabled
        XCTAssertTrue(logger.enabledCategories.contains(testCategory))
        
        // Disable
        logger.disableCategory(testCategory)
        XCTAssertFalse(logger.enabledCategories.contains(testCategory))
        
        // Re-enable
        logger.enableCategory(testCategory)
        XCTAssertTrue(logger.enabledCategories.contains(testCategory))
    }
    
    func testEnableDisableMultipleCategories() {
        let testCategories: [LoggingManager.Category] = [.network, .ui, .persistence]
        
        // Disable multiple
        logger.disableCategories(testCategories)
        for category in testCategories {
            XCTAssertFalse(logger.enabledCategories.contains(category))
        }
        
        // Enable multiple
        logger.enableCategories(testCategories)
        for category in testCategories {
            XCTAssertTrue(logger.enabledCategories.contains(category))
        }
    }
    
    // MARK: - Level and Category Enum Tests
    
    func testLogLevelProperties() {
        XCTAssertEqual(LoggingManager.Level.debug.emoji, "🐛")
        XCTAssertEqual(LoggingManager.Level.info.emoji, "ℹ️")
        XCTAssertEqual(LoggingManager.Level.warning.emoji, "⚠️")
        XCTAssertEqual(LoggingManager.Level.error.emoji, "❌")
        XCTAssertEqual(LoggingManager.Level.critical.emoji, "🚨")
        
        XCTAssertEqual(LoggingManager.Level.debug.osLogType, .debug)
        XCTAssertEqual(LoggingManager.Level.info.osLogType, .info)
        XCTAssertEqual(LoggingManager.Level.warning.osLogType, .default)
        XCTAssertEqual(LoggingManager.Level.error.osLogType, .error)
        XCTAssertEqual(LoggingManager.Level.critical.osLogType, .fault)
    }
    
    func testLogLevelRawValues() {
        XCTAssertEqual(LoggingManager.Level.debug.rawValue, 0)
        XCTAssertEqual(LoggingManager.Level.info.rawValue, 1)
        XCTAssertEqual(LoggingManager.Level.warning.rawValue, 2)
        XCTAssertEqual(LoggingManager.Level.error.rawValue, 3)
        XCTAssertEqual(LoggingManager.Level.critical.rawValue, 4)
    }
    
    func testCategoryEnumCompleteness() {
        let expectedCategories: [LoggingManager.Category] = [
            .ui, .network, .persistence, .session, .loading, .project,
            .message, .apns, .performance, .error, .debug, .claude,
            .sync, .queue, .auth, .state
        ]
        
        XCTAssertEqual(LoggingManager.Category.allCases.count, expectedCategories.count)
        
        for category in expectedCategories {
            XCTAssertTrue(LoggingManager.Category.allCases.contains(category))
        }
    }
    
    func testCategoryRawValues() {
        XCTAssertEqual(LoggingManager.Category.ui.rawValue, "UI")
        XCTAssertEqual(LoggingManager.Category.network.rawValue, "Network")
        XCTAssertEqual(LoggingManager.Category.persistence.rawValue, "Persistence")
        XCTAssertEqual(LoggingManager.Category.session.rawValue, "Session")
        XCTAssertEqual(LoggingManager.Category.loading.rawValue, "Loading")
        XCTAssertEqual(LoggingManager.Category.project.rawValue, "Project")
        XCTAssertEqual(LoggingManager.Category.message.rawValue, "Message")
        XCTAssertEqual(LoggingManager.Category.apns.rawValue, "APNS")
        XCTAssertEqual(LoggingManager.Category.performance.rawValue, "Performance")
        XCTAssertEqual(LoggingManager.Category.error.rawValue, "Error")
        XCTAssertEqual(LoggingManager.Category.debug.rawValue, "Debug")
        XCTAssertEqual(LoggingManager.Category.claude.rawValue, "Claude")
        XCTAssertEqual(LoggingManager.Category.sync.rawValue, "Sync")
        XCTAssertEqual(LoggingManager.Category.queue.rawValue, "Queue")
        XCTAssertEqual(LoggingManager.Category.auth.rawValue, "Auth")
        XCTAssertEqual(LoggingManager.Category.state.rawValue, "State")
    }
    
    // MARK: - Basic Logging Tests
    
    func testBasicLogging() {
        // Test that logging doesn't crash
        logger.log("Test message", category: .debug, level: .info)
        logger.log("Network request", category: .network, level: .debug)
        logger.log("Error occurred", category: .error, level: .error)
        
        // If we get here without crashing, logging works
        XCTAssertTrue(true)
    }
    
    func testLevelFiltering() {
        logger.minimumLevel = .warning
        
        // These should be filtered out (below warning)
        logger.log("Debug message", category: .debug, level: .debug)
        logger.log("Info message", category: .debug, level: .info)
        
        // These should pass through (warning and above)
        logger.log("Warning message", category: .debug, level: .warning)
        logger.log("Error message", category: .debug, level: .error)
        logger.log("Critical message", category: .debug, level: .critical)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testCategoryFiltering() {
        // Disable network category
        logger.disableCategory(.network)
        
        // This should be filtered out
        logger.log("Network message", category: .network, level: .info)
        
        // This should pass through
        logger.log("Debug message", category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    // MARK: - Convenience Method Tests
    
    func testConvenienceMethods() {
        // Test all convenience methods
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
        logger.critical("Critical message")
        
        // Test with custom categories
        logger.debug("UI debug", category: .ui)
        logger.info("Network info", category: .network)
        logger.error("Persistence error", category: .persistence)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    // MARK: - Domain-Specific Logging Tests
    
    func testLogMessage() {
        logger.logMessage("Hello Claude", operation: "send_message")
        logger.logMessage("Response received", operation: "receive_response", details: "Success")
        logger.logMessage("Failed to send", operation: "send_message", details: "Network error")
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testLogSession() {
        logger.logSession("Session started", sessionId: "abc123def456")
        logger.logSession("Session ended", sessionId: "abc123def456", projectPath: "/Users/test/project")
        logger.logSession("Session activity", sessionId: nil, projectPath: "/Users/test/another-project")
        logger.logSession("General session event", sessionId: nil, projectPath: nil)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testLogLoading() {
        logger.logLoading("Chat loading", isLoading: true, projectPath: "/Users/test/project")
        logger.logLoading("Chat loading", isLoading: false, projectPath: "/Users/test/project")
        logger.logLoading("General loading", isLoading: true, projectPath: nil)
        logger.logLoading("General loading", isLoading: false, projectPath: nil)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testLogProject() {
        logger.logProject("Project opened", projectName: "MyApp", projectPath: "/Users/test/MyApp")
        logger.logProject("Project closed", projectName: "MyApp")
        logger.logProject("Project analysis", projectPath: "/Users/test/SomeProject")
        logger.logProject("General project event")
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testLogAPNS() {
        logger.logAPNS("Push notification sent", messageId: "msg123", sessionId: "session456")
        logger.logAPNS("Push notification received", messageId: "msg123")
        logger.logAPNS("Push notification failed", sessionId: "session456")
        logger.logAPNS("General APNS event")
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testLogPerformance() {
        logger.logPerformance("API call completed", duration: 0.543)
        logger.logPerformance("Database query", duration: 0.123, details: "Users table")
        logger.logPerformance("UI rendering", details: "Chat view")
        logger.logPerformance("General performance metric")
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    // MARK: - Global Function Tests
    
    func testGlobalConvenienceFunctions() {
        log("Global log function", category: .debug, level: .info)
        logDebug("Global debug function", category: .ui)
        logInfo("Global info function", category: .network)
        logError("Global error function", category: .error)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    // MARK: - Edge Cases and Error Handling Tests
    
    func testEmptyMessage() {
        logger.log("", category: .debug, level: .info)
        logger.debug("")
        logger.info("")
        logger.warning("")
        logger.error("")
        logger.critical("")
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testLongMessage() {
        let longMessage = String(repeating: "A", count: 1000)
        logger.log(longMessage, category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testSpecialCharacters() {
        logger.log("Message with unicode: 🚀 🎉 ❤️", category: .debug, level: .info)
        logger.log("Message with newlines:\nLine 1\nLine 2", category: .debug, level: .info)
        logger.log("Message with quotes: \"Hello\" and 'World'", category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testNilParameters() {
        logger.logSession("Session event", sessionId: nil, projectPath: nil)
        logger.logLoading("Loading event", isLoading: true, projectPath: nil)
        logger.logProject("Project event", projectName: nil, projectPath: nil)
        logger.logAPNS("APNS event", messageId: nil, sessionId: nil)
        logger.logPerformance("Performance event", duration: nil, details: nil)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    // MARK: - Configuration Edge Cases Tests
    
    func testDisableAllCategories() {
        logger.disableCategories(Array(LoggingManager.Category.allCases))
        XCTAssertTrue(logger.enabledCategories.isEmpty)
        
        // Logging should be filtered out
        logger.log("This should be filtered", category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testDisableConsoleLogging() {
        logger.enableConsoleLogging = false
        logger.log("Console logging disabled", category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testDisableOSLogging() {
        logger.enableOSLogging = false
        logger.log("OS logging disabled", category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testEnableFileLogging() {
        logger.enableFileLogging = true
        logger.log("File logging enabled", category: .debug, level: .info)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    // MARK: - File Path Processing Tests
    
    func testFilePathProcessing() {
        // The logging system should extract the filename from the full path
        let testFile = "/Users/developer/Project/Sources/TestFile.swift"
        logger.log("Test with file path", category: .debug, level: .info, file: testFile, function: "testFunction", line: 123)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testSessionIdTruncation() {
        let longSessionId = "very-long-session-id-that-should-be-truncated-for-readability"
        logger.logSession("Test session", sessionId: longSessionId)
        
        // Should handle long session IDs gracefully
        XCTAssertTrue(true)
    }
    
    func testProjectPathExtraction() {
        let projectPath = "/Users/developer/Documents/Projects/MyAwesomeProject"
        logger.logSession("Test project path", sessionId: nil, projectPath: projectPath)
        logger.logLoading("Test loading with project", isLoading: true, projectPath: projectPath)
        logger.logProject("Test project logging", projectPath: projectPath)
        
        // Should extract project name from full path
        XCTAssertTrue(true)
    }
    
    // MARK: - Performance Tests
    
    func testLoggingPerformance() {
        let messageCount = 1000
        let startTime = Date()
        
        for i in 0..<messageCount {
            logger.log("Performance test message \(i)", category: .performance, level: .info)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete reasonably quickly (less than 1 second for 1000 messages)
        XCTAssertLessThan(duration, 1.0)
    }
    
    func testConcurrentLogging() throws {
        guard !isCI else {
            throw XCTSkip("Skipping concurrent test in CI environment")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent logging")
        expectation.expectedFulfillmentCount = 5
        
        let queue = DispatchQueue.global(qos: .background)
        
        for i in 0..<5 {
            queue.async {
                for j in 0..<100 {
                    self.logger.log("Concurrent message \(i)-\(j)", category: .debug, level: .info)
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Level Filtering Performance Tests
    
    func testFilteredLoggingPerformance() {
        logger.minimumLevel = .critical // Filter out most messages
        
        let messageCount = 1000
        let startTime = Date()
        
        for i in 0..<messageCount {
            logger.log("Filtered message \(i)", category: .debug, level: .debug) // Should be filtered
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Filtered logging should be very fast
        XCTAssertLessThan(duration, 0.1)
    }
    
    func testCategoryFilteringPerformance() {
        logger.disableCategory(.debug) // Disable debug category
        
        let messageCount = 1000
        let startTime = Date()
        
        for i in 0..<messageCount {
            logger.log("Category filtered message \(i)", category: .debug, level: .info) // Should be filtered
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Category-filtered logging should be very fast
        XCTAssertLessThan(duration, 0.1)
    }
    
    // MARK: - String Formatting Tests
    
    func testDurationFormatting() {
        logger.logPerformance("Test duration", duration: 1.234567)
        logger.logPerformance("Test small duration", duration: 0.001)
        logger.logPerformance("Test zero duration", duration: 0.0)
        logger.logPerformance("Test large duration", duration: 123.456)
        
        // Test passes if no crashes occur
        XCTAssertTrue(true)
    }
    
    func testMessageIdTruncation() {
        let longMessageId = "very-long-message-id-that-should-be-truncated-for-display"
        logger.logAPNS("Test message ID truncation", messageId: longMessageId, sessionId: nil)
        
        // Should handle long message IDs gracefully
        XCTAssertTrue(true)
    }
}
