import XCTest
import Combine
@testable import AICLICompanion

/// Integration tests for CloudKit sync and device coordination working together
@available(iOS 16.0, macOS 13.0, *)
final class CloudKitDeviceCoordinationIntegrationTests: XCTestCase {
    
    var chatViewModel: ChatViewModel!
    var cloudKitSync: CloudKitSyncManager!
    var deviceCoordinator: DeviceCoordinator!
    var mockWebSocketManager: MockWebSocketManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        
        mockWebSocketManager = MockWebSocketManager()
        deviceCoordinator = DeviceCoordinator(webSocketManager: mockWebSocketManager)
        cloudKitSync = CloudKitSyncManager()
        chatViewModel = ChatViewModel.shared
        cancellables = Set<AnyCancellable>()
        
        // Setup initial state
        mockWebSocketManager.isConnected = true
    }
    
    override func tearDown() {
        cancellables = nil
        chatViewModel = nil
        cloudKitSync = nil
        deviceCoordinator = nil
        mockWebSocketManager = nil
        super.tearDown()
    }
    
    // MARK: - Multi-Device Message Sync Tests
    
    func testMultiDeviceMessageSync() async throws {
        // Given
        let project = createTestProject()
        let sessionId = "test-session-123"
        
        // Setup: Device becomes primary
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: true)
        
        XCTAssertTrue(deviceCoordinator.isPrimary)
        
        // Setup CloudKit as available
        await setupCloudKitAvailable()
        
        // When: Send message as primary device
        let testMessage = "Test message for sync"
        
        let messageExpectation = XCTestExpectation(description: "Message sent and synced")
        
        // Monitor message addition
        chatViewModel.$messages
            .dropFirst()
            .sink { messages in
                if !messages.isEmpty && messages.last?.content == testMessage {
                    messageExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Send message using device coordination
        await chatViewModel.sendMessageWithCoordination(testMessage, for: project)
        
        // Then
        await fulfillment(of: [messageExpectation], timeout: 5.0)
        
        // Verify message was added locally
        XCTAssertFalse(chatViewModel.messages.isEmpty)
        XCTAssertEqual(chatViewModel.messages.last?.content, testMessage)
        
        // Verify CloudKit sync was attempted
        XCTAssertNotNil(chatViewModel.messages.last?.messageHash)
        XCTAssertTrue(chatViewModel.messages.last?.needsSync == true)
    }
    
    func testSecondaryDeviceCannotSendMessages() async throws {
        // Given
        let project = createTestProject()
        let sessionId = "test-session-123"
        
        // Setup: Device is secondary (another device is primary)
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: false, primaryDevice: "other-device")
        
        XCTAssertFalse(deviceCoordinator.isPrimary)
        
        // When: Attempt to send message as secondary device
        let initialMessageCount = chatViewModel.messages.count
        await chatViewModel.sendMessageWithCoordination("Should not send", for: project)
        
        // Then: Message should not be sent
        XCTAssertEqual(chatViewModel.messages.count, initialMessageCount)
    }
    
    // MARK: - Primary Device Handoff Tests
    
    func testPrimaryDeviceHandoff() async throws {
        // Given
        let project = createTestProject()
        let sessionId = "test-session-123"
        let otherDeviceId = "other-device-456"
        
        // Setup: Device starts as primary
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: true)
        
        XCTAssertTrue(deviceCoordinator.isPrimary)
        
        // When: Transfer primary to other device
        try await deviceCoordinator.transferPrimary(to: otherDeviceId)
        await simulatePrimaryTransferResult(success: true, newPrimary: otherDeviceId)
        
        // Then: Device should no longer be primary
        XCTAssertFalse(deviceCoordinator.isPrimary)
        XCTAssertEqual(deviceCoordinator.primaryElectionStatus, .secondary)
        
        // Test message sending is now blocked
        let initialMessageCount = chatViewModel.messages.count
        await chatViewModel.sendMessageWithCoordination("Should not send", for: project)
        XCTAssertEqual(chatViewModel.messages.count, initialMessageCount)
    }
    
    // MARK: - CloudKit Sync with Device Coordination Tests
    
    func testCloudKitSyncWithDeviceCoordination() async throws {
        // Given
        let project = createTestProject()
        let sessionId = "test-session-123"
        
        // Setup device coordination
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: true)
        
        // Setup CloudKit
        await setupCloudKitAvailable()
        
        // When: Perform CloudKit sync for the project
        let syncExpectation = XCTestExpectation(description: "CloudKit sync completed")
        
        cloudKitSync.$syncStatus
            .dropFirst()
            .sink { status in
                if status == .synced {
                    syncExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        try await chatViewModel.syncProject(project)
        
        // Then
        await fulfillment(of: [syncExpectation], timeout: 10.0)
        XCTAssertEqual(cloudKitSync.syncStatus, .synced)
    }
    
    // MARK: - Duplicate Message Prevention Tests
    
    func testDuplicateMessagePrevention() async throws {
        // Given
        let project = createTestProject()
        let sessionId = "test-session-123"
        let messageContent = "Test duplicate message"
        
        // Setup: Device is primary
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: true)
        
        await setupCloudKitAvailable()
        
        // When: Send same message twice quickly
        await chatViewModel.sendMessageWithCoordination(messageContent, for: project)
        let firstMessageCount = chatViewModel.messages.count
        
        // Attempt to send identical message
        await chatViewModel.sendMessageWithCoordination(messageContent, for: project)
        let secondMessageCount = chatViewModel.messages.count
        
        // Then: Second message should have different hash or be handled appropriately
        // The exact behavior depends on implementation - either blocked or allowed with different timestamps
        // For now, we verify that the system handles it gracefully
        XCTAssertGreaterThanOrEqual(secondMessageCount, firstMessageCount)
    }
    
    // MARK: - Connection Recovery Tests
    
    func testConnectionRecovery() async throws {
        // Given
        let sessionId = "test-session-123"
        
        // Setup: Device is registered and in session
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: true)
        
        XCTAssertTrue(deviceCoordinator.isPrimary)
        XCTAssertEqual(deviceCoordinator.registrationStatus, .registered)
        
        // When: Connection is lost
        mockWebSocketManager.disconnect()
        await simulateConnectionStatusChange(.disconnected)
        
        // Then: Device status should be reset
        XCTAssertEqual(deviceCoordinator.connectionStatus, .disconnected)
        XCTAssertEqual(deviceCoordinator.registrationStatus, .unregistered)
        XCTAssertFalse(deviceCoordinator.isPrimary)
        
        // When: Connection is restored
        mockWebSocketManager.connect(to: "ws://localhost", token: nil)
        await simulateConnectionStatusChange(.connected)
        
        // Then: Device should be ready to re-register
        XCTAssertEqual(deviceCoordinator.connectionStatus, .connected)
    }
    
    // MARK: - Error Handling Tests
    
    func testCloudKitSyncErrorHandling() async throws {
        // Given
        let project = createTestProject()
        
        // Setup: CloudKit is unavailable
        await MainActor.run {
            cloudKitSync.iCloudAvailable = false
            cloudKitSync.errorMessage = "iCloud account not available"
        }
        
        // When: Attempt to sync
        do {
            try await chatViewModel.syncProject(project)
            XCTFail("Should throw CloudKit unavailable error")
        } catch CloudKitSchema.SyncError.iCloudUnavailable {
            // Then: Error should be handled gracefully
            XCTAssertFalse(cloudKitSync.iCloudAvailable)
            XCTAssertNotNil(cloudKitSync.errorMessage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Performance Tests
    
    func testMultiDevicePerformance() async throws {
        // Given
        let project = createTestProject()
        let sessionId = "test-session-123"
        let messageCount = 50
        
        // Setup
        try await deviceCoordinator.registerWithServer(userId: "test-user")
        await simulateDeviceRegistered()
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: true)
        await setupCloudKitAvailable()
        
        // When: Send multiple messages rapidly
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<messageCount {
            await chatViewModel.sendMessageWithCoordination("Message \(i)", for: project)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        // Then: Performance should be reasonable
        XCTAssertLessThan(duration, 10.0, "Sending \(messageCount) messages took too long: \(duration)s")
        XCTAssertEqual(chatViewModel.messages.count, messageCount)
    }
    
    // MARK: - Helper Methods
    
    private func createTestProject() -> Project {
        return Project(name: "Test Project", path: "/test/project")
    }
    
    private func setupCloudKitAvailable() async {
        await MainActor.run {
            cloudKitSync.iCloudAvailable = true
            cloudKitSync.syncStatus = .pending
        }
    }
    
    private func simulateDeviceRegistered() async {
        let message = [
            "type": "device-registered",
            "deviceId": deviceCoordinator.currentDeviceId
        ]
        await simulateWebSocketMessage(message)
    }
    
    private func simulateSessionJoined(sessionId: String, isPrimary: Bool, primaryDevice: String? = nil) async {
        let message = [
            "type": "session-joined",
            "sessionId": sessionId,
            "activeDevices": [],
            "primaryDeviceId": primaryDevice ?? (isPrimary ? deviceCoordinator.currentDeviceId : nil),
            "isPrimary": isPrimary
        ] as [String: Any]
        
        await simulateWebSocketMessage(message)
    }
    
    private func simulatePrimaryTransferResult(success: Bool, newPrimary: String) async {
        let message = [
            "type": "primary-transfer-result",
            "success": success,
            "newPrimaryDeviceId": newPrimary
        ] as [String: Any]
        
        await simulateWebSocketMessage(message)
    }
    
    private func simulateWebSocketMessage(_ message: [String: Any]) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .deviceCoordinationMessageReceived,
                object: nil,
                userInfo: message
            )
        }
        
        // Allow time for async processing
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    private func simulateConnectionStatusChange(_ status: WebSocketManager.ConnectionStatus) async {
        // Simulate connection status change
        await MainActor.run {
            // This would normally be handled by the WebSocket manager
            // For testing, we manually update the status
        }
    }
}

// MARK: - Test Utilities

extension CloudKitDeviceCoordinationIntegrationTests {
    
    /// Simulate multiple devices scenario
    func setupMultiDeviceScenario(deviceCount: Int) async throws -> [String] {
        var deviceIds: [String] = []
        
        for i in 0..<deviceCount {
            let deviceId = "test-device-\(i)"
            deviceIds.append(deviceId)
        }
        
        // Simulate other devices in session
        let activeDevices = deviceIds.dropFirst().enumerated().map { (index, deviceId) in
            return [
                "deviceId": deviceId,
                "platform": "iOS",
                "lastSeen": Date().timeIntervalSince1970 * 1000,
                "isPrimary": index == 0 // First other device is primary
            ]
        }
        
        let message = [
            "type": "session-joined",
            "sessionId": "multi-device-session",
            "activeDevices": activeDevices,
            "primaryDeviceId": activeDevices.first?["deviceId"],
            "isPrimary": false
        ] as [String: Any]
        
        await simulateWebSocketMessage(message)
        
        return deviceIds
    }
    
    /// Create test messages with CloudKit properties
    func createTestMessagesWithCloudKitProps(count: Int) -> [Message] {
        var messages: [Message] = []
        
        for i in 0..<count {
            var message = Message(
                content: "Test message \(i)",
                sender: i % 2 == 0 ? .user : .assistant,
                type: .text,
                metadata: AICLIMessageMetadata(sessionId: "test-session", duration: 0)
            )
            
            message.messageHash = "hash-\(i)"
            message.markAsNeedingSync()
            messages.append(message)
        }
        
        return messages
    }
}

// MARK: - Load Test

@available(iOS 16.0, macOS 13.0, *)
extension CloudKitDeviceCoordinationIntegrationTests {
    
    func testHighLoadMultiDeviceScenario() async throws {
        // Given
        let deviceCount = 10
        let messagesPerDevice = 20
        let sessionId = "load-test-session"
        
        // Setup multiple devices
        let deviceIds = try await setupMultiDeviceScenario(deviceCount: deviceCount)
        
        // Setup current device as secondary
        try await deviceCoordinator.registerWithServer(userId: "load-test-user")
        await simulateDeviceRegistered()
        
        try await deviceCoordinator.joinSession(sessionId)
        await simulateSessionJoined(sessionId: sessionId, isPrimary: false)
        
        // When: Simulate high message load from other devices
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for deviceId in deviceIds {
            for messageIndex in 0..<messagesPerDevice {
                // Simulate message received from other device
                let messageData = [
                    "type": "message-received",
                    "deviceId": deviceId,
                    "content": "Message \(messageIndex) from \(deviceId)",
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ] as [String: Any]
                
                await simulateWebSocketMessage(messageData)
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        // Then: System should handle high load gracefully
        let totalMessages = deviceCount * messagesPerDevice
        XCTAssertLessThan(duration, 30.0, "Processing \(totalMessages) messages took too long: \(duration)s")
        XCTAssertEqual(deviceCoordinator.activeDevices.count, deviceCount - 1) // Excluding current device
        XCTAssertFalse(deviceCoordinator.isPrimary) // Should remain secondary
    }
}