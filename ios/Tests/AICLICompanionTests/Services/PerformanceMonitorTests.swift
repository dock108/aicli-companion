import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class PerformanceMonitorTests: XCTestCase {
    
    var monitor: PerformanceMonitor!
    
    override func setUp() {
        super.setUp()
        // Each test gets a fresh monitor instance via shared singleton
        monitor = PerformanceMonitor.shared
        monitor.startSession() // Reset state for each test
    }
    
    // MARK: - Message Tracking Tests
    
    func testMessageTrackingBasics() {
        let messageId = "test-msg-001"
        let messageType = "chat"
        
        let startTime = monitor.startMessageTracking(messageId: messageId, type: messageType)
        
        XCTAssertNotNil(startTime)
        XCTAssertLessThanOrEqual(startTime.timeIntervalSinceNow, 0) // Should be in the past
        XCTAssertGreaterThan(startTime.timeIntervalSinceNow, -1) // But very recent
    }
    
    func testMessageTrackingCompletion() {
        let messageId = "test-msg-002"
        let messageType = "command"
        
        let startTime = monitor.startMessageTracking(messageId: messageId, type: messageType)
        
        // Wait a small amount to ensure measurable processing time
        Thread.sleep(forTimeInterval: 0.01)
        
        let initialCount = monitor.messagesProcessedCount
        monitor.completeMessageTracking(messageId: messageId, startTime: startTime, type: messageType, success: true)
        
        XCTAssertEqual(monitor.messagesProcessedCount, initialCount + 1)
    }
    
    func testMessageTrackingWithFailure() {
        let messageId = "test-msg-003"
        let messageType = "error"
        let startTime = Date()
        
        monitor.completeMessageTracking(messageId: messageId, startTime: startTime, type: messageType, success: false)
        
        // Should still increment count even for failures
        XCTAssertGreaterThan(monitor.messagesProcessedCount, 0)
    }
    
    func testMultipleMessageTracking() {
        let messageTypes = ["chat", "command", "system", "error"]
        let startCounts = monitor.messagesProcessedCount
        
        for (index, messageType) in messageTypes.enumerated() {
            let messageId = "msg-\(index)"
            let startTime = monitor.startMessageTracking(messageId: messageId, type: messageType)
            monitor.completeMessageTracking(messageId: messageId, startTime: startTime, type: messageType)
        }
        
        XCTAssertEqual(monitor.messagesProcessedCount, startCounts + messageTypes.count)
    }
    
    // MARK: - Connection Event Tests
    
    func testConnectionEstablished() {
        monitor.recordConnectionEstablished()
        
        // Should update connection stability score
        XCTAssertGreaterThanOrEqual(monitor.connectionStabilityScore, 0)
        XCTAssertLessThanOrEqual(monitor.connectionStabilityScore, 100)
    }
    
    func testConnectionLost() {
        // First establish a connection
        monitor.recordConnectionEstablished()
        
        // Wait a bit then lose connection
        Thread.sleep(forTimeInterval: 0.01)
        monitor.recordConnectionLost()
        
        // Connection stability should still be within valid range
        XCTAssertGreaterThanOrEqual(monitor.connectionStabilityScore, 0)
        XCTAssertLessThanOrEqual(monitor.connectionStabilityScore, 100)
    }
    
    func testConnectionEventSequence() {
        // Test a sequence of connection events
        monitor.recordConnectionEstablished()
        monitor.recordConnectionLost()
        monitor.recordConnectionEstablished()
        
        // Should handle multiple events without crashing
        XCTAssertTrue(true) // If we get here, the sequence worked
    }
    
    // MARK: - Session Management Tests
    
    func testSessionStart() {
        let initialCount = monitor.messagesProcessedCount
        
        monitor.startSession()
        
        // Should reset counters
        XCTAssertEqual(monitor.messagesProcessedCount, 0)
        XCTAssertLessThanOrEqual(monitor.messagesProcessedCount, initialCount)
    }
    
    func testSessionStartResetsCounters() {
        // Process some messages first
        for i in 0..<3 {
            let messageId = "msg-\(i)"
            let startTime = monitor.startMessageTracking(messageId: messageId, type: "test")
            monitor.completeMessageTracking(messageId: messageId, startTime: startTime, type: "test")
        }
        
        XCTAssertEqual(monitor.messagesProcessedCount, 3)
        
        // Start new session
        monitor.startSession()
        
        // Counters should be reset
        XCTAssertEqual(monitor.messagesProcessedCount, 0)
    }
    
    // MARK: - Performance Metrics Tests
    
    func testPerformanceMetricsStructure() {
        let metrics = monitor.getCurrentMetrics(sessionId: "test-session")
        
        XCTAssertNotNil(metrics.timestamp)
        XCTAssertEqual(metrics.sessionId, "test-session")
        XCTAssertNotNil(metrics.metrics.messageProcessing)
        XCTAssertNotNil(metrics.metrics.connection)
        XCTAssertNotNil(metrics.metrics.app)
    }
    
    func testMessageProcessingMetrics() {
        let metrics = monitor.getCurrentMetrics()
        let messageMetrics = metrics.metrics.messageProcessing
        
        XCTAssertGreaterThanOrEqual(messageMetrics.averageProcessingTime, 0)
        XCTAssertGreaterThanOrEqual(messageMetrics.messageCount, 0)
        XCTAssertGreaterThanOrEqual(messageMetrics.successRate, 0)
        XCTAssertLessThanOrEqual(messageMetrics.successRate, 1.0)
        XCTAssertGreaterThanOrEqual(messageMetrics.p95ProcessingTime, 0)
    }
    
    func testConnectionMetrics() {
        let metrics = monitor.getCurrentMetrics()
        let connectionMetrics = metrics.metrics.connection
        
        XCTAssertGreaterThanOrEqual(connectionMetrics.uptime, 0)
        XCTAssertGreaterThanOrEqual(connectionMetrics.stabilityScore, 0)
        XCTAssertLessThanOrEqual(connectionMetrics.stabilityScore, 100)
        XCTAssertGreaterThanOrEqual(connectionMetrics.reconnectionCount, 0)
        XCTAssertGreaterThanOrEqual(connectionMetrics.averageReconnectionTime, 0)
    }
    
    func testAppMetrics() {
        let metrics = monitor.getCurrentMetrics()
        let appMetrics = metrics.metrics.app
        
        XCTAssertGreaterThanOrEqual(appMetrics.memoryUsage, 0)
        XCTAssertGreaterThanOrEqual(appMetrics.sessionDuration, 0)
        XCTAssertEqual(appMetrics.platform, "iOS")
        XCTAssertFalse(appMetrics.appVersion.isEmpty)
    }
    
    // MARK: - Data Structure Tests
    
    func testMessageTimingCreation() {
        let messageId = "timing-test-001"
        let startTime = Date()
        let endTime = Date().addingTimeInterval(0.1)
        let messageType = "test"
        
        let timing = PerformanceMonitor.MessageTiming(
            messageId: messageId,
            startTime: startTime,
            endTime: endTime,
            messageType: messageType,
            success: true
        )
        
        XCTAssertEqual(timing.messageId, messageId)
        XCTAssertEqual(timing.startTime, startTime)
        XCTAssertEqual(timing.endTime, endTime)
        XCTAssertEqual(timing.messageType, messageType)
        XCTAssertTrue(timing.success)
        XCTAssertEqual(timing.processingTime, endTime.timeIntervalSince(startTime))
    }
    
    func testConnectionEventCreation() {
        let timestamp = Date()
        let duration: TimeInterval = 60.0
        
        let event = PerformanceMonitor.ConnectionEvent(
            timestamp: timestamp,
            type: .connected,
            duration: duration
        )
        
        XCTAssertEqual(event.timestamp, timestamp)
        XCTAssertEqual(event.type, .connected)
        XCTAssertEqual(event.duration, duration)
    }
    
    func testConnectionEventTypes() {
        let eventTypes: [PerformanceMonitor.ConnectionEvent.EventType] = [
            .connected, .disconnected, .reconnected, .error
        ]
        
        for eventType in eventTypes {
            let event = PerformanceMonitor.ConnectionEvent(
                timestamp: Date(),
                type: eventType,
                duration: nil
            )
            XCTAssertEqual(event.type, eventType)
        }
    }
    
    // MARK: - Performance Metrics Data Model Tests
    
    func testPerformanceMetricsCodable() throws {
        let metrics = PerformanceMonitor.PerformanceMetrics(
            timestamp: Date(),
            sessionId: "test-session",
            metrics: PerformanceMonitor.PerformanceMetrics.Metrics(
                messageProcessing: PerformanceMonitor.PerformanceMetrics.MessageProcessingMetrics(
                    averageProcessingTime: 1.5,
                    messageCount: 10,
                    successRate: 0.95,
                    p95ProcessingTime: 2.1
                ),
                connection: PerformanceMonitor.PerformanceMetrics.ConnectionMetrics(
                    uptime: 3600,
                    stabilityScore: 95.0,
                    reconnectionCount: 2,
                    averageReconnectionTime: 5.0
                ),
                app: PerformanceMonitor.PerformanceMetrics.AppMetrics(
                    memoryUsage: 128.5,
                    sessionDuration: 7200,
                    platform: "iOS",
                    appVersion: "1.0.0"
                )
            )
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(metrics)
        XCTAssertGreaterThan(data.count, 0)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedMetrics = try decoder.decode(PerformanceMonitor.PerformanceMetrics.self, from: data)
        
        XCTAssertEqual(decodedMetrics.sessionId, "test-session")
        XCTAssertEqual(decodedMetrics.metrics.messageProcessing.messageCount, 10)
        XCTAssertEqual(decodedMetrics.metrics.connection.stabilityScore, 95.0)
        XCTAssertEqual(decodedMetrics.metrics.app.platform, "iOS")
    }
    
    func testMessageProcessingMetricsDefaults() {
        let metrics = PerformanceMonitor.PerformanceMetrics.MessageProcessingMetrics(
            averageProcessingTime: 0,
            messageCount: 0,
            successRate: 0,
            p95ProcessingTime: 0
        )
        
        XCTAssertEqual(metrics.averageProcessingTime, 0)
        XCTAssertEqual(metrics.messageCount, 0)
        XCTAssertEqual(metrics.successRate, 0)
        XCTAssertEqual(metrics.p95ProcessingTime, 0)
    }
    
    func testConnectionMetricsDefaults() {
        let metrics = PerformanceMonitor.PerformanceMetrics.ConnectionMetrics(
            uptime: 0,
            stabilityScore: 100.0,
            reconnectionCount: 0,
            averageReconnectionTime: 0
        )
        
        XCTAssertEqual(metrics.uptime, 0)
        XCTAssertEqual(metrics.stabilityScore, 100.0)
        XCTAssertEqual(metrics.reconnectionCount, 0)
        XCTAssertEqual(metrics.averageReconnectionTime, 0)
    }
    
    // MARK: - Edge Cases and Error Handling Tests
    
    func testMessageTrackingWithSameId() {
        let messageId = "duplicate-id"
        let messageType = "test"
        
        // Track same message ID multiple times
        let startTime1 = monitor.startMessageTracking(messageId: messageId, type: messageType)
        let startTime2 = monitor.startMessageTracking(messageId: messageId, type: messageType)
        
        // Both should return valid times
        XCTAssertNotNil(startTime1)
        XCTAssertNotNil(startTime2)
        
        // Complete both
        monitor.completeMessageTracking(messageId: messageId, startTime: startTime1, type: messageType)
        monitor.completeMessageTracking(messageId: messageId, startTime: startTime2, type: messageType)
        
        // Should handle duplicates gracefully
        XCTAssertGreaterThanOrEqual(monitor.messagesProcessedCount, 2)
    }
    
    func testConnectionEventsWithoutEstablishing() {
        // Try to record connection lost without establishing first
        monitor.recordConnectionLost()
        
        // Should handle gracefully
        XCTAssertGreaterThanOrEqual(monitor.connectionStabilityScore, 0)
    }
    
    func testZeroProcessingTime() {
        let messageId = "instant-msg"
        let messageType = "instant"
        let now = Date()
        
        // Complete with same start and end time
        monitor.completeMessageTracking(messageId: messageId, startTime: now, type: messageType)
        
        // Should handle zero processing time
        XCTAssertEqual(monitor.messagesProcessedCount, 1)
    }
    
    func testNegativeProcessingTime() {
        let messageId = "negative-msg"
        let messageType = "negative"
        let futureTime = Date().addingTimeInterval(10) // Future time
        
        // Complete with future start time (negative processing time)
        monitor.completeMessageTracking(messageId: messageId, startTime: futureTime, type: messageType)
        
        // Should handle negative processing time gracefully
        XCTAssertEqual(monitor.messagesProcessedCount, 1)
    }
    
    // MARK: - Published Properties Tests
    
    func testPublishedPropertiesInitialValues() {
        // Test initial published property values
        XCTAssertGreaterThanOrEqual(monitor.averageMessageProcessingTime, 0)
        XCTAssertGreaterThanOrEqual(monitor.connectionUptime, 0)
        XCTAssertGreaterThanOrEqual(monitor.messagesProcessedCount, 0)
        XCTAssertGreaterThanOrEqual(monitor.connectionStabilityScore, 0)
        XCTAssertLessThanOrEqual(monitor.connectionStabilityScore, 100)
    }
    
    func testConnectionStabilityScoreRange() {
        // Test that stability score stays in valid range
        for _ in 0..<5 {
            monitor.recordConnectionLost()
        }
        
        XCTAssertGreaterThanOrEqual(monitor.connectionStabilityScore, 0)
        XCTAssertLessThanOrEqual(monitor.connectionStabilityScore, 100)
    }
    
    // MARK: - Memory and Performance Tests
    
    func testMemoryUsageCalculation() {
        let metrics = monitor.getCurrentMetrics()
        let memoryUsage = metrics.metrics.app.memoryUsage
        
        // Memory usage should be positive and reasonable (< 1GB for tests)
        XCTAssertGreaterThan(memoryUsage, 0)
        XCTAssertLessThan(memoryUsage, 1024) // Less than 1GB
    }
    
    func testSessionDurationCalculation() {
        monitor.startSession()
        
        // Wait a bit
        Thread.sleep(forTimeInterval: 0.1)
        
        let metrics = monitor.getCurrentMetrics()
        let sessionDuration = metrics.metrics.app.sessionDuration
        
        XCTAssertGreaterThanOrEqual(sessionDuration, 0.1)
        XCTAssertLessThan(sessionDuration, 10) // Should be very short for tests
    }
    
    func testAppVersionRetrieval() {
        let metrics = monitor.getCurrentMetrics()
        let appVersion = metrics.metrics.app.appVersion
        
        // Should have some version string (though might be "Unknown" in test environment)
        XCTAssertFalse(appVersion.isEmpty)
    }
}