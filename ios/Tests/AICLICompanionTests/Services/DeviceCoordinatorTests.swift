import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class DeviceCoordinatorTests: XCTestCase {
    var sut: DeviceCoordinator!
    var mockWebSocketManager: MockWebSocketManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockWebSocketManager = MockWebSocketManager()
        sut = DeviceCoordinator(webSocketManager: mockWebSocketManager)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        sut = nil
        mockWebSocketManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertFalse(sut.isPrimary)
        XCTAssertTrue(sut.activeDevices.isEmpty)
        XCTAssertNotNil(sut.currentDeviceId)
        XCTAssertEqual(sut.registrationStatus, .unregistered)
        XCTAssertEqual(sut.primaryElectionStatus, .none)
        XCTAssertEqual(sut.connectionStatus, .disconnected)
    }
    
    // MARK: - Device Registration Tests
    
    func testRegisterWithServer_Success() async throws {
        // Given
        let userId = "test-user-123"
        mockWebSocketManager.isConnected = true
        
        // When
        try await sut.registerWithServer(userId: userId)
        
        // Then
        XCTAssertEqual(mockWebSocketManager.sentMessages.count, 1)
        
        let sentMessage = mockWebSocketManager.sentMessages.first
        XCTAssertEqual(sentMessage?["type"] as? String, "device-announce")
        XCTAssertEqual(sentMessage?["userId"] as? String, userId)
        XCTAssertEqual(sentMessage?["deviceId"] as? String, sut.currentDeviceId)
        
        // Simulate successful registration response
        await simulateDeviceRegisteredMessage()
        
        XCTAssertEqual(sut.registrationStatus, .registered)
    }
    
    func testRegisterWithServer_WhenWebSocketUnavailable() async {
        // Given
        sut.setWebSocketManager(nil as! WebSocketManager) // Force nil
        
        // When & Then
        do {
            try await sut.registerWithServer(userId: "test-user")
            XCTFail("Should throw webSocketNotAvailable error")
        } catch DeviceCoordinationError.webSocketNotAvailable {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Session Management Tests
    
    func testJoinSession_Success() async throws {
        // Given
        let sessionId = "test-session-123"
        mockWebSocketManager.isConnected = true
        
        // When
        try await sut.joinSession(sessionId)
        
        // Then
        XCTAssertEqual(mockWebSocketManager.sentMessages.count, 1)
        
        let sentMessage = mockWebSocketManager.sentMessages.first
        XCTAssertEqual(sentMessage?["type"] as? String, "session-join")
        XCTAssertEqual(sentMessage?["sessionId"] as? String, sessionId)
        XCTAssertEqual(sentMessage?["deviceId"] as? String, sut.currentDeviceId)
    }
    
    func testLeaveSession_Success() async throws {
        // Given
        let sessionId = "test-session-123"
        mockWebSocketManager.isConnected = true
        
        // First join the session
        try await sut.joinSession(sessionId)
        mockWebSocketManager.sentMessages.removeAll()
        
        // When
        try await sut.leaveSession()
        
        // Then
        XCTAssertEqual(mockWebSocketManager.sentMessages.count, 1)
        
        let sentMessage = mockWebSocketManager.sentMessages.first
        XCTAssertEqual(sentMessage?["type"] as? String, "session-leave")
        XCTAssertEqual(sentMessage?["sessionId"] as? String, sessionId)
    }
    
    // MARK: - Primary Device Election Tests
    
    func testRequestPrimary_Success() async throws {
        // Given
        let sessionId = "test-session-123"
        mockWebSocketManager.isConnected = true
        
        // Join session first
        try await sut.joinSession(sessionId)
        mockWebSocketManager.sentMessages.removeAll()
        
        // When
        try await sut.requestPrimary()
        
        // Then
        XCTAssertEqual(sut.primaryElectionStatus, .requesting)
        XCTAssertEqual(mockWebSocketManager.sentMessages.count, 1)
        
        let sentMessage = mockWebSocketManager.sentMessages.first
        XCTAssertEqual(sentMessage?["type"] as? String, "primary-election-request")
        XCTAssertEqual(sentMessage?["sessionId"] as? String, sessionId)
    }
    
    func testRequestPrimary_WhenNoActiveSession() async {
        // Given
        // No session joined
        
        // When & Then
        do {
            try await sut.requestPrimary()
            XCTFail("Should throw noActiveSession error")
        } catch DeviceCoordinationError.noActiveSession {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTransferPrimary_Success() async throws {
        // Given
        let sessionId = "test-session-123"
        let targetDeviceId = "target-device-456"
        mockWebSocketManager.isConnected = true
        
        // Setup: join session and become primary
        try await sut.joinSession(sessionId)
        await simulatePrimaryElectedMessage(deviceId: sut.currentDeviceId)
        mockWebSocketManager.sentMessages.removeAll()
        
        // When
        try await sut.transferPrimary(to: targetDeviceId)
        
        // Then
        XCTAssertEqual(sut.primaryElectionStatus, .transferring)
        XCTAssertEqual(mockWebSocketManager.sentMessages.count, 1)
        
        let sentMessage = mockWebSocketManager.sentMessages.first
        XCTAssertEqual(sentMessage?["type"] as? String, "primary-transfer-request")
        XCTAssertEqual(sentMessage?["fromDeviceId"] as? String, sut.currentDeviceId)
        XCTAssertEqual(sentMessage?["toDeviceId"] as? String, targetDeviceId)
    }
    
    func testTransferPrimary_WhenNotPrimary() async {
        // Given
        let targetDeviceId = "target-device-456"
        // Device is not primary
        
        // When & Then
        do {
            try await sut.transferPrimary(to: targetDeviceId)
            XCTFail("Should throw notPrimaryDevice error")
        } catch DeviceCoordinationError.notPrimaryDevice {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testReleasePrimary() async throws {
        // Given
        await simulatePrimaryElectedMessage(deviceId: sut.currentDeviceId)
        XCTAssertTrue(sut.isPrimary)
        
        // When
        try await sut.releasePrimary()
        
        // Then
        XCTAssertFalse(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .none)
    }
    
    // MARK: - Heartbeat Tests
    
    func testSendHeartbeat_Success() async {
        // Given
        mockWebSocketManager.isConnected = true
        await simulateDeviceRegisteredMessage()
        
        // When
        await sut.sendHeartbeat()
        
        // Then
        XCTAssertEqual(mockWebSocketManager.sentMessages.count, 1)
        
        let sentMessage = mockWebSocketManager.sentMessages.first
        XCTAssertEqual(sentMessage?["type"] as? String, "device-heartbeat")
        XCTAssertEqual(sentMessage?["deviceId"] as? String, sut.currentDeviceId)
        XCTAssertNotNil(sentMessage?["timestamp"])
    }
    
    func testSendHeartbeat_WhenNotRegistered() async {
        // Given
        mockWebSocketManager.isConnected = true
        // Device is not registered
        
        // When
        await sut.sendHeartbeat()
        
        // Then - no message should be sent
        XCTAssertTrue(mockWebSocketManager.sentMessages.isEmpty)
    }
    
    // MARK: - Message Handling Tests
    
    func testHandleDeviceRegistered() async {
        // Given
        let message = [
            "type": "device-registered",
            "deviceId": sut.currentDeviceId
        ]
        
        // When
        await simulateWebSocketMessage(message)
        
        // Then
        XCTAssertEqual(sut.registrationStatus, .registered)
    }
    
    func testHandleSessionJoined() async {
        // Given
        let sessionId = "test-session-123"
        let message = [
            "type": "session-joined",
            "sessionId": sessionId,
            "activeDevices": [
                [
                    "deviceId": "other-device",
                    "platform": "iOS",
                    "lastSeen": Date().timeIntervalSince1970 * 1000,
                    "isPrimary": false
                ]
            ],
            "primaryDeviceId": nil,
            "isPrimary": false
        ] as [String: Any]
        
        // When
        await simulateWebSocketMessage(message)
        
        // Then
        XCTAssertEqual(sut.activeDevices.count, 1)
        XCTAssertEqual(sut.activeDevices.first?.deviceId, "other-device")
        XCTAssertFalse(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .none)
    }
    
    func testHandlePrimaryElected() async {
        // Given
        let sessionId = "test-session-123"
        let message = [
            "type": "primary-elected",
            "sessionId": sessionId,
            "deviceId": sut.currentDeviceId
        ]
        
        // When
        await simulateWebSocketMessage(message)
        
        // Then
        XCTAssertTrue(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .primary)
    }
    
    func testHandlePrimaryElected_OtherDevice() async {
        // Given
        let sessionId = "test-session-123"
        let message = [
            "type": "primary-elected",
            "sessionId": sessionId,
            "deviceId": "other-device-123"
        ]
        
        // When
        await simulateWebSocketMessage(message)
        
        // Then
        XCTAssertFalse(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .secondary)
    }
    
    func testHandlePrimaryElectionResult_Success() async {
        // Given
        let message = [
            "type": "primary-election-result",
            "success": true,
            "isPrimary": true,
            "primaryDeviceId": sut.currentDeviceId
        ] as [String: Any]
        
        // When
        await simulateWebSocketMessage(message)
        
        // Then
        XCTAssertTrue(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .primary)
    }
    
    func testHandlePrimaryElectionResult_Failed() async {
        // Given
        let message = [
            "type": "primary-election-result",
            "success": false,
            "reason": "primary_exists"
        ] as [String: Any]
        
        // When
        await simulateWebSocketMessage(message)
        
        // Then
        XCTAssertFalse(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .failed)
    }
    
    // MARK: - Connection Status Tests
    
    func testConnectionStatusUpdates() async {
        // Given
        let expectation = XCTestExpectation(description: "Connection status updated")
        
        sut.$connectionStatus
            .dropFirst() // Skip initial value
            .sink { status in
                if status == .connected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        mockWebSocketManager.connectionStatus = .connected
        await simulateConnectionStatusChange(.connected)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.connectionStatus, .connected)
    }
    
    // MARK: - Helper Methods
    
    private func simulateWebSocketMessage(_ message: [String: Any]) async {
        await MainActor.run {
            // Simulate message received via WebSocket
            NotificationCenter.default.post(
                name: .deviceCoordinationMessageReceived,
                object: nil,
                userInfo: message
            )
        }
        
        // Give time for async processing
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    private func simulateDeviceRegisteredMessage() async {
        let message = [
            "type": "device-registered",
            "deviceId": sut.currentDeviceId
        ]
        await simulateWebSocketMessage(message)
    }
    
    private func simulatePrimaryElectedMessage(deviceId: String) async {
        let message = [
            "type": "primary-elected",
            "sessionId": "current-session",
            "deviceId": deviceId
        ]
        await simulateWebSocketMessage(message)
    }
    
    private func simulateConnectionStatusChange(_ status: WebSocketManager.ConnectionStatus) async {
        await MainActor.run {
            // This would typically be handled by the WebSocket manager
            // For testing, we simulate the status change
        }
    }
}

// MARK: - Mock WebSocket Manager

@available(iOS 16.0, macOS 13.0, *)
class MockWebSocketManager: WebSocketManager {
    var sentMessages: [[String: Any]] = []
    var isConnected = false
    var connectionStatus: ConnectionStatus = .disconnected
    
    override func send(_ message: [String: Any]) async throws {
        sentMessages.append(message)
    }
    
    override func connect(to serverURL: String, token: String?) {
        isConnected = true
        connectionStatus = .connected
    }
    
    override func disconnect() {
        isConnected = false
        connectionStatus = .disconnected
    }
}

// MARK: - Integration Tests

@available(iOS 16.0, macOS 13.0, *)
extension DeviceCoordinatorTests {
    func testFullDeviceCoordinationFlow() async throws {
        // Given
        let userId = "test-user"
        let sessionId = "test-session"
        mockWebSocketManager.isConnected = true
        
        // When - Register device
        try await sut.registerWithServer(userId: userId)
        await simulateDeviceRegisteredMessage()
        
        // Then - Device should be registered
        XCTAssertEqual(sut.registrationStatus, .registered)
        
        // When - Join session
        try await sut.joinSession(sessionId)
        await simulateWebSocketMessage([
            "type": "session-joined",
            "sessionId": sessionId,
            "activeDevices": [],
            "primaryDeviceId": nil,
            "isPrimary": false
        ])
        
        // Then - Session should be joined
        XCTAssertTrue(sut.activeDevices.isEmpty)
        
        // When - Request primary
        try await sut.requestPrimary()
        await simulateWebSocketMessage([
            "type": "primary-election-result",
            "success": true,
            "isPrimary": true,
            "primaryDeviceId": sut.currentDeviceId
        ] as [String: Any])
        
        // Then - Should become primary
        XCTAssertTrue(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .primary)
        
        // When - Another device joins
        await simulateWebSocketMessage([
            "type": "session-joined",
            "sessionId": sessionId,
            "activeDevices": [
                [
                    "deviceId": "other-device",
                    "platform": "iOS",
                    "lastSeen": Date().timeIntervalSince1970 * 1000,
                    "isPrimary": false
                ]
            ],
            "primaryDeviceId": sut.currentDeviceId,
            "isPrimary": true
        ] as [String: Any])
        
        // Then - Should show other device
        XCTAssertEqual(sut.activeDevices.count, 1)
        XCTAssertTrue(sut.isPrimary)
        
        // When - Transfer primary to other device
        try await sut.transferPrimary(to: "other-device")
        await simulateWebSocketMessage([
            "type": "primary-transfer-result",
            "success": true,
            "newPrimaryDeviceId": "other-device"
        ] as [String: Any])
        
        // Then - Should no longer be primary
        XCTAssertFalse(sut.isPrimary)
        XCTAssertEqual(sut.primaryElectionStatus, .secondary)
    }
}
