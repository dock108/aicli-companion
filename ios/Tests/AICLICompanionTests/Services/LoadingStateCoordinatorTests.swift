import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class LoadingStateCoordinatorTests: XCTestCase {
    var coordinator: LoadingStateCoordinator!
    
    override func setUp() {
        super.setUp()
        coordinator = LoadingStateCoordinator.shared
        coordinator.clearAllLoading() // Reset state for each test
    }
    
    override func tearDown() {
        coordinator.clearAllLoading() // Clean up after each test
        super.tearDown()
    }
    
    // MARK: - Basic Loading State Tests
    
    func testInitialState() {
        XCTAssertFalse(coordinator.isAnyLoading)
        XCTAssertTrue(coordinator.activeLoadingStates.isEmpty)
        XCTAssertTrue(coordinator.projectLoadingStates.isEmpty)
        XCTAssertTrue(coordinator.loadingTimeouts.isEmpty)
    }
    
    func testStartAndStopLoading() {
        let loadingType = LoadingStateCoordinator.LoadingType.chatMessage
        
        // Initially not loading
        XCTAssertFalse(coordinator.isLoading(loadingType))
        XCTAssertFalse(coordinator.isAnyLoading)
        
        // Start loading
        coordinator.startLoading(loadingType)
        XCTAssertTrue(coordinator.isLoading(loadingType))
        XCTAssertTrue(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 1)
        
        // Stop loading
        coordinator.stopLoading(loadingType)
        XCTAssertFalse(coordinator.isLoading(loadingType))
        XCTAssertFalse(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 0)
    }
    
    func testMultipleLoadingTypes() {
        let type1 = LoadingStateCoordinator.LoadingType.chatMessage
        let type2 = LoadingStateCoordinator.LoadingType.connection
        let type3 = LoadingStateCoordinator.LoadingType.fileOperation
        
        // Start multiple loading types
        coordinator.startLoading(type1)
        coordinator.startLoading(type2)
        coordinator.startLoading(type3)
        
        XCTAssertTrue(coordinator.isLoading(type1))
        XCTAssertTrue(coordinator.isLoading(type2))
        XCTAssertTrue(coordinator.isLoading(type3))
        XCTAssertTrue(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 3)
        
        // Stop one type
        coordinator.stopLoading(type2)
        XCTAssertTrue(coordinator.isLoading(type1))
        XCTAssertFalse(coordinator.isLoading(type2))
        XCTAssertTrue(coordinator.isLoading(type3))
        XCTAssertTrue(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 2)
        
        // Stop remaining types
        coordinator.stopLoading(type1)
        coordinator.stopLoading(type3)
        XCTAssertFalse(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 0)
    }
    
    // MARK: - Project Loading Tests
    
    func testProjectLoading() {
        let projectPath = "/Users/test/project"
        
        // Initially not loading
        XCTAssertFalse(coordinator.isProjectLoading(projectPath))
        XCTAssertFalse(coordinator.isAnyLoading)
        
        // Start project loading
        coordinator.startProjectLoading(projectPath)
        XCTAssertTrue(coordinator.isProjectLoading(projectPath))
        XCTAssertTrue(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.projectLoadingStates[projectPath], true)
        
        // Stop project loading
        coordinator.stopProjectLoading(projectPath)
        XCTAssertFalse(coordinator.isProjectLoading(projectPath))
        XCTAssertFalse(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.projectLoadingStates[projectPath], false)
    }
    
    func testMultipleProjectLoading() {
        let project1 = "/Users/test/project1"
        let project2 = "/Users/test/project2"
        let project3 = "/Users/test/project3"
        
        // Start multiple project loading
        coordinator.startProjectLoading(project1)
        coordinator.startProjectLoading(project2)
        coordinator.startProjectLoading(project3)
        
        XCTAssertTrue(coordinator.isProjectLoading(project1))
        XCTAssertTrue(coordinator.isProjectLoading(project2))
        XCTAssertTrue(coordinator.isProjectLoading(project3))
        XCTAssertTrue(coordinator.isAnyLoading)
        
        // Stop one project
        coordinator.stopProjectLoading(project2)
        XCTAssertTrue(coordinator.isProjectLoading(project1))
        XCTAssertFalse(coordinator.isProjectLoading(project2))
        XCTAssertTrue(coordinator.isProjectLoading(project3))
        XCTAssertTrue(coordinator.isAnyLoading)
        
        // Stop remaining projects
        coordinator.stopProjectLoading(project1)
        coordinator.stopProjectLoading(project3)
        XCTAssertFalse(coordinator.isAnyLoading)
    }
    
    // MARK: - Mixed Loading Tests
    
    func testMixedLoadingTypes() {
        let loadingType = LoadingStateCoordinator.LoadingType.connection
        let projectPath = "/Users/test/mixed-project"
        
        // Start both types
        coordinator.startLoading(loadingType)
        coordinator.startProjectLoading(projectPath)
        
        XCTAssertTrue(coordinator.isLoading(loadingType))
        XCTAssertTrue(coordinator.isProjectLoading(projectPath))
        XCTAssertTrue(coordinator.isAnyLoading)
        
        // Stop one type
        coordinator.stopLoading(loadingType)
        XCTAssertFalse(coordinator.isLoading(loadingType))
        XCTAssertTrue(coordinator.isProjectLoading(projectPath))
        XCTAssertTrue(coordinator.isAnyLoading) // Still loading project
        
        // Stop remaining type
        coordinator.stopProjectLoading(projectPath)
        XCTAssertFalse(coordinator.isAnyLoading)
    }
    
    // MARK: - Timeout Tests
    
    func testLoadingWithTimeout() throws {
        let loadingType = LoadingStateCoordinator.LoadingType.authentication
        let expectation = XCTestExpectation(description: "Loading timeout")
        
        // Start loading with short timeout
        coordinator.startLoading(loadingType, timeout: 0.1)
        XCTAssertTrue(coordinator.isLoading(loadingType))
        
        // Wait for timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Should have timed out and stopped loading
            XCTAssertFalse(self.coordinator.isLoading(loadingType))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testProjectLoadingWithTimeout() throws {
        let projectPath = "/Users/test/timeout-project"
        let expectation = XCTestExpectation(description: "Project timeout")
        
        // Start project loading with short timeout
        coordinator.startProjectLoading(projectPath, timeout: 0.1)
        XCTAssertTrue(coordinator.isProjectLoading(projectPath))
        
        // Wait for timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Should have timed out and stopped loading
            XCTAssertFalse(self.coordinator.isProjectLoading(projectPath))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testTimeoutClearedOnManualStop() {
        let loadingType = LoadingStateCoordinator.LoadingType.qrScanning
        
        // Start loading with timeout
        coordinator.startLoading(loadingType, timeout: 10.0) // Long timeout
        XCTAssertTrue(coordinator.isLoading(loadingType))
        XCTAssertEqual(coordinator.loadingTimeouts.count, 1)
        
        // Stop manually before timeout
        coordinator.stopLoading(loadingType)
        XCTAssertFalse(coordinator.isLoading(loadingType))
        XCTAssertEqual(coordinator.loadingTimeouts.count, 0) // Timeout should be cleared
    }
    
    // MARK: - Clear All Loading Tests
    
    func testClearAllLoading() {
        let type1 = LoadingStateCoordinator.LoadingType.chatMessage
        let type2 = LoadingStateCoordinator.LoadingType.connection
        let project1 = "/Users/test/project1"
        let project2 = "/Users/test/project2"
        
        // Start multiple loading states
        coordinator.startLoading(type1)
        coordinator.startLoading(type2)
        coordinator.startProjectLoading(project1)
        coordinator.startProjectLoading(project2)
        
        XCTAssertTrue(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 2)
        XCTAssertEqual(coordinator.projectLoadingStates.count, 2)
        
        // Clear all loading
        coordinator.clearAllLoading()
        
        XCTAssertFalse(coordinator.isAnyLoading)
        XCTAssertEqual(coordinator.activeLoadingStates.count, 0)
        XCTAssertEqual(coordinator.projectLoadingStates.count, 0)
        XCTAssertEqual(coordinator.loadingTimeouts.count, 0)
        
        // Verify individual checks
        XCTAssertFalse(coordinator.isLoading(type1))
        XCTAssertFalse(coordinator.isLoading(type2))
        XCTAssertFalse(coordinator.isProjectLoading(project1))
        XCTAssertFalse(coordinator.isProjectLoading(project2))
    }
    
    // MARK: - Loading Messages Tests
    
    func testLoadingMessages() {
        let testCases: [(LoadingStateCoordinator.LoadingType, String)] = [
            (.chatMessage, "Sending message to Claude..."),
            (.projectSelection, "Loading projects..."),
            (.qrScanning, "Scanning QR code..."),
            (.connection, "Connecting to server..."),
            (.fileOperation, "Processing files..."),
            (.cloudKitSync, "Syncing to iCloud..."),
            (.authentication, "Authenticating..."),
            (.projectAnalysis, "Analyzing project...")
        ]
        
        for (loadingType, expectedMessage) in testCases {
            let actualMessage = coordinator.getLoadingMessage(for: loadingType)
            XCTAssertEqual(actualMessage, expectedMessage, "Message mismatch for \(loadingType)")
        }
    }
    
    // MARK: - Convenience Methods Tests
    
    func testChatLoadingConvenience() {
        let projectPath = "/Users/test/chat-project"
        
        // Test start chat loading
        coordinator.startChatLoading(for: projectPath)
        XCTAssertTrue(coordinator.isChatLoading(for: projectPath))
        XCTAssertTrue(coordinator.isProjectLoading(projectPath))
        XCTAssertTrue(coordinator.isAnyLoading)
        
        // Test stop chat loading
        coordinator.stopChatLoading(for: projectPath)
        XCTAssertFalse(coordinator.isChatLoading(for: projectPath))
        XCTAssertFalse(coordinator.isProjectLoading(projectPath))
        XCTAssertFalse(coordinator.isAnyLoading)
    }
    
    func testChatLoadingWithTimeout() throws {
        let projectPath = "/Users/test/chat-timeout-project"
        let expectation = XCTestExpectation(description: "Chat loading timeout")
        
        // Start chat loading with short timeout
        coordinator.startChatLoading(for: projectPath, timeout: 0.1)
        XCTAssertTrue(coordinator.isChatLoading(for: projectPath))
        
        // Wait for timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertFalse(self.coordinator.isChatLoading(for: projectPath))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Migration Helper Tests
    
    func testMigrateFromLegacyState() {
        let loadingType = LoadingStateCoordinator.LoadingType.fileOperation
        
        // Initially not loading
        XCTAssertFalse(coordinator.isLoading(loadingType))
        
        // Migrate from legacy true state
        coordinator.migrateFromLegacyState(true, type: loadingType)
        XCTAssertTrue(coordinator.isLoading(loadingType))
        
        // Migrate from legacy false state
        coordinator.migrateFromLegacyState(false, type: loadingType)
        XCTAssertFalse(coordinator.isLoading(loadingType))
    }
    
    func testMigrateFromLegacyStateNoChange() {
        let loadingType = LoadingStateCoordinator.LoadingType.cloudKitSync
        
        // Start loading normally
        coordinator.startLoading(loadingType)
        XCTAssertTrue(coordinator.isLoading(loadingType))
        
        // Try to migrate from already matching state (should do nothing)
        coordinator.migrateFromLegacyState(true, type: loadingType)
        XCTAssertTrue(coordinator.isLoading(loadingType)) // Still loading, no change
        
        // Stop loading normally
        coordinator.stopLoading(loadingType)
        XCTAssertFalse(coordinator.isLoading(loadingType))
        
        // Try to migrate from already matching state (should do nothing)
        coordinator.migrateFromLegacyState(false, type: loadingType)
        XCTAssertFalse(coordinator.isLoading(loadingType)) // Still not loading, no change
    }
    
    // MARK: - Edge Cases and Error Handling Tests
    
    func testStartAlreadyLoadingType() {
        let loadingType = LoadingStateCoordinator.LoadingType.projectSelection
        
        // Start loading
        coordinator.startLoading(loadingType)
        XCTAssertTrue(coordinator.isLoading(loadingType))
        XCTAssertEqual(coordinator.activeLoadingStates.count, 1)
        
        // Try to start again (should be ignored)
        coordinator.startLoading(loadingType)
        XCTAssertTrue(coordinator.isLoading(loadingType))
        XCTAssertEqual(coordinator.activeLoadingStates.count, 1) // No duplicate
    }
    
    func testStopNotLoadingType() {
        let loadingType = LoadingStateCoordinator.LoadingType.projectAnalysis
        
        // Try to stop loading when not currently loading (should handle gracefully)
        XCTAssertFalse(coordinator.isLoading(loadingType))
        coordinator.stopLoading(loadingType) // Should not crash
        XCTAssertFalse(coordinator.isLoading(loadingType))
    }
    
    func testStopNotLoadingProject() {
        let projectPath = "/Users/test/not-loading-project"
        
        // Try to stop project loading when not currently loading
        XCTAssertFalse(coordinator.isProjectLoading(projectPath))
        coordinator.stopProjectLoading(projectPath) // Should not crash
        XCTAssertFalse(coordinator.isProjectLoading(projectPath))
    }
    
    func testEmptyProjectPath() {
        let emptyPath = ""
        
        // Should handle empty project path gracefully
        coordinator.startProjectLoading(emptyPath)
        XCTAssertTrue(coordinator.isProjectLoading(emptyPath))
        
        coordinator.stopProjectLoading(emptyPath)
        XCTAssertFalse(coordinator.isProjectLoading(emptyPath))
    }
    
    // MARK: - LoadingType Enum Tests
    
    func testLoadingTypeCaseIterable() {
        let allTypes = LoadingStateCoordinator.LoadingType.allCases
        XCTAssertEqual(allTypes.count, 8)
        
        let expectedTypes: [LoadingStateCoordinator.LoadingType] = [
            .chatMessage, .projectSelection, .qrScanning, .connection,
            .fileOperation, .cloudKitSync, .authentication, .projectAnalysis
        ]
        
        for expectedType in expectedTypes {
            XCTAssertTrue(allTypes.contains(expectedType), "Missing type: \(expectedType)")
        }
    }
    
    func testLoadingTypeRawValues() {
        let testCases: [(LoadingStateCoordinator.LoadingType, String)] = [
            (.chatMessage, "chat_message"),
            (.projectSelection, "project_selection"),
            (.qrScanning, "qr_scanning"),
            (.connection, "connection"),
            (.fileOperation, "file_operation"),
            (.cloudKitSync, "cloudkit_sync"),
            (.authentication, "authentication"),
            (.projectAnalysis, "project_analysis")
        ]
        
        for (loadingType, expectedRawValue) in testCases {
            XCTAssertEqual(loadingType.rawValue, expectedRawValue)
        }
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceWithManyOperations() {
        let projectPaths = (0..<100).map { "/Users/test/project\($0)" }
        let loadingTypes = LoadingStateCoordinator.LoadingType.allCases
        
        measure {
            // Start many operations
            for projectPath in projectPaths {
                coordinator.startProjectLoading(projectPath)
            }
            
            for loadingType in loadingTypes {
                coordinator.startLoading(loadingType)
            }
            
            // Check states
            XCTAssertTrue(coordinator.isAnyLoading)
            
            // Stop all operations
            for projectPath in projectPaths {
                coordinator.stopProjectLoading(projectPath)
            }
            
            for loadingType in loadingTypes {
                coordinator.stopLoading(loadingType)
            }
            
            XCTAssertFalse(coordinator.isAnyLoading)
        }
    }
    
    func testClearAllPerformance() {
        let projectPaths = (0..<50).map { "/Users/test/project\($0)" }
        let loadingTypes = LoadingStateCoordinator.LoadingType.allCases
        
        // Setup many loading states
        for projectPath in projectPaths {
            coordinator.startProjectLoading(projectPath)
        }
        
        for loadingType in loadingTypes {
            coordinator.startLoading(loadingType)
        }
        
        XCTAssertTrue(coordinator.isAnyLoading)
        
        measure {
            coordinator.clearAllLoading()
            XCTAssertFalse(coordinator.isAnyLoading)
            
            // Setup again for next iteration
            for projectPath in projectPaths {
                coordinator.startProjectLoading(projectPath)
            }
            
            for loadingType in loadingTypes {
                coordinator.startLoading(loadingType)
            }
        }
    }
    
    // MARK: - Observable Object Tests
    
    func testObservableObjectUpdates() {
        let expectation = XCTestExpectation(description: "ObjectWillChange notification")
        expectation.expectedFulfillmentCount = 2 // Start and stop
        
        let cancellable = coordinator.objectWillChange.sink {
            expectation.fulfill()
        }
        
        coordinator.startLoading(.chatMessage)
        coordinator.stopLoading(.chatMessage)
        
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}
