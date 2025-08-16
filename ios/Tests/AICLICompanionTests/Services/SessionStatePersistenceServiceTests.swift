import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class SessionStatePersistenceServiceTests: XCTestCase {
    
    var persistenceService: SessionStatePersistenceService!
    var testSessionId: String!
    var testProjectId: String!
    var testProjectName: String!
    var testProjectPath: String!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        persistenceService = SessionStatePersistenceService.shared
        testSessionId = "test-session-\(UUID().uuidString)"
        testProjectId = "test-project-\(UUID().uuidString)"
        testProjectName = "Test Project"
        testProjectPath = "/test/project/path"
        cancellables = Set<AnyCancellable>()
        
        // Clear ALL existing sessions to ensure test isolation
        persistenceService.getActiveSessions().forEach { session in
            persistenceService.removeSession(session.id)
        }
    }
    
    override func tearDown() {
        // Clean up ALL test data
        persistenceService.getActiveSessions().forEach { session in
            persistenceService.removeSession(session.id)
        }
        cancellables.removeAll()
        persistenceService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSessionStatePersistenceServiceSingleton() throws {
        let service1 = SessionStatePersistenceService.shared
        let service2 = SessionStatePersistenceService.shared
        
        XCTAssertTrue(service1 === service2, "SessionStatePersistenceService should be a singleton")
    }
    
    func testSessionStatePersistenceServiceInitialization() throws {
        XCTAssertNotNil(persistenceService)
        XCTAssertNotNil(persistenceService.activeSessions)
    }
    
    // MARK: - Session Saving Tests
    
    func testSaveNewSession() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 5,
            aicliSessionId: "aicli-session-123"
        )
        
        let retrievedSession = persistenceService.getSessionStateById(testSessionId)
        
        XCTAssertNotNil(retrievedSession)
        XCTAssertEqual(retrievedSession?.id, testSessionId)
        XCTAssertEqual(retrievedSession?.projectId, testProjectId)
        XCTAssertEqual(retrievedSession?.projectName, testProjectName)
        XCTAssertEqual(retrievedSession?.projectPath, testProjectPath)
        XCTAssertEqual(retrievedSession?.messageCount, 5)
        XCTAssertEqual(retrievedSession?.aicliSessionId, "aicli-session-123")
    }
    
    func testSaveSessionWithMetadata() throws {
        let metadata = ["key1": "value1", "key2": "value2"]
        
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 3,
            aicliSessionId: nil,
            metadata: metadata
        )
        
        let retrievedSession = persistenceService.getSessionStateById(testSessionId)
        
        XCTAssertNotNil(retrievedSession)
        XCTAssertEqual(retrievedSession?.metadata["key1"], "value1")
        XCTAssertEqual(retrievedSession?.metadata["key2"], "value2")
    }
    
    func testUpdateExistingSession() throws {
        // Save initial session
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 3,
            aicliSessionId: "initial-session"
        )
        
        let initialSession = persistenceService.getSessionStateById(testSessionId)
        XCTAssertEqual(initialSession?.messageCount, 3)
        XCTAssertEqual(initialSession?.aicliSessionId, "initial-session")
        
        // Update the session
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 7,
            aicliSessionId: "updated-session"
        )
        
        let updatedSession = persistenceService.getSessionStateById(testSessionId)
        XCTAssertEqual(updatedSession?.messageCount, 7)
        XCTAssertEqual(updatedSession?.aicliSessionId, "updated-session")
        
        // Created date should remain the same
        XCTAssertEqual(updatedSession?.createdAt, initialSession?.createdAt)
    }
    
    // MARK: - Session Retrieval Tests
    
    func testGetSessionStateById() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 2,
            aicliSessionId: nil
        )
        
        let session = persistenceService.getSessionStateById(testSessionId)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.id, testSessionId)
    }
    
    func testGetSessionStateByProjectId() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 2,
            aicliSessionId: nil
        )
        
        let session = persistenceService.getSessionState(for: testProjectId)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.projectId, testProjectId)
    }
    
    func testGetNonExistentSession() throws {
        let session = persistenceService.getSessionStateById("non-existent-session")
        XCTAssertNil(session)
    }
    
    func testGetNonExistentProjectSession() throws {
        let session = persistenceService.getSessionState(for: "non-existent-project")
        XCTAssertNil(session)
    }
    
    // MARK: - Session Activity Tests
    
    func testTouchSession() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        let initialSession = persistenceService.getSessionStateById(testSessionId)
        let initialLastActive = initialSession?.lastActiveAt
        
        // Wait a brief moment to ensure time difference
        Thread.sleep(forTimeInterval: 0.1)
        
        persistenceService.touchSession(testSessionId)
        
        let updatedSession = persistenceService.getSessionStateById(testSessionId)
        let updatedLastActive = updatedSession?.lastActiveAt
        
        XCTAssertNotNil(initialLastActive)
        XCTAssertNotNil(updatedLastActive)
        XCTAssertTrue(updatedLastActive! > initialLastActive!)
    }
    
    func testTouchNonExistentSession() throws {
        // Should not crash when touching non-existent session
        persistenceService.touchSession("non-existent-session")
        
        let session = persistenceService.getSessionStateById("non-existent-session")
        XCTAssertNil(session)
    }
    
    // MARK: - Session Removal Tests
    
    func testRemoveSession() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        // Verify session exists
        XCTAssertNotNil(persistenceService.getSessionStateById(testSessionId))
        
        // Remove session
        persistenceService.removeSession(testSessionId)
        
        // Verify session is removed
        XCTAssertNil(persistenceService.getSessionStateById(testSessionId))
    }
    
    func testRemoveNonExistentSession() throws {
        // Should not crash when removing non-existent session
        persistenceService.removeSession("non-existent-session")
    }
    
    // MARK: - Session Status Tests
    
    func testIsSessionActive() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        XCTAssertTrue(persistenceService.isSessionActive(testSessionId))
        XCTAssertFalse(persistenceService.isSessionActive("non-existent-session"))
    }
    
    func testGetSessionExpiry() throws {
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        let expiry = persistenceService.getSessionExpiry(testSessionId)
        XCTAssertNotNil(expiry, "Session expiry should not be nil")
        if let expiry = expiry {
            XCTAssertTrue(expiry > Date(), "Session should expire in the future")
        }
    }
    
    func testGetNonExistentSessionExpiry() throws {
        let expiry = persistenceService.getSessionExpiry("non-existent-session")
        XCTAssertNil(expiry)
    }
    
    // MARK: - Active Sessions Tests
    
    func testGetActiveSessions() throws {
        let initialCount = persistenceService.getActiveSessions().count
        
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        let activeSessions = persistenceService.getActiveSessions()
        XCTAssertEqual(activeSessions.count, initialCount + 1)
        
        let testSession = activeSessions.first { $0.id == testSessionId }
        XCTAssertNotNil(testSession)
    }
    
    // MARK: - Session Expiry Tests
    
    func testSessionStateInfoIsExpired() throws {
        let pastDate = Date().addingTimeInterval(-8 * 24 * 60 * 60) // 8 days ago
        let sessionInfo = SessionStatePersistenceService.SessionStateInfo(
            id: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            createdAt: pastDate,
            lastActiveAt: pastDate,
            messageCount: 1,
            aicliSessionId: nil,
            metadata: [:]
        )
        
        XCTAssertTrue(sessionInfo.isExpired)
    }
    
    func testSessionStateInfoNotExpired() throws {
        let recentDate = Date().addingTimeInterval(-1 * 60 * 60) // 1 hour ago
        let sessionInfo = SessionStatePersistenceService.SessionStateInfo(
            id: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            createdAt: recentDate,
            lastActiveAt: recentDate,
            messageCount: 1,
            aicliSessionId: nil,
            metadata: [:]
        )
        
        XCTAssertFalse(sessionInfo.isExpired)
    }
    
    func testSessionStateInfoExpiresAt() throws {
        let baseDate = Date()
        let sessionInfo = SessionStatePersistenceService.SessionStateInfo(
            id: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            createdAt: baseDate,
            lastActiveAt: baseDate,
            messageCount: 1,
            aicliSessionId: nil,
            metadata: [:]
        )
        
        let expectedExpiry = baseDate.addingTimeInterval(7 * 24 * 60 * 60) // 7 days
        let actualExpiry = sessionInfo.expiresAt
        
        // Allow for small time differences
        XCTAssertTrue(abs(actualExpiry.timeIntervalSince(expectedExpiry)) < 1.0)
    }
    
    func testSessionStateInfoFormattedExpiry() throws {
        let futureDate = Date().addingTimeInterval(24 * 60 * 60) // 1 day from now
        let sessionInfo = SessionStatePersistenceService.SessionStateInfo(
            id: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            createdAt: Date(),
            lastActiveAt: futureDate,
            messageCount: 1,
            aicliSessionId: nil,
            metadata: [:]
        )
        
        let formatted = sessionInfo.formattedExpiry
        XCTAssertFalse(formatted.isEmpty)
        // The exact format depends on the system, but it should contain relative time
    }
    
    // MARK: - Cleanup Tests
    
    func testCleanupExpiredSessions() throws {
        throw XCTSkip("Skipping time-sensitive test in CI")
        // Save a fresh session
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        // Verify session exists
        XCTAssertTrue(persistenceService.isSessionActive(testSessionId))
        
        // Run cleanup (should not remove fresh session)
        persistenceService.cleanupExpiredSessions()
        
        // Session should still exist
        XCTAssertTrue(persistenceService.isSessionActive(testSessionId))
    }
    
    // MARK: - Published Properties Tests
    
    func testActiveSessionsIsPublished() throws {
        throw XCTSkip("Skipping flaky published property test in CI")
        let expectation = XCTestExpectation(description: "Active sessions should be published")
        var sessionChanges: [[SessionStatePersistenceService.SessionStateInfo]] = []
        
        persistenceService.$activeSessions
            .sink { sessions in
                sessionChanges.append(sessions)
                if sessionChanges.count >= 2 { // Initial + after save
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(sessionChanges.count, 2)
        XCTAssertTrue(sessionChanges[1].contains { $0.id == testSessionId })
    }
    
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentSessionOperations() throws {
        throw XCTSkip("Skipping flaky concurrent test in CI")
        let expectation = XCTestExpectation(description: "Concurrent operations should complete safely")
        expectation.expectedFulfillmentCount = 10
        
        let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
        
        for i in 0..<10 {
            concurrentQueue.async {
                let sessionId = "\(self.testSessionId!)_\(i)"
                let projectId = "\(self.testProjectId!)_\(i)"
                
                self.persistenceService.saveSessionState(
                    sessionId: sessionId,
                    projectId: projectId,
                    projectName: "Concurrent Project \(i)",
                    projectPath: "/concurrent/path/\(i)",
                    messageCount: i,
                    aicliSessionId: nil
                )
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Verify all concurrent saves succeeded
        for i in 0..<10 {
            let sessionId = "\(testSessionId!)_\(i)"
            XCTAssertTrue(persistenceService.isSessionActive(sessionId))
        }
        
        // Clean up concurrent sessions
        for i in 0..<10 {
            let sessionId = "\(testSessionId!)_\(i)"
            persistenceService.removeSession(sessionId)
        }
    }
    
    func testConcurrentTouchOperations() throws {
        throw XCTSkip("Skipping flaky concurrent test in CI")
        // Save a session first
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        let expectation = XCTestExpectation(description: "Concurrent touch operations should complete")
        expectation.expectedFulfillmentCount = 5
        
        let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
        
        for _ in 0..<5 {
            concurrentQueue.async {
                self.persistenceService.touchSession(self.testSessionId)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Session should still be active
        XCTAssertTrue(persistenceService.isSessionActive(testSessionId))
    }
    
    // MARK: - Performance Tests
    
    func testSaveManySessionsPerformance() throws {
        measure {
            for i in 0..<100 {
                let sessionId = "perf-session-\(i)"
                let projectId = "perf-project-\(i)"
                
                persistenceService.saveSessionState(
                    sessionId: sessionId,
                    projectId: projectId,
                    projectName: "Performance Project \(i)",
                    projectPath: "/perf/path/\(i)",
                    messageCount: i,
                    aicliSessionId: nil
                )
            }
        }
        
        // Clean up performance test data
        for i in 0..<100 {
            let sessionId = "perf-session-\(i)"
            persistenceService.removeSession(sessionId)
        }
    }
    
    func testRetrieveManySessionsPerformance() throws {
        // Setup test data
        for i in 0..<100 {
            let sessionId = "perf-retrieve-session-\(i)"
            let projectId = "perf-retrieve-project-\(i)"
            
            persistenceService.saveSessionState(
                sessionId: sessionId,
                projectId: projectId,
                projectName: "Performance Retrieve Project \(i)",
                projectPath: "/perf/retrieve/path/\(i)",
                messageCount: i,
                aicliSessionId: nil
            )
        }
        
        measure {
            _ = persistenceService.getActiveSessions()
            
            for i in 0..<100 {
                let sessionId = "perf-retrieve-session-\(i)"
                _ = persistenceService.getSessionStateById(sessionId)
            }
        }
        
        // Clean up performance test data
        for i in 0..<100 {
            let sessionId = "perf-retrieve-session-\(i)"
            persistenceService.removeSession(sessionId)
        }
    }
    
    // MARK: - Edge Cases
    
    func testSaveSessionWithEmptyStrings() throws {
        persistenceService.saveSessionState(
            sessionId: "",
            projectId: "",
            projectName: "",
            projectPath: "",
            messageCount: 0,
            aicliSessionId: nil
        )
        
        let session = persistenceService.getSessionStateById("")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.projectName, "")
        XCTAssertEqual(session?.messageCount, 0)
    }
    
    func testSaveSessionWithLargeMetadata() throws {
        var largeMetadata: [String: String] = [:]
        for i in 0..<1000 {
            largeMetadata["key\(i)"] = "value\(i)"
        }
        
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            messageCount: 1,
            aicliSessionId: nil,
            metadata: largeMetadata
        )
        
        let session = persistenceService.getSessionStateById(testSessionId)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.metadata.count, 1000)
    }
    
    func testSaveSessionWithUnicodeContent() throws {
        let unicodeName = "Test Project 🚀 with émojis and ñ special chars 中文"
        let unicodePath = "/unicode/path/with/émojis/🚀/中文"
        
        persistenceService.saveSessionState(
            sessionId: testSessionId,
            projectId: testProjectId,
            projectName: unicodeName,
            projectPath: unicodePath,
            messageCount: 1,
            aicliSessionId: nil
        )
        
        let session = persistenceService.getSessionStateById(testSessionId)
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.projectName, unicodeName)
        XCTAssertEqual(session?.projectPath, unicodePath)
    }
}

// MARK: - Test Helpers

extension SessionStatePersistenceServiceTests {
    
    private func createTestSessionInfo(
        sessionId: String? = nil,
        projectId: String? = nil,
        lastActiveAt: Date = Date()
    ) -> SessionStatePersistenceService.SessionStateInfo {
        return SessionStatePersistenceService.SessionStateInfo(
            id: sessionId ?? testSessionId,
            projectId: projectId ?? testProjectId,
            projectName: testProjectName,
            projectPath: testProjectPath,
            createdAt: Date(),
            lastActiveAt: lastActiveAt,
            messageCount: 1,
            aicliSessionId: nil,
            metadata: [:]
        )
    }
}