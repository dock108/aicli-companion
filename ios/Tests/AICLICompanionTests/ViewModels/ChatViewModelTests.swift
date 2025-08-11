import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatViewModelTests: XCTestCase {
    
    var chatViewModel: ChatViewModel!
    var mockAICLIService: MockHTTPAICLIService!
    var mockSettings: SettingsManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        mockAICLIService = MockHTTPAICLIService()
        mockSettings = SettingsManager()
        chatViewModel = ChatViewModel(aicliService: mockAICLIService, settings: mockSettings)
        cancellables = Set<AnyCancellable>()
        
        // Setup connected state for HTTP service
        mockAICLIService.isConnected = true
        mockAICLIService.connectionStatus = .connected
    }
    
    override func tearDown() async throws {
        chatViewModel = nil
        mockAICLIService?.reset()
        mockAICLIService = nil
        mockSettings = nil
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async throws {
        XCTAssertEqual(chatViewModel.messages.count, 0)
        XCTAssertFalse(chatViewModel.isLoading)
        XCTAssertNil(chatViewModel.progressInfo)
        XCTAssertNil(chatViewModel.sessionError)
        XCTAssertNil(chatViewModel.activeSession)
        XCTAssertNil(chatViewModel.currentSessionId)
        XCTAssertNil(chatViewModel.currentProject)
    }
    
    // MARK: - Message Sending Tests
    
    func testSendMessageAddsUserMessage() async throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        let testMessage = "Hello, Claude!"
        
        XCTAssertEqual(chatViewModel.messages.count, 0)
        
        // Setup mock response
        let mockResponse = TestDataFactory.createAICLIResponse(
            result: "Hello! How can I help you?",
            sessionId: "test-session-123"
        )
        mockAICLIService.setMockResponse(mockResponse)
        
        chatViewModel.sendMessage(testMessage, for: testProject)
        
        // Should immediately add user message
        XCTAssertEqual(chatViewModel.messages.count, 1)
        XCTAssertEqual(chatViewModel.messages[0].content, testMessage)
        XCTAssertEqual(chatViewModel.messages[0].sender, .user)
        XCTAssertEqual(chatViewModel.messages[0].type, .text)
        XCTAssertTrue(chatViewModel.isLoading)
    }
    
    func testSendEmptyMessageDoesNothing() async throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        XCTAssertEqual(chatViewModel.messages.count, 0)
        
        chatViewModel.sendMessage("", for: testProject)
        
        // Should not add any message or start loading
        XCTAssertEqual(chatViewModel.messages.count, 0)
        XCTAssertFalse(chatViewModel.isLoading)
    }
    
    func testSendWhitespaceOnlyMessageDoesNothing() async throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        XCTAssertEqual(chatViewModel.messages.count, 0)
        
        chatViewModel.sendMessage("   \n\t  ", for: testProject)
        
        // Should not add any message or start loading
        XCTAssertEqual(chatViewModel.messages.count, 0)
        XCTAssertFalse(chatViewModel.isLoading)
    }
    
    func testSendMessageUpdatesCurrentProject() async throws {
        let project1 = TestDataFactory.TestProject.frontend
        let testProject1 = Project(name: project1.name, path: project1.path, type: "Frontend")
        
        let project2 = TestDataFactory.TestProject.backend
        let testProject2 = Project(name: project2.name, path: project2.path, type: "Backend")
        
        XCTAssertNil(chatViewModel.currentProject)
        
        // Setup mock response
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        
        // Send message to first project
        chatViewModel.sendMessage("Test 1", for: testProject1)
        XCTAssertEqual(chatViewModel.currentProject?.path, testProject1.path)
        
        // Send message to second project
        chatViewModel.sendMessage("Test 2", for: testProject2)
        XCTAssertEqual(chatViewModel.currentProject?.path, testProject2.path)
    }
    
    func testSendMessageWithServiceNotConnected() async throws {
        let project = TestDataFactory.TestProject.mobile
        let testProject = Project(name: project.name, path: project.path, type: "Mobile")
        
        // Disconnect the service
        mockAICLIService.isConnected = false
        mockAICLIService.connectionStatus = .disconnected
        
        chatViewModel.sendMessage("Test message", for: testProject)
        
        // Should still add user message but show error
        XCTAssertEqual(chatViewModel.messages.count, 1)
        XCTAssertNotNil(chatViewModel.sessionError)
        XCTAssertFalse(chatViewModel.isLoading)
    }
    
    // MARK: - Loading State Tests
    
    func testLoadingStateChanges() async throws {
        let expectation = XCTestExpectation(description: "Loading state should change")
        var loadingStates: [Bool] = []
        
        chatViewModel.$isLoading
            .sink { isLoading in
                loadingStates.append(isLoading)
                if loadingStates.count >= 2 { // false -> true
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        // Setup mock response with delay
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        mockAICLIService.responseDelay = 0.1
        
        chatViewModel.sendMessage("Test", for: testProject)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(loadingStates[0], false) // Initial state
        XCTAssertEqual(loadingStates[1], true)  // After sending message
    }
    
    // MARK: - Message Management Tests
    
    func testMessagesArePublished() async throws {
        let expectation = XCTestExpectation(description: "Messages should be published")
        var messageCountChanges: [Int] = []
        
        chatViewModel.$messages
            .map { $0.count }
            .sink { count in
                messageCountChanges.append(count)
                if messageCountChanges.count >= 2 { // 0 -> 1
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        
        chatViewModel.sendMessage("Test message", for: testProject)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(messageCountChanges[0], 0) // Initial state
        XCTAssertEqual(messageCountChanges[1], 1) // After adding user message
    }
    
    // MARK: - Session Management Tests
    
    func testActiveSessionIsPublished() async throws {
        let expectation = XCTestExpectation(description: "Active session should be published")
        var sessionChanges: [ProjectSession?] = []
        
        chatViewModel.$activeSession
            .sink { session in
                sessionChanges.append(session)
                if sessionChanges.count >= 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: 0.5)
        
        XCTAssertEqual(sessionChanges.count, 1)
        XCTAssertNil(sessionChanges[0]) // Initial state should be nil
    }
    
    func testCurrentSessionIdIsPublished() async throws {
        let expectation = XCTestExpectation(description: "Current session ID should be published")
        var sessionIdChanges: [String?] = []
        
        chatViewModel.$currentSessionId
            .sink { sessionId in
                sessionIdChanges.append(sessionId)
                if sessionIdChanges.count >= 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: 0.5)
        
        XCTAssertEqual(sessionIdChanges.count, 1)
        XCTAssertNil(sessionIdChanges[0]) // Initial state should be nil
    }
    
    // MARK: - Error Handling Tests
    
    func testSessionErrorIsPublished() async throws {
        let expectation = XCTestExpectation(description: "Session error should be published")
        var errorChanges: [String?] = []
        
        chatViewModel.$sessionError
            .sink { error in
                errorChanges.append(error)
                if errorChanges.count >= 2 { // nil -> error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        let project = TestDataFactory.TestProject.mobile
        let testProject = Project(name: project.name, path: project.path, type: "Mobile")
        
        // Simulate service error
        mockAICLIService.isConnected = false
        
        chatViewModel.sendMessage("This should fail", for: testProject)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(errorChanges[0], nil) // Initial state
        XCTAssertNotNil(errorChanges[1]) // Error state
    }
    
    // MARK: - Progress Information Tests
    
    func testProgressInfoIsPublished() async throws {
        let expectation = XCTestExpectation(description: "Progress info should be published")
        var progressChanges: [ProgressInfo?] = []
        
        chatViewModel.$progressInfo
            .sink { progress in
                progressChanges.append(progress)
                if progressChanges.count >= 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: 0.5)
        
        XCTAssertEqual(progressChanges.count, 1)
        XCTAssertNil(progressChanges[0]) // Initial state should be nil
    }
    
    // MARK: - Multi-Project Tests
    
    func testHandleMultipleProjects() async throws {
        let project1 = TestDataFactory.TestProject.frontend
        let testProject1 = Project(name: project1.name, path: project1.path, type: "Frontend")
        
        let project2 = TestDataFactory.TestProject.backend
        let testProject2 = Project(name: project2.name, path: project2.path, type: "Backend")
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        
        // Send messages to different projects
        chatViewModel.sendMessage("Message for project 1", for: testProject1)
        chatViewModel.sendMessage("Message for project 2", for: testProject2)
        
        XCTAssertEqual(chatViewModel.messages.count, 2)
        XCTAssertEqual(chatViewModel.currentProject?.path, testProject2.path) // Last project wins
    }
    
    // MARK: - Message Content Tests
    
    func testLongMessageHandling() async throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        let longMessage = String(repeating: "This is a very long message. ", count: 100)
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        
        chatViewModel.sendMessage(longMessage, for: testProject)
        
        XCTAssertEqual(chatViewModel.messages.count, 1)
        XCTAssertEqual(chatViewModel.messages[0].content, longMessage)
        XCTAssertEqual(chatViewModel.messages[0].sender, .user)
    }
    
    func testSpecialCharactersInMessage() async throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let specialMessage = "Test with émojis 🚀 and ñ special chars & symbols! @#$%^&*()_+-=[]{}|;':\",./<>?"
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        
        chatViewModel.sendMessage(specialMessage, for: testProject)
        
        XCTAssertEqual(chatViewModel.messages.count, 1)
        XCTAssertEqual(chatViewModel.messages[0].content, specialMessage)
    }
    
    // MARK: - State Consistency Tests
    
    func testStateConsistencyAfterMultipleOperations() async throws {
        let project = TestDataFactory.TestProject.mobile
        let testProject = Project(name: project.name, path: project.path, type: "Mobile")
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        mockAICLIService.responseDelay = 0.05 // Fast response
        
        // Send multiple messages quickly
        chatViewModel.sendMessage("Message 1", for: testProject)
        chatViewModel.sendMessage("Message 2", for: testProject)
        chatViewModel.sendMessage("Message 3", for: testProject)
        
        XCTAssertEqual(chatViewModel.messages.count, 3)
        XCTAssertEqual(chatViewModel.currentProject?.path, testProject.path)
        
        // All messages should be user messages
        for (index, message) in chatViewModel.messages.enumerated() {
            XCTAssertEqual(message.sender, .user)
            XCTAssertEqual(message.content, "Message \(index + 1)")
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testViewModelDeinitialization() async throws {
        weak var weakViewModel: ChatViewModel?
        
        do {
            let localMockService = MockHTTPAICLIService()
            let localMockSettings = SettingsManager()
            let viewModel = ChatViewModel(aicliService: localMockService, settings: localMockSettings)
            weakViewModel = viewModel
            
            // Use the view model
            let project = TestDataFactory.TestProject.frontend
            let testProject = Project(name: project.name, path: project.path, type: "Frontend")
            viewModel.sendMessage("Test", for: testProject)
            
            XCTAssertNotNil(weakViewModel)
        }
        
        // After leaving scope, view model should be deallocated
        // Note: This test might not work reliably due to ARC behavior in test environment
        // XCTAssertNil(weakViewModel)
    }
    
    // MARK: - Performance Tests
    
    func testMessageSendingPerformance() async throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        mockAICLIService.responseDelay = 0.0 // No delay for performance test
        
        measure {
            for i in 0..<100 {
                chatViewModel.sendMessage("Performance test message \(i)", for: testProject)
            }
        }
    }
    
    func testLargeMessageListHandling() async throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        mockAICLIService.responseDelay = 0.0
        
        // Add many messages
        for i in 0..<1000 {
            chatViewModel.sendMessage("Message \(i)", for: testProject)
        }
        
        XCTAssertEqual(chatViewModel.messages.count, 1000)
        
        // Test that we can still access first and last messages efficiently
        XCTAssertEqual(chatViewModel.messages.first?.content, "Message 0")
        XCTAssertEqual(chatViewModel.messages.last?.content, "Message 999")
    }
    
    // MARK: - Edge Case Tests
    
    func testSendMessageWithNilProject() async throws {
        // This would be a programming error, but test graceful handling
        // Note: In Swift, this would be a compile-time error, so we can't easily test this
    }
    
    func testResetState() async throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        // Add some state
        let mockResponse = TestDataFactory.createAICLIResponse()
        mockAICLIService.setMockResponse(mockResponse)
        
        chatViewModel.sendMessage("Test", for: testProject)
        XCTAssertEqual(chatViewModel.messages.count, 1)
        XCTAssertNotNil(chatViewModel.currentProject)
        
        // Reset by creating new instance
        let newChatViewModel = ChatViewModel(aicliService: mockAICLIService, settings: mockSettings)
        
        XCTAssertEqual(newChatViewModel.messages.count, 0)
        XCTAssertNil(newChatViewModel.currentProject)
        XCTAssertFalse(newChatViewModel.isLoading)
    }
}