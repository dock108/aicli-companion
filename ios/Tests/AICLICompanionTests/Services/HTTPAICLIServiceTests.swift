import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class HTTPAICLIServiceTests: XCTestCase {
    
    var httpService: HTTPAICLIService!
    var mockService: MockHTTPAICLIService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        httpService = HTTPAICLIService()
        mockService = MockHTTPAICLIService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        httpService = nil
        mockService?.reset()
        mockService = nil
        cancellables.removeAll()
        super.tearDown()
    }
    
    // MARK: - Connection Tests
    
    func testSuccessfulConnection() throws {
        let expectation = XCTestExpectation(description: "Connection should succeed")
        
        mockService.connect(
            to: "localhost",
            port: 3000,
            authToken: nil
        ) { result in
            switch result {
            case .success:
                XCTAssertTrue(self.mockService.isConnected)
                XCTAssertEqual(self.mockService.connectionStatus, .connected)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Connection should succeed, but failed with: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify connection parameters were recorded
        XCTAssertEqual(mockService.lastConnectedAddress, "localhost")
        XCTAssertEqual(mockService.lastConnectedPort, 3000)
        XCTAssertNil(mockService.lastAuthToken)
    }
    
    func testConnectionWithAuthToken() throws {
        let expectation = XCTestExpectation(description: "Connection with auth token should succeed")
        let authToken = "test-auth-token-123"
        
        mockService.connect(
            to: "api.example.com",
            port: 443,
            authToken: authToken
        ) { result in
            switch result {
            case .success:
                XCTAssertTrue(self.mockService.isConnected)
                XCTAssertEqual(self.mockService.lastAuthToken, authToken)
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Connection with auth token should succeed, but failed with: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testConnectionFailure() throws {
        let expectation = XCTestExpectation(description: "Connection should fail")
        
        mockService.simulateConnectionError(.connectionFailed("Mock connection error"))
        
        mockService.connect(
            to: "invalid-server",
            port: 9999,
            authToken: nil
        ) { result in
            switch result {
            case .success:
                XCTFail("Connection should fail")
            case .failure(let error):
                XCTAssertFalse(self.mockService.isConnected)
                if case .error(let statusError) = self.mockService.connectionStatus {
                    XCTAssertTrue(statusError.localizedDescription.contains("Mock connection error"))
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testAuthenticationFailure() throws {
        let expectation = XCTestExpectation(description: "Authentication should fail")
        
        mockService.simulateAuthenticationFailure()
        
        mockService.connect(
            to: "secure-server.com",
            port: 443,
            authToken: "invalid-token"
        ) { result in
            switch result {
            case .success:
                XCTFail("Authentication should fail")
            case .failure(let error):
                XCTAssertEqual(error, .authenticationFailed)
                XCTAssertFalse(self.mockService.isConnected)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDisconnection() throws {
        // First connect
        let connectExpectation = XCTestExpectation(description: "Should connect first")
        
        mockService.connect(to: "localhost", port: 3000, authToken: nil) { result in
            switch result {
            case .success:
                connectExpectation.fulfill()
            case .failure:
                XCTFail("Connection should succeed")
            }
        }
        
        wait(for: [connectExpectation], timeout: 1.0)
        XCTAssertTrue(mockService.isConnected)
        
        // Then disconnect
        mockService.disconnect()
        
        XCTAssertFalse(mockService.isConnected)
        XCTAssertEqual(mockService.connectionStatus, .disconnected)
        XCTAssertNil(mockService.currentSession)
    }
    
    // MARK: - Chat Message Tests
    
    func testSuccessfulChatMessage() throws {
        let expectation = XCTestExpectation(description: "Chat message should succeed")
        
        // Setup connection first
        mockService.isConnected = true
        mockService.connectionStatus = .connected
        
        let testPrompt = "Hello, Claude!"
        let testProjectPath = "/test/project"
        let expectedResponse = TestDataFactory.createAICLIResponse(
            result: "Hello! How can I help you?",
            sessionId: "chat-session-123"
        )
        
        mockService.setMockResponse(expectedResponse)
        
        mockService.sendChatMessage(
            testPrompt,
            projectPath: testProjectPath,
            sessionId: nil
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.result, "Hello! How can I help you?")
                XCTAssertEqual(response.sessionId, "chat-session-123")
                XCTAssertFalse(response.isError)
                XCTAssertEqual(self.mockService.currentSession, "chat-session-123")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Chat message should succeed, but failed with: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify message was recorded
        XCTAssertEqual(mockService.recordedChatRequests.count, 1)
        XCTAssertEqual(mockService.recordedChatRequests.first, testPrompt)
    }
    
    func testChatMessageWithExistingSession() throws {
        let expectation = XCTestExpectation(description: "Chat message with session should succeed")
        
        mockService.isConnected = true
        mockService.connectionStatus = .connected
        
        let existingSessionId = "existing-session-456"
        let testPrompt = "Continue our conversation"
        let expectedResponse = TestDataFactory.createAICLIResponse(
            result: "Of course! Let's continue.",
            sessionId: existingSessionId
        )
        
        mockService.setMockResponse(expectedResponse)
        
        mockService.sendChatMessage(
            testPrompt,
            projectPath: "/test/project",
            sessionId: existingSessionId
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.sessionId, existingSessionId)
                XCTAssertEqual(response.result, "Of course! Let's continue.")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Chat message with session should succeed, but failed with: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testChatMessageNetworkFailure() throws {
        let expectation = XCTestExpectation(description: "Chat message should fail with network error")
        
        mockService.isConnected = true
        mockService.setMockError(.networkError(URLError(.notConnectedToInternet)))
        
        mockService.sendChatMessage(
            "Test message",
            projectPath: "/test/project",
            sessionId: nil
        ) { result in
            switch result {
            case .success:
                XCTFail("Chat message should fail with network error")
            case .failure(let error):
                if case .networkError(let urlError) = error {
                    XCTAssertEqual((urlError as? URLError)?.code, .notConnectedToInternet)
                } else {
                    XCTFail("Should be network error, got: \(error)")
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testChatMessageWithServerError() throws {
        let expectation = XCTestExpectation(description: "Chat message should handle server error")
        
        mockService.isConnected = true
        let errorResponse = TestDataFactory.createAICLIResponse(
            result: "Server error occurred",
            isError: true
        )
        mockService.setMockResponse(errorResponse)
        
        mockService.sendChatMessage(
            "Test message",
            projectPath: "/test/project",
            sessionId: nil
        ) { result in
            switch result {
            case .success(let response):
                XCTAssertTrue(response.isError)
                XCTAssertEqual(response.result, "Server error occurred")
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Should succeed but with error response, got failure: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Connection Status Tests
    
    func testConnectionStatusObservation() throws {
        let expectation = XCTestExpectation(description: "Connection status should be observable")
        var receivedStatuses: [ConnectionStatus] = []
        
        mockService.$connectionStatus
            .sink { status in
                receivedStatuses.append(status)
                if receivedStatuses.count == 3 { // disconnected -> connected -> error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate status changes
        mockService.connectionStatus = .connected
        mockService.simulateConnectionLoss()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedStatuses.count, 3)
        XCTAssertEqual(receivedStatuses[0], .disconnected) // Initial
        XCTAssertEqual(receivedStatuses[1], .connected)
        if case .error = receivedStatuses[2] {
            // Expected error status
        } else {
            XCTFail("Third status should be error")
        }
    }
    
    func testIsConnectedObservation() throws {
        let expectation = XCTestExpectation(description: "isConnected should be observable")
        var connectionStates: [Bool] = []
        
        mockService.$isConnected
            .sink { isConnected in
                connectionStates.append(isConnected)
                if connectionStates.count == 3 { // false -> true -> false
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Simulate connection changes
        mockService.isConnected = true
        mockService.isConnected = false
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(connectionStates, [false, true, false])
    }
    
    // MARK: - Test Connection Tests
    
    func testSuccessfulTestConnection() throws {
        let expectation = XCTestExpectation(description: "Test connection should succeed")
        
        mockService.testConnection { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Test connection should succeed, but failed with: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testFailedTestConnection() throws {
        let expectation = XCTestExpectation(description: "Test connection should fail")
        
        mockService.simulateConnectionError(.connectionFailed("Test connection failed"))
        
        mockService.testConnection { result in
            switch result {
            case .success:
                XCTFail("Test connection should fail")
            case .failure(let error):
                XCTAssertTrue(error.localizedDescription.contains("Test connection failed"))
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Device Registration Tests
    
    func testSuccessfulDeviceRegistration() throws {
        let expectation = XCTestExpectation(description: "Device registration should succeed")
        
        let deviceToken = "test-device-token-789"
        
        mockService.registerDeviceForPushNotifications(deviceToken: deviceToken) { result in
            switch result {
            case .success:
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Device registration should succeed, but failed with: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Mock Service Behavior Tests
    
    func testMockServiceReset() throws {
        // Setup some state
        mockService.isConnected = true
        mockService.connectionStatus = .connected
        mockService.currentSession = "test-session"
        mockService.shouldFailConnection = true
        mockService.recordedChatRequests = ["test message"]
        mockService.lastConnectedAddress = "test.com"
        
        // Reset
        mockService.reset()
        
        // Verify reset state
        XCTAssertFalse(mockService.isConnected)
        XCTAssertEqual(mockService.connectionStatus, .disconnected)
        XCTAssertNil(mockService.currentSession)
        XCTAssertFalse(mockService.shouldFailConnection)
        XCTAssertTrue(mockService.recordedChatRequests.isEmpty)
        XCTAssertNil(mockService.lastConnectedAddress)
    }
    
    func testMockServiceConnectionDelay() throws {
        let expectation = XCTestExpectation(description: "Connection should have delay")
        mockService.connectionDelay = 0.5
        
        let startTime = Date()
        
        mockService.connect(to: "localhost", port: 3000, authToken: nil) { result in
            let elapsedTime = Date().timeIntervalSince(startTime)
            XCTAssertGreaterThanOrEqual(elapsedTime, 0.5)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testMockServiceResponseDelay() throws {
        let expectation = XCTestExpectation(description: "Chat response should have delay")
        mockService.responseDelay = 0.3
        mockService.isConnected = true
        
        let startTime = Date()
        
        mockService.sendChatMessage("Test", projectPath: "/test", sessionId: nil) { result in
            let elapsedTime = Date().timeIntervalSince(startTime)
            XCTAssertGreaterThanOrEqual(elapsedTime, 0.3)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Edge Cases Tests
    
    func testMultipleConcurrentChatMessages() throws {
        let expectation = XCTestExpectation(description: "Multiple chat messages should complete")
        expectation.expectedFulfillmentCount = 3
        
        mockService.isConnected = true
        mockService.responseDelay = 0.1
        
        for i in 1...3 {
            mockService.sendChatMessage(
                "Message \(i)",
                projectPath: "/test",
                sessionId: nil
            ) { result in
                switch result {
                case .success(let response):
                    XCTAssertTrue(response.result.contains("Message \(i)"))
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Message \(i) should succeed, but failed with: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertEqual(mockService.recordedChatRequests.count, 3)
    }
    
    func testConnectionWithEmptyAddress() throws {
        let expectation = XCTestExpectation(description: "Should handle empty address")
        
        mockService.connect(to: "", port: 3000, authToken: nil) { result in
            // Mock service should still work with empty address
            switch result {
            case .success:
                XCTAssertEqual(self.mockService.lastConnectedAddress, "")
                expectation.fulfill()
            case .failure:
                // Also acceptable for empty address
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testChatMessageWithEmptyContent() throws {
        let expectation = XCTestExpectation(description: "Should handle empty content")
        
        mockService.isConnected = true
        
        mockService.sendChatMessage("", projectPath: "/test", sessionId: nil) { result in
            switch result {
            case .success(let response):
                // Mock should respond to empty messages
                XCTAssertTrue(response.result.contains("Mock response to:"))
                expectation.fulfill()
            case .failure:
                XCTFail("Should handle empty messages")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockService.recordedChatRequests.count, 1)
        XCTAssertEqual(mockService.recordedChatRequests.first, "")
    }
    
    // MARK: - Performance Tests
    
    func testChatMessagePerformance() throws {
        mockService.isConnected = true
        mockService.responseDelay = 0.0 // No delay for performance test
        
        measure {
            let group = DispatchGroup()
            
            for i in 0..<100 {
                group.enter()
                mockService.sendChatMessage(
                    "Performance test message \(i)",
                    projectPath: "/test",
                    sessionId: nil
                ) { _ in
                    group.leave()
                }
            }
            
            group.wait()
        }
    }
}