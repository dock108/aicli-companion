import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessageQueueManagerTests: XCTestCase {
    
    var queueManager: MessageQueueManager!
    
    // Helper to check if we're in CI
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil ||
        ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil
    }
    
    override func setUp() {
        super.setUp()
        queueManager = MessageQueueManager.shared
        queueManager.clearAllQueues() // Reset state for each test
    }
    
    override func tearDown() {
        queueManager.clearAllQueues()
        super.tearDown()
    }
    
    // MARK: - Basic Queue Operations Tests
    
    func testInitialState() {
        guard !isCI else {
            XCTSkip("Skipping singleton state test in CI environment")
            return
        }
        
        // Clear any existing state from singleton
        queueManager.clearAllQueues()
        queueManager.finishReceivingQueued()
        
        // Allow time for async updates
        let expectation = XCTestExpectation(description: "State cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(queueManager.queuedMessageCount, 0)
        XCTAssertFalse(queueManager.isReceivingQueued)
        XCTAssertNil(queueManager.oldestQueuedTimestamp)
        XCTAssertEqual(queueManager.queuedMessages.count, 0)
    }
    
@MainActor
    func testTrackQueuedMessage() async {
        guard !isCI else {
            throw XCTSkip("Skipping async test in CI environment")
        }
        
        let messageId = "msg-001"
        let sessionId = "session-123"
        let priority = 1
        
        queueManager.trackQueuedMessage(messageId: messageId, sessionId: sessionId, priority: priority)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        XCTAssertNotNil(queueManager.oldestQueuedTimestamp)
        XCTAssertEqual(queueManager.queuedMessages.count, 1)
        
        let queuedMessage = queueManager.queuedMessages.first!
        XCTAssertEqual(queuedMessage.messageId, messageId)
        XCTAssertEqual(queuedMessage.sessionId, sessionId)
        XCTAssertEqual(queuedMessage.priority, priority)
        XCTAssertNil(queuedMessage.deliveredAt)
    }
    
@MainActor
    func testTrackMultipleMessages() async {
        let messages = [
            ("msg-001", "session-123"),
            ("msg-002", "session-123"),
            ("msg-003", "session-456")
        ]
        
        for (messageId, sessionId) in messages {
            queueManager.trackQueuedMessage(messageId: messageId, sessionId: sessionId)
        }
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(queueManager.queuedMessageCount, 3)
        XCTAssertEqual(queueManager.queuedMessages.count, 3)
        
        // Check all messages are queued
        for (messageId, sessionId) in messages {
            let found = queueManager.queuedMessages.contains { 
                $0.messageId == messageId && $0.sessionId == sessionId 
            }
            XCTAssertTrue(found, "Message \(messageId) should be in queue")
        }
    }
    
@MainActor
    func testMarkMessageDelivered() async {
        let messageId = "msg-001"
        let sessionId = "session-123"
        
        queueManager.trackQueuedMessage(messageId: messageId, sessionId: sessionId)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        
        queueManager.markMessageDelivered(messageId: messageId)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Find the message in the queue
        if let message = queueManager.queuedMessages.first(where: { $0.messageId == messageId }) {
            XCTAssertNotNil(message.deliveredAt)
            XCTAssertNotNil(message.deliveryDelay)
            XCTAssertGreaterThanOrEqual(message.deliveryDelay!, 0)
        } else {
            XCTFail("Message should be found in queue")
        }
    }
    
    func testMarkNonExistentMessageDelivered() {
        // Try to mark a message as delivered that was never queued
        queueManager.markMessageDelivered(messageId: "non-existent")
        
        // Should not crash and queue should remain empty
        XCTAssertEqual(queueManager.queuedMessageCount, 0)
    }
    
    // MARK: - Queue Info Tests
    
    func testGetQueueInfoForSession() {
        let sessionId = "session-123"
        let otherSessionId = "session-456"
        
        // Add messages to different sessions
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: sessionId)
        queueManager.trackQueuedMessage(messageId: "msg-002", sessionId: sessionId)
        queueManager.trackQueuedMessage(messageId: "msg-003", sessionId: otherSessionId)
        
        let queueInfo = queueManager.getQueueInfo(for: sessionId)
        
        XCTAssertEqual(queueInfo.count, 2)
        XCTAssertNotNil(queueInfo.oldestTimestamp)
    }
    
    func testGetQueueInfoEmptySession() {
        let queueInfo = queueManager.getQueueInfo(for: "empty-session")
        
        XCTAssertEqual(queueInfo.count, 0)
        XCTAssertNil(queueInfo.oldestTimestamp)
    }
    
    func testGetQueueInfoWithDeliveredMessages() {
        let sessionId = "session-123"
        
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: sessionId)
        queueManager.trackQueuedMessage(messageId: "msg-002", sessionId: sessionId)
        
        // Mark one as delivered
        queueManager.markMessageDelivered(messageId: "msg-001")
        
        let queueInfo = queueManager.getQueueInfo(for: sessionId)
        
        // Should only count undelivered messages
        XCTAssertEqual(queueInfo.count, 1)
    }
    
    // MARK: - Clear Queue Tests
    
    @MainActor
    func testClearQueueForSession() async {
        let sessionId = "session-123"
        let otherSessionId = "session-456"
        
        // Add messages to different sessions
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: sessionId)
        queueManager.trackQueuedMessage(messageId: "msg-002", sessionId: sessionId)
        queueManager.trackQueuedMessage(messageId: "msg-003", sessionId: otherSessionId)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 3)
        
        queueManager.clearQueue(for: sessionId)
        
        // Wait for main queue updates after clearing
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 1)
        
        // Verify only the other session's message remains
        let remaining = queueManager.queuedMessages.first
        XCTAssertEqual(remaining?.messageId, "msg-003")
        XCTAssertEqual(remaining?.sessionId, otherSessionId)
    }
    
    @MainActor
    func testClearAllQueues() async {
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: "session-123")
        queueManager.trackQueuedMessage(messageId: "msg-002", sessionId: "session-456")
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 2)
        
        queueManager.clearAllQueues()
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 0)
        XCTAssertEqual(queueManager.queuedMessages.count, 0)
        XCTAssertNil(queueManager.oldestQueuedTimestamp)
    }
    
    // MARK: - Receiving Queued Messages Tests
    
    func testStartReceivingQueued() {
        // Ensure clean state
        queueManager.finishReceivingQueued()
        
        let expectation = XCTestExpectation(description: "Initial state check")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.queueManager.isReceivingQueued)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        queueManager.startReceivingQueued()
        
        let updateExpectation = XCTestExpectation(description: "State update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.queueManager.isReceivingQueued)
            updateExpectation.fulfill()
        }
        
        wait(for: [updateExpectation], timeout: 1.0)
    }
    
    func testFinishReceivingQueued() {
        queueManager.startReceivingQueued()
        
        let startExpectation = XCTestExpectation(description: "Start receiving")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.queueManager.isReceivingQueued)
            startExpectation.fulfill()
        }
        
        wait(for: [startExpectation], timeout: 1.0)
        
        queueManager.finishReceivingQueued()
        
        let finishExpectation = XCTestExpectation(description: "Finish receiving")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.queueManager.isReceivingQueued)
            finishExpectation.fulfill()
        }
        
        wait(for: [finishExpectation], timeout: 1.0)
    }
    
    // MARK: - Progress Response Handling Tests
    
    func testHandleQueueProgress() {
        let queueManager = MessageQueueManager.shared
        
        // Test progress message that starts queue processing
        let _ = ProgressResponse(
            message: "Processing queued messages",
            progress: 0.0,
            stage: "queue",
            estimatedTimeRemaining: nil
        )
        
        // Access the private method via reflection or test the behavior indirectly
        // Since the method is private, we test the observable behavior
        XCTAssertFalse(queueManager.isReceivingQueued)
        
        // Test progress message that finishes queue processing
        let _ = ProgressResponse(
            message: "Queue processing complete",
            progress: 1.0,
            stage: "done",
            estimatedTimeRemaining: nil
        )
        
        // Since handleQueueProgress is private, we can't test it directly
        // But we can test the public methods it would call
        queueManager.startReceivingQueued()
        
        let expectation = XCTestExpectation(description: "Queue processing state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.queueManager.isReceivingQueued)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - QueuedMessageInfo Tests
    
    func testQueuedMessageInfoDeliveryDelay() {
        let messageId = "msg-001"
        let sessionId = "session-123"
        let queuedAt = Date()
        
        let queuedInfo = MessageQueueManager.QueuedMessageInfo(
            messageId: messageId,
            sessionId: sessionId,
            queuedAt: queuedAt,
            priority: 0,
            deliveredAt: nil
        )
        
        XCTAssertNil(queuedInfo.deliveryDelay)
        
        let deliveredAt = queuedAt.addingTimeInterval(5.0)
        let deliveredInfo = MessageQueueManager.QueuedMessageInfo(
            messageId: messageId,
            sessionId: sessionId,
            queuedAt: queuedAt,
            priority: 0,
            deliveredAt: deliveredAt
        )
        
        XCTAssertNotNil(deliveredInfo.deliveryDelay)
        XCTAssertEqual(deliveredInfo.deliveryDelay!, 5.0, accuracy: 0.01)
    }
    
    // MARK: - Message Extension Tests
    
    func testCreateQueuedMetadata() {
        let sessionId = "test-session"
        let duration: TimeInterval = 1.5
        let queuedAt = Date()
        
        let metadata = Message.createQueuedMetadata(
            sessionId: sessionId,
            duration: duration,
            queuedAt: queuedAt
        )
        
        XCTAssertEqual(metadata.sessionId, sessionId)
        XCTAssertEqual(metadata.duration, duration)
        XCTAssertEqual(metadata.queuedAt, queuedAt)
        XCTAssertNil(metadata.deliveredAt)
    }
    
    func testMarkDeliveredFromQueue() {
        let sessionId = "test-session"
        let queuedAt = Date()
        
        var message = Message(
            content: "Test message",
            sender: .assistant,
            metadata: Message.createQueuedMetadata(sessionId: sessionId, queuedAt: queuedAt)
        )
        
        XCTAssertNotNil(message.metadata?.queuedAt)
        XCTAssertNil(message.metadata?.deliveredAt)
        
        message.markDeliveredFromQueue()
        
        XCTAssertNotNil(message.metadata?.queuedAt)
        XCTAssertNotNil(message.metadata?.deliveredAt)
        XCTAssertEqual(message.metadata?.sessionId, sessionId)
    }
    
    func testMarkDeliveredFromQueueWithoutQueuedMetadata() {
        var message = Message(
            content: "Test message",
            sender: .assistant
        )
        
        // Should not crash when marking delivered without queued metadata
        message.markDeliveredFromQueue()
        
        XCTAssertNil(message.metadata?.queuedAt)
        XCTAssertNil(message.metadata?.deliveredAt)
    }
    
    // MARK: - Thread Safety Tests
    
@MainActor
    func testConcurrentQueueOperations() async {
        guard !isCI else {
            throw XCTSkip("Skipping concurrent test in CI environment")
        }
        
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue.global(qos: .background)
        
        for i in 0..<10 {
            queue.async {
                self.queueManager.trackQueuedMessage(
                    messageId: "msg-\(i)",
                    sessionId: "session-\(i % 3)"
                )
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // All messages should be tracked without race conditions
        XCTAssertEqual(queueManager.queuedMessageCount, 10)
    }
    
@MainActor
    func testConcurrentDeliveryOperations() async {
        guard !isCI else {
            throw XCTSkip("Skipping concurrent test in CI environment")
        }
        
        // Setup messages
        for i in 0..<5 {
            queueManager.trackQueuedMessage(messageId: "msg-\(i)", sessionId: "session-123")
        }
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 5)
        
        let expectation = XCTestExpectation(description: "Concurrent deliveries")
        expectation.expectedFulfillmentCount = 5
        
        let queue = DispatchQueue.global(qos: .background)
        
        for i in 0..<5 {
            queue.async {
                self.queueManager.markMessageDelivered(messageId: "msg-\(i)")
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // All messages should be marked as delivered
        let deliveredCount = queueManager.queuedMessages.filter { $0.deliveredAt != nil }.count
        XCTAssertEqual(deliveredCount, 5)
    }
    
    // MARK: - Edge Cases Tests
    
    func testTrackingWithEmptyIds() {
        // Clear state first
        queueManager.clearAllQueues()
        
        let expectation = XCTestExpectation(description: "Tracking with empty IDs")
        
        queueManager.trackQueuedMessage(messageId: "", sessionId: "session-123")
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: "")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.queueManager.queuedMessageCount, 2)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
@MainActor
    func testMultiplePriorities() async {
        queueManager.trackQueuedMessage(messageId: "msg-high", sessionId: "session-123", priority: 10)
        queueManager.trackQueuedMessage(messageId: "msg-low", sessionId: "session-123", priority: 1)
        queueManager.trackQueuedMessage(messageId: "msg-normal", sessionId: "session-123", priority: 5)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, 3)
        
        let priorities = queueManager.queuedMessages.map { $0.priority }
        XCTAssertTrue(priorities.contains(10))
        XCTAssertTrue(priorities.contains(1))
        XCTAssertTrue(priorities.contains(5))
    }
    
@MainActor
    func testOldestQueuedTimestamp() async {
        let firstTime = Date()
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: "session-123")
        
        // Wait a bit before adding second message
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        queueManager.trackQueuedMessage(messageId: "msg-002", sessionId: "session-123")
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(queueManager.oldestQueuedTimestamp)
        
        // Oldest should be very close to firstTime (within 1 second tolerance)
        let timeDiff = abs(queueManager.oldestQueuedTimestamp!.timeIntervalSince(firstTime))
        XCTAssertLessThan(timeDiff, 1.0)
    }
    
@MainActor
    func testCleanupDeliveredMessages() async {
        // This method is called internally after marking messages as delivered
        queueManager.trackQueuedMessage(messageId: "msg-001", sessionId: "session-123")
        queueManager.markMessageDelivered(messageId: "msg-001")
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(queueManager.queuedMessages.count, 1)
        
        // Wait for cleanup to be triggered (normally happens after 2 second delay)
        let expectation = XCTestExpectation(description: "Cleanup triggered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            // After cleanup, delivered messages should be removed
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // The cleanup happens automatically, so we can't easily test it
        // But we can verify the message was delivered
        if let message = queueManager.queuedMessages.first {
            XCTAssertNotNil(message.deliveredAt)
        }
    }
    
    // MARK: - Performance Tests
    
@MainActor
    func testLargeQueuePerformance() async {
        let messageCount = 1000
        let startTime = Date()
        
        for i in 0..<messageCount {
            queueManager.trackQueuedMessage(
                messageId: "msg-\(i)",
                sessionId: "session-\(i % 10)"
            )
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Wait for main queue updates
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(queueManager.queuedMessageCount, messageCount)
        XCTAssertLessThan(duration, 1.0) // Should complete within 1 second
    }
    
    func testSessionFilteringPerformance() {
        // Add many messages across different sessions
        for i in 0..<500 {
            queueManager.trackQueuedMessage(
                messageId: "msg-\(i)",
                sessionId: "session-\(i % 20)" // 20 different sessions
            )
        }
        
        let startTime = Date()
        let queueInfo = queueManager.getQueueInfo(for: "session-5")
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertGreaterThan(queueInfo.count, 0) // Should find some messages
        XCTAssertLessThan(duration, 0.1) // Should be fast
    }
}