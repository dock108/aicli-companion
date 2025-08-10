import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessageQueueManagerTests: XCTestCase {
    
    var queueManager: MessageQueueManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        queueManager = MessageQueueManager.shared
        cancellables = Set<AnyCancellable>()
        
        // Clear any existing queue state
        queueManager.clearAllQueues()
    }
    
    override func tearDown() {
        queueManager.clearAllQueues()
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() throws {
        XCTAssertEqual(queueManager.queuedMessageCount, 0)
        XCTAssertFalse(queueManager.isReceivingQueued)
        XCTAssertNil(queueManager.oldestQueuedTimestamp)
        XCTAssertEqual(queueManager.queuedMessages.count, 0)
    }
    
    // MARK: - Message Queuing Tests
    
    func testTrackQueuedMessage() throws {
        let messageId = "test-message-123"
        let sessionId = "test-session-456"
        let priority = 1
        
        queueManager.trackQueuedMessage(
            messageId: messageId,
            sessionId: sessionId,
            priority: priority
        )
        
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        XCTAssertEqual(queueManager.queuedMessages.count, 1)
        XCTAssertNotNil(queueManager.oldestQueuedTimestamp)
        
        let queuedMessage = queueManager.queuedMessages[0]
        XCTAssertEqual(queuedMessage.messageId, messageId)
        XCTAssertEqual(queuedMessage.sessionId, sessionId)
        XCTAssertEqual(queuedMessage.priority, priority)
        XCTAssertNil(queuedMessage.deliveredAt)
    }
    
    func testTrackMultipleQueuedMessages() throws {
        let messages = [
            ("msg-1", "session-1", 0),
            ("msg-2", "session-1", 1),
            ("msg-3", "session-2", 0)
        ]
        
        for (messageId, sessionId, priority) in messages {
            queueManager.trackQueuedMessage(
                messageId: messageId,
                sessionId: sessionId,
                priority: priority
            )
        }
        
        XCTAssertEqual(queueManager.queuedMessageCount, 3)
        XCTAssertEqual(queueManager.queuedMessages.count, 3)
        
        // Verify all messages are tracked
        let messageIds = Set(queueManager.queuedMessages.map { $0.messageId })
        XCTAssertEqual(messageIds, Set(["msg-1", "msg-2", "msg-3"]))
    }
    
    func testQueuedMessageTimestamp() throws {
        let beforeQueue = Date()
        
        queueManager.trackQueuedMessage(
            messageId: "timestamp-test",
            sessionId: "session-test",
            priority: 0
        )
        
        let afterQueue = Date()
        
        XCTAssertEqual(queueManager.queuedMessages.count, 1)
        let queuedMessage = queueManager.queuedMessages[0]
        
        XCTAssertTrue(queuedMessage.queuedAt >= beforeQueue)
        XCTAssertTrue(queuedMessage.queuedAt <= afterQueue)
        XCTAssertEqual(queueManager.oldestQueuedTimestamp, queuedMessage.queuedAt)
    }
    
    // MARK: - Message Delivery Tests
    
    func testMarkMessageDelivered() throws {
        let messageId = "delivery-test-123"
        let sessionId = "session-delivery"
        
        // First queue a message
        queueManager.trackQueuedMessage(
            messageId: messageId,
            sessionId: sessionId,
            priority: 0
        )
        
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        XCTAssertNil(queueManager.queuedMessages[0].deliveredAt)
        
        // Mark as delivered
        queueManager.markMessageDelivered(messageId: messageId)
        
        // Should still be in queue but marked as delivered
        XCTAssertEqual(queueManager.queuedMessages.count, 1)
        XCTAssertNotNil(queueManager.queuedMessages[0].deliveredAt)
        XCTAssertNotNil(queueManager.queuedMessages[0].deliveryDelay)
    }
    
    func testMarkNonExistentMessageDelivered() throws {
        // Should not crash or cause issues
        queueManager.markMessageDelivered(messageId: "non-existent-message")
        
        XCTAssertEqual(queueManager.queuedMessageCount, 0)
        XCTAssertEqual(queueManager.queuedMessages.count, 0)
    }
    
    func testDeliveryDelayCalculation() throws {
        let messageId = "delay-test-message"
        let sessionId = "delay-test-session"
        
        let beforeQueue = Date()
        queueManager.trackQueuedMessage(
            messageId: messageId,
            sessionId: sessionId,
            priority: 0
        )
        
        // Wait a small amount to create measurable delay
        Thread.sleep(forTimeInterval: 0.1)
        
        queueManager.markMessageDelivered(messageId: messageId)
        
        let queuedMessage = queueManager.queuedMessages[0]
        guard let deliveryDelay = queuedMessage.deliveryDelay else {
            XCTFail("Delivery delay should be calculated")
            return
        }
        
        XCTAssertGreaterThanOrEqual(deliveryDelay, 0.1)
        XCTAssertLessThan(deliveryDelay, 1.0) // Should be reasonable
    }
    
    // MARK: - Session-Specific Queue Info Tests
    
    func testGetQueueInfoForSession() throws {
        // Add messages for different sessions
        queueManager.trackQueuedMessage(messageId: "msg-1", sessionId: "session-1", priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-2", sessionId: "session-1", priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-3", sessionId: "session-2", priority: 0)
        
        let session1Info = queueManager.getQueueInfo(for: "session-1")
        let session2Info = queueManager.getQueueInfo(for: "session-2")
        let emptySessionInfo = queueManager.getQueueInfo(for: "empty-session")
        
        XCTAssertEqual(session1Info.count, 2)
        XCTAssertNotNil(session1Info.oldestTimestamp)
        
        XCTAssertEqual(session2Info.count, 1)
        XCTAssertNotNil(session2Info.oldestTimestamp)
        
        XCTAssertEqual(emptySessionInfo.count, 0)
        XCTAssertNil(emptySessionInfo.oldestTimestamp)
    }
    
    func testGetQueueInfoExcludesDeliveredMessages() throws {
        let sessionId = "delivered-test-session"
        
        queueManager.trackQueuedMessage(messageId: "msg-1", sessionId: sessionId, priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-2", sessionId: sessionId, priority: 0)
        
        // Initially should have 2 messages
        let initialInfo = queueManager.getQueueInfo(for: sessionId)
        XCTAssertEqual(initialInfo.count, 2)
        
        // Mark one as delivered
        queueManager.markMessageDelivered(messageId: "msg-1")
        
        // Should now report 1 message (excluding delivered)
        let afterDeliveryInfo = queueManager.getQueueInfo(for: sessionId)
        XCTAssertEqual(afterDeliveryInfo.count, 1)
    }
    
    func testOldestTimestampCalculation() throws {
        let sessionId = "timestamp-test-session"
        
        // Add first message
        queueManager.trackQueuedMessage(messageId: "msg-1", sessionId: sessionId, priority: 0)
        let firstTimestamp = queueManager.oldestQueuedTimestamp
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // Add second message
        queueManager.trackQueuedMessage(messageId: "msg-2", sessionId: sessionId, priority: 0)
        let secondTimestamp = queueManager.oldestQueuedTimestamp
        
        // Oldest timestamp should remain the same (first message)
        XCTAssertEqual(firstTimestamp, secondTimestamp)
        
        // Verify session-specific oldest timestamp
        let sessionInfo = queueManager.getQueueInfo(for: sessionId)
        XCTAssertEqual(sessionInfo.oldestTimestamp, firstTimestamp)
    }
    
    // MARK: - Queue Clearing Tests
    
    func testClearQueueForSession() throws {
        // Add messages for different sessions
        queueManager.trackQueuedMessage(messageId: "msg-1", sessionId: "session-1", priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-2", sessionId: "session-1", priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-3", sessionId: "session-2", priority: 0)
        
        XCTAssertEqual(queueManager.queuedMessageCount, 3)
        
        // Clear queue for session-1
        queueManager.clearQueue(for: "session-1")
        
        XCTAssertEqual(queueManager.queuedMessageCount, 1) // Only session-2 message remains
        
        let remainingMessages = queueManager.queuedMessages
        XCTAssertEqual(remainingMessages.count, 1)
        XCTAssertEqual(remainingMessages[0].messageId, "msg-3")
        XCTAssertEqual(remainingMessages[0].sessionId, "session-2")
    }
    
    func testClearAllQueues() throws {
        // Add multiple messages
        queueManager.trackQueuedMessage(messageId: "msg-1", sessionId: "session-1", priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-2", sessionId: "session-2", priority: 0)
        queueManager.trackQueuedMessage(messageId: "msg-3", sessionId: "session-3", priority: 0)
        
        XCTAssertEqual(queueManager.queuedMessageCount, 3)
        
        // Clear all
        queueManager.clearAllQueues()
        
        XCTAssertEqual(queueManager.queuedMessageCount, 0)
        XCTAssertEqual(queueManager.queuedMessages.count, 0)
        XCTAssertNil(queueManager.oldestQueuedTimestamp)
        XCTAssertFalse(queueManager.isReceivingQueued)
    }
    
    // MARK: - Published Properties Tests
    
    func testQueuedMessageCountIsPublished() throws {
        let expectation = XCTestExpectation(description: "Queued message count should be published")
        var countChanges: [Int] = []
        
        queueManager.$queuedMessageCount
            .sink { count in
                countChanges.append(count)
                if countChanges.count >= 3 { // 0 -> 1 -> 2
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        queueManager.trackQueuedMessage(messageId: "count-test-1", sessionId: "session", priority: 0)
        queueManager.trackQueuedMessage(messageId: "count-test-2", sessionId: "session", priority: 0)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(countChanges[0], 0) // Initial
        XCTAssertEqual(countChanges[1], 1) // After first message
        XCTAssertEqual(countChanges[2], 2) // After second message
    }
    
    func testIsReceivingQueuedIsPublished() throws {
        let expectation = XCTestExpectation(description: "isReceivingQueued should be published")
        var receivingStates: [Bool] = []
        
        queueManager.$isReceivingQueued
            .sink { isReceiving in
                receivingStates.append(isReceiving)
                if receivingStates.count >= 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 0.5)
        
        XCTAssertEqual(receivingStates[0], false) // Initial state
    }
    
    func testQueuedMessagesIsPublished() throws {
        let expectation = XCTestExpectation(description: "Queued messages should be published")
        var messageArrayChanges: [[MessageQueueManager.QueuedMessageInfo]] = []
        
        queueManager.$queuedMessages
            .sink { messages in
                messageArrayChanges.append(messages)
                if messageArrayChanges.count >= 2 { // empty -> 1 message
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        queueManager.trackQueuedMessage(messageId: "published-test", sessionId: "session", priority: 0)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(messageArrayChanges[0].count, 0) // Initial empty
        XCTAssertEqual(messageArrayChanges[1].count, 1) // After adding message
    }
    
    // MARK: - Priority Handling Tests
    
    func testMessagePriority() throws {
        queueManager.trackQueuedMessage(messageId: "low-priority", sessionId: "session", priority: 0)
        queueManager.trackQueuedMessage(messageId: "high-priority", sessionId: "session", priority: 1)
        queueManager.trackQueuedMessage(messageId: "higher-priority", sessionId: "session", priority: 2)
        
        XCTAssertEqual(queueManager.queuedMessages.count, 3)
        
        // All messages should be tracked regardless of priority
        let priorities = queueManager.queuedMessages.map { $0.priority }
        XCTAssertTrue(priorities.contains(0))
        XCTAssertTrue(priorities.contains(1))
        XCTAssertTrue(priorities.contains(2))
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentQueueOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent operations should complete safely")
        expectation.expectedFulfillmentCount = 10
        
        let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
        
        // Perform multiple operations concurrently
        for i in 0..<10 {
            concurrentQueue.async {
                self.queueManager.trackQueuedMessage(
                    messageId: "concurrent-msg-\(i)",
                    sessionId: "concurrent-session",
                    priority: i % 3
                )
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // All messages should be tracked safely
        XCTAssertEqual(queueManager.queuedMessageCount, 10)
        XCTAssertEqual(queueManager.queuedMessages.count, 10)
        
        // Verify all message IDs are unique
        let messageIds = Set(queueManager.queuedMessages.map { $0.messageId })
        XCTAssertEqual(messageIds.count, 10)
    }
    
    func testConcurrentDeliveryMarking() throws {
        // First add messages
        for i in 0..<5 {
            queueManager.trackQueuedMessage(
                messageId: "delivery-concurrent-\(i)",
                sessionId: "session",
                priority: 0
            )
        }
        
        let expectation = XCTestExpectation(description: "Concurrent delivery marking should work")
        expectation.expectedFulfillmentCount = 5
        
        let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
        
        // Mark all as delivered concurrently
        for i in 0..<5 {
            concurrentQueue.async {
                self.queueManager.markMessageDelivered(messageId: "delivery-concurrent-\(i)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // All messages should be marked as delivered
        let deliveredCount = queueManager.queuedMessages.filter { $0.deliveredAt != nil }.count
        XCTAssertEqual(deliveredCount, 5)
    }
    
    // MARK: - Performance Tests
    
    func testQueuePerformanceWithManyMessages() throws {
        measure {
            for i in 0..<1000 {
                queueManager.trackQueuedMessage(
                    messageId: "perf-msg-\(i)",
                    sessionId: "perf-session-\(i % 10)", // 10 different sessions
                    priority: i % 3
                )
            }
            
            // Test some operations on the large queue
            _ = queueManager.getQueueInfo(for: "perf-session-0")
            queueManager.clearQueue(for: "perf-session-1")
        }
    }
    
    func testDeliveryPerformance() throws {
        // Add many messages first
        let messageIds = (0..<500).map { "delivery-perf-\($0)" }
        for messageId in messageIds {
            queueManager.trackQueuedMessage(
                messageId: messageId,
                sessionId: "perf-session",
                priority: 0
            )
        }
        
        measure {
            // Mark all as delivered
            for messageId in messageIds {
                queueManager.markMessageDelivered(messageId: messageId)
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testDuplicateMessageIds() throws {
        let messageId = "duplicate-test"
        let sessionId = "duplicate-session"
        
        queueManager.trackQueuedMessage(messageId: messageId, sessionId: sessionId, priority: 0)
        queueManager.trackQueuedMessage(messageId: messageId, sessionId: sessionId, priority: 1)
        
        // Both should be tracked (even with duplicate IDs)
        XCTAssertEqual(queueManager.queuedMessageCount, 2)
        
        // Mark one as delivered - should only affect first match
        queueManager.markMessageDelivered(messageId: messageId)
        
        let deliveredCount = queueManager.queuedMessages.filter { $0.deliveredAt != nil }.count
        XCTAssertEqual(deliveredCount, 1)
    }
    
    func testEmptyStringIds() throws {
        queueManager.trackQueuedMessage(messageId: "", sessionId: "", priority: 0)
        
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        XCTAssertEqual(queueManager.queuedMessages[0].messageId, "")
        XCTAssertEqual(queueManager.queuedMessages[0].sessionId, "")
    }
    
    func testNegativePriority() throws {
        queueManager.trackQueuedMessage(
            messageId: "negative-priority-test",
            sessionId: "session",
            priority: -1
        )
        
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        XCTAssertEqual(queueManager.queuedMessages[0].priority, -1)
    }
}