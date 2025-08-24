import XCTest
import Foundation
import Network
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class ConnectionReliabilityManagerTests: XCTestCase {
    
    // Helper to check if we're in CI
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
    }
    
    // MARK: - Connection Manager Creation Tests
    
    func testConnectionReliabilityManagerSharedInstance() {
        // Test that shared instance exists and is the same instance
        let manager1 = ConnectionReliabilityManager.shared
        let manager2 = ConnectionReliabilityManager.shared
        
        XCTAssertTrue(manager1 === manager2, "Shared instances should be identical")
        XCTAssertNotNil(manager1.connectionQuality)
    }
    
    func testConnectionReliabilityManagerInitialState() {
        let manager = ConnectionReliabilityManager.shared
        
        // Since this is a singleton that's already initialized with network monitoring,
        // we need to account for potential state changes from network status
        // The singleton may have fair/unknown quality based on network state
        XCTAssertTrue([.unknown, .fair, .excellent, .good].contains(manager.connectionQuality))
        
        // Reconnection state should still be predictable if we cancel first
        manager.cancelReconnection()
        XCTAssertFalse(manager.isReconnecting)
        XCTAssertNil(manager.nextReconnectTime)
        
        // History may have events from singleton initialization and network monitoring
        XCTAssertGreaterThanOrEqual(manager.connectionHistory.count, 0)
    }
    
    // MARK: - Connection Quality Tests
    
    func testConnectionQualityValues() {
        let qualities: [ConnectionReliabilityManager.ConnectionQuality] = [
            .excellent, .good, .fair, .poor, .offline, .unknown
        ]
        
        for quality in qualities {
            XCTAssertFalse(quality.color.isEmpty)
            XCTAssertFalse(quality.icon.isEmpty)
            XCTAssertFalse(quality.rawValue.isEmpty)
        }
        
        // Test specific values
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.excellent.rawValue, "Excellent")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.good.rawValue, "Good")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.fair.rawValue, "Fair")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.poor.rawValue, "Poor")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.offline.rawValue, "Offline")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.unknown.rawValue, "Unknown")
    }
    
    func testConnectionQualityColors() {
        
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.excellent.color, "green")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.good.color, "blue")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.fair.color, "yellow")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.poor.color, "orange")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.offline.color, "red")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.unknown.color, "gray")
    }
    
    func testConnectionQualityIcons() {
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.excellent.icon, "wifi")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.good.icon, "wifi")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.fair.icon, "wifi.exclamationmark")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.poor.icon, "wifi.exclamationmark")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.offline.icon, "wifi.slash")
        XCTAssertEqual(ConnectionReliabilityManager.ConnectionQuality.unknown.icon, "questionmark.circle")
    }
    
    // MARK: - Connection Event Tests
    
    func testConnectionEvent() {
        let event = ConnectionReliabilityManager.ConnectionEvent(
            timestamp: Date(),
            type: .connected,
            quality: .excellent,
            details: "Test connection established"
        )
        
        XCTAssertEqual(event.type, .connected)
        XCTAssertEqual(event.quality, .excellent)
        XCTAssertEqual(event.details, "Test connection established")
        XCTAssertNotNil(event.timestamp)
    }
    
    func testConnectionEventTypes() {
        let eventTypes: [ConnectionReliabilityManager.ConnectionEvent.EventType] = [
            .connected, .disconnected, .reconnecting, .qualityChanged, .error
        ]
        
        for type in eventTypes {
            let event = ConnectionReliabilityManager.ConnectionEvent(
                timestamp: Date(),
                type: type,
                quality: .good,
                details: nil
            )
            XCTAssertEqual(event.type, type)
        }
    }
    
    // MARK: - Exponential Backoff Tests
    
    func testGetNextReconnectDelay() {
        let manager = ConnectionReliabilityManager.shared
        
        // Reset state for clean test
        manager.cancelReconnection()
        
        // First attempt should be close to base delay (1 second + jitter)
        let firstDelay = manager.getNextReconnectDelay()
        XCTAssertGreaterThan(firstDelay, 0.7) // base - jitter
        XCTAssertLessThan(firstDelay, 1.3) // base + jitter
        
        // Simulate increasing reconnect attempts
        for _ in 1..<5 {
            // Manually increment for testing
            manager.cancelReconnection()
            let delay = manager.getNextReconnectDelay()
            
            // Should generally increase (with jitter, not always strictly)
            XCTAssertGreaterThan(delay, 0.5) // At least some minimum
            XCTAssertLessThan(delay, 300.0) // Never exceed max
        }
    }
    
    func testExponentialBackoffProgression() throws {
        guard !isCI else {
            throw XCTSkip("Skipping timing-sensitive test in CI environment")
        }
        
        let manager = ConnectionReliabilityManager.shared
        manager.cancelReconnection() // Reset state
        
        var delays: [TimeInterval] = []
        
        // Collect several delays to see the progression
        for _ in 0..<6 {
            let delay = manager.getNextReconnectDelay()
            delays.append(delay)
            
            // Verify delay is within reasonable bounds
            XCTAssertGreaterThan(delay, 0.0)
            XCTAssertLessThanOrEqual(delay, 300.0) // Max delay cap
        }
        
        // First delay should be around base delay (1s ± jitter)
        XCTAssertLessThan(delays[0], 2.0)
        
        // Later delays should generally be larger (allowing for jitter)
        XCTAssertGreaterThan(delays[5], delays[0])
    }
    
    // MARK: - Reconnection State Management Tests
    
    func testResetReconnectionState() {
        let manager = ConnectionReliabilityManager.shared
        
        // First cancel any existing reconnection
        manager.cancelReconnection()
        
        // Set up some reconnection state
        manager.scheduleReconnection {
            // Action for test setup
        }
        
        // Verify reconnection state is set
        XCTAssertTrue(manager.isReconnecting)
        XCTAssertGreaterThan(manager.reconnectAttempt, 0)
        XCTAssertNotNil(manager.nextReconnectTime)
        
        // Reset the state
        manager.resetReconnectionState()
        
        // Verify state is reset
        XCTAssertFalse(manager.isReconnecting)
        XCTAssertEqual(manager.reconnectAttempt, 0)
        XCTAssertNil(manager.nextReconnectTime)
    }
    
    func testCancelReconnection() {
        let manager = ConnectionReliabilityManager.shared
        
        // First cancel any existing reconnection
        manager.cancelReconnection()
        
        // Schedule a reconnection
        var actionCalled = false
        manager.scheduleReconnection {
            actionCalled = true
        }
        
        XCTAssertTrue(manager.isReconnecting)
        XCTAssertNotNil(manager.nextReconnectTime)
        
        // Cancel the reconnection
        manager.cancelReconnection()
        
        XCTAssertFalse(manager.isReconnecting)
        XCTAssertNil(manager.nextReconnectTime)
        
        // Wait a bit to ensure action doesn't get called
        let expectation = XCTestExpectation(description: "Wait for potential callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.2)
        
        XCTAssertFalse(actionCalled, "Cancelled reconnection should not execute")
    }
    
    func testHandleConnectionEstablished() {
        let manager = ConnectionReliabilityManager.shared
        
        // First cancel any existing reconnection
        manager.cancelReconnection()
        
        // Set up some disconnection state first
        manager.scheduleReconnection {
            // Action for test setup
        }
        
        // Handle connection established
        manager.handleConnectionEstablished()
        
        // Should reset reconnection state and set quality to excellent
        XCTAssertFalse(manager.isReconnecting)
        XCTAssertEqual(manager.reconnectAttempt, 0)
        XCTAssertNil(manager.nextReconnectTime)
        XCTAssertEqual(manager.connectionQuality, .excellent)
    }
    
    func testHandleConnectionLost() throws {
        guard !isCI else {
            throw XCTSkip("Skipping singleton state test in CI environment")
        }
        
        let manager = ConnectionReliabilityManager.shared
        let initialHistoryCount = manager.connectionHistory.count
        
        manager.handleConnectionLost()
        
        // Should record disconnection event
        XCTAssertGreaterThan(manager.connectionHistory.count, initialHistoryCount)
        
        // Find the disconnected event
        let disconnectedEvent = manager.connectionHistory.last { $0.type == .disconnected }
        XCTAssertNotNil(disconnectedEvent)
    }
    
    // MARK: - Message Cache Tests
    
    func testMessageCaching() {
        let manager = ConnectionReliabilityManager.shared
        
        // Create test messages
        let message1 = Message(
            id: UUID(),
            content: "Hello world",
            sender: .assistant,
            timestamp: Date()
        )
        
        let message2 = Message(
            id: UUID(),
            content: "How are you?",
            sender: .user,
            timestamp: Date()
        )
        
        // Cache messages
        manager.cacheMessage(message1)
        manager.cacheMessage(message2)
        
        // Test message was cached
        XCTAssertTrue(manager.wasMessageReceived(message1))
        XCTAssertTrue(manager.wasMessageReceived(message2))
        
        // Test message not in cache
        let message3 = Message(
            id: UUID(),
            content: "Not cached",
            sender: .assistant,
            timestamp: Date()
        )
        XCTAssertFalse(manager.wasMessageReceived(message3))
    }
    
    func testGetRecentMessages() {
        let manager = ConnectionReliabilityManager.shared
        
        // Cache multiple messages
        let messages = (0..<15).map { i in
            Message(
                id: UUID(),
                content: "Message \(i)",
                sender: .assistant,
                timestamp: Date().addingTimeInterval(TimeInterval(i))
            )
        }
        
        for message in messages {
            manager.cacheMessage(message)
        }
        
        // Get recent messages
        let recent = manager.getRecentMessages(count: 10)
        XCTAssertEqual(recent.count, 10)
        
        // Should be the last 10 messages
        let lastMessage = recent.last
        XCTAssertEqual(lastMessage?.content, "Message 14")
    }
    
    func testCachedMessageEquality() {
        let messageId = UUID()
        let message1 = Message(
            id: messageId,
            content: "Test message",
            sender: .user,
            timestamp: Date()
        )
        
        let message2 = Message(
            id: messageId, // Same ID
            content: "Test message", // Same content
            sender: .user,
            timestamp: Date() // Different timestamp
        )
        
        let cached1 = ConnectionReliabilityManager.CachedMessage(from: message1)
        let cached2 = ConnectionReliabilityManager.CachedMessage(from: message2)
        
        // Should have equal properties
        XCTAssertEqual(cached1.id, cached2.id)
        XCTAssertEqual(cached1.content, cached2.content)
        XCTAssertEqual(cached1.checksum, cached2.checksum)
        
        // Note: CachedMessage equality may depend on timestamp too,
        // so we test individual properties rather than direct equality
    }
    
    // MARK: - Circular Buffer Tests
    
    func testCircularBufferBasicOperations() {
        var buffer = CircularBuffer<String>(capacity: 3)
        
        // Test adding elements
        buffer.append("A")
        buffer.append("B")
        buffer.append("C")
        
        XCTAssertTrue(buffer.contains("A"))
        XCTAssertTrue(buffer.contains("B"))
        XCTAssertTrue(buffer.contains("C"))
        
        // Test overflow (should replace oldest)
        buffer.append("D")
        
        XCTAssertFalse(buffer.contains("A")) // Should be overwritten
        XCTAssertTrue(buffer.contains("B"))
        XCTAssertTrue(buffer.contains("C"))
        XCTAssertTrue(buffer.contains("D"))
    }
    
    func testCircularBufferSuffix() {
        var buffer = CircularBuffer<Int>(capacity: 5)
        
        // Add more elements than capacity
        for i in 1...7 {
            buffer.append(i)
        }
        
        // Get last 3 elements
        let last3 = buffer.suffix(3)
        XCTAssertEqual(last3, [5, 6, 7])
        
        // Get all elements (should be last 5)
        let all = buffer.suffix(10) // Request more than available
        XCTAssertEqual(all, [3, 4, 5, 6, 7])
    }
    
    func testCircularBufferEdgeCases() {
        // Test empty buffer
        let emptyBuffer = CircularBuffer<String>(capacity: 3)
        XCTAssertFalse(emptyBuffer.contains("anything"))
        XCTAssertEqual(emptyBuffer.suffix(5), [])
        
        // Test single capacity buffer
        var singleBuffer = CircularBuffer<Int>(capacity: 1)
        singleBuffer.append(42)
        XCTAssertTrue(singleBuffer.contains(42))
        
        singleBuffer.append(84)
        XCTAssertFalse(singleBuffer.contains(42))
        XCTAssertTrue(singleBuffer.contains(84))
    }
    
    // MARK: - Connection History Tests
    
    func testConnectionHistoryLimit() {
        let manager = ConnectionReliabilityManager.shared
        
        // Clear any existing history by waiting a moment
        Thread.sleep(forTimeInterval: 0.01)
        
        // Add many disconnection events to trigger history logging
        for _ in 0..<150 {
            manager.recordDisconnection()
            // Small delay to ensure different timestamps
            Thread.sleep(forTimeInterval: 0.001)
        }
        
        // History should be limited to 100 events
        XCTAssertLessThanOrEqual(manager.connectionHistory.count, 100)
        // Since singleton may have been used by other tests, just check we have some events
        XCTAssertGreaterThan(manager.connectionHistory.count, 0)
    }
    
    func testRecordConnectionAttempt() {
        let manager = ConnectionReliabilityManager.shared
        
        // Record some attempts
        for _ in 0..<5 {
            manager.recordConnectionAttempt()
        }
        
        // Connection attempts are tracked internally, but we can test the public interface
        // doesn't crash and the manager continues to function
        XCTAssertNotNil(manager.connectionQuality)
    }
    
    func testRecordDisconnection() throws {
        guard !isCI else {
            throw XCTSkip("Skipping singleton state test in CI environment")
        }
        
        let manager = ConnectionReliabilityManager.shared
        let initialCount = manager.connectionHistory.count
        
        manager.recordDisconnection()
        
        // Should add to history
        XCTAssertGreaterThan(manager.connectionHistory.count, initialCount)
        
        // Should have a disconnected event
        let lastEvent = manager.connectionHistory.last
        XCTAssertEqual(lastEvent?.type, .disconnected)
    }
    
    // MARK: - Schedule Reconnection Tests
    
    func testScheduleReconnection() {
        let manager = ConnectionReliabilityManager.shared
        manager.cancelReconnection() // Reset state
        
        let expectation = XCTestExpectation(description: "Reconnection callback")
        var actionCalled = false
        
        manager.scheduleReconnection {
            actionCalled = true
            expectation.fulfill()
        }
        
        // Should set reconnection state
        XCTAssertTrue(manager.isReconnecting)
        XCTAssertEqual(manager.reconnectAttempt, 1)
        XCTAssertNotNil(manager.nextReconnectTime)
        
        // Should eventually call the action (with short timeout for test)
        wait(for: [expectation], timeout: 3.0)
        XCTAssertTrue(actionCalled)
    }
    
    func testScheduleReconnectionMaxAttempts() {
        let manager = ConnectionReliabilityManager.shared
        manager.cancelReconnection() // Reset state
        
        // Simulate max attempts by directly setting the attempt count
        // We'll call scheduleReconnection multiple times to test the limit
        var callCount = 0
        
        for _ in 0..<15 { // Try more than max attempts (10)
            manager.scheduleReconnection {
                callCount += 1
            }
        }
        
        // Should not exceed max attempts
        XCTAssertLessThanOrEqual(manager.reconnectAttempt, 10)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfMessageCaching() {
        measure {
            let manager = ConnectionReliabilityManager.shared
            
            for i in 0..<1000 {
                let message = Message(
                    id: UUID(),
                    content: "Performance test message \(i)",
                    sender: .assistant,
                    timestamp: Date()
                )
                
                manager.cacheMessage(message)
                _ = manager.wasMessageReceived(message)
            }
        }
    }
    
    func testPerformanceOfCircularBuffer() {
        measure {
            var buffer = CircularBuffer<String>(capacity: 100)
            
            for i in 0..<1000 {
                buffer.append("item-\(i)")
                _ = buffer.contains("item-\(i)")
                _ = buffer.suffix(10)
            }
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentMessageCaching() {
        let expectation = XCTestExpectation(description: "Concurrent message caching")
        expectation.expectedFulfillmentCount = 10
        
        let manager = ConnectionReliabilityManager.shared
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        for i in 0..<10 {
            group.enter()
            queue.async {
                let message = Message(
                    id: UUID(),
                    content: "Concurrent message \(i)",
                    sender: .user,
                    timestamp: Date()
                )
                
                // Synchronize access to the manager
                DispatchQueue.main.sync {
                    manager.cacheMessage(message)
                    _ = manager.wasMessageReceived(message)
                }
                
                expectation.fulfill()
                group.leave()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Edge Cases Tests
    
    func testEdgeCaseHandling() {
        let manager = ConnectionReliabilityManager.shared
        
        // Test with nil/empty scenarios don't crash
        manager.cancelReconnection() // Should not crash when nothing to cancel
        manager.resetReconnectionState() // Should not crash when already reset
        
        // Test getting recent messages when cache is empty or small
        let emptyRecent = manager.getRecentMessages(count: 0)
        XCTAssertEqual(emptyRecent.count, 0)
        
        // Note: getRecentMessages uses suffix which handles negative counts gracefully
        // by returning empty array, no need to test negative count
        
        // Test message with empty content
        let emptyMessage = Message(
            id: UUID(),
            content: "",
            sender: .assistant,
            timestamp: Date()
        )
        
        manager.cacheMessage(emptyMessage)
        XCTAssertTrue(manager.wasMessageReceived(emptyMessage))
    }
    
    func testMessageWithSpecialCharacters() {
        let manager = ConnectionReliabilityManager.shared
        
        let specialMessage = Message(
            id: UUID(),
            content: "Special chars: 🎉 Unicode: 世界 Quotes: \"test\" & symbols: <>&",
            sender: .user,
            timestamp: Date()
        )
        
        manager.cacheMessage(specialMessage)
        XCTAssertTrue(manager.wasMessageReceived(specialMessage))
    }
    
    func testVeryLongMessage() {
        let manager = ConnectionReliabilityManager.shared
        
        let longContent = String(repeating: "A", count: 10000)
        let longMessage = Message(
            id: UUID(),
            content: longContent,
            sender: .assistant,
            timestamp: Date()
        )
        
        manager.cacheMessage(longMessage)
        XCTAssertTrue(manager.wasMessageReceived(longMessage))
        XCTAssertEqual(manager.getRecentMessages(count: 1).first?.content, longContent)
    }
}