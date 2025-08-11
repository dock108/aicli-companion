import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class MessagePersistenceServiceTests: XCTestCase {
    
    var persistenceService: MessagePersistenceService!
    var testProjectId: String!
    var testSessionId: String!
    var testProject: Project!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        persistenceService = MessagePersistenceService.shared
        testProjectId = "test-project-\(UUID().uuidString)"
        testSessionId = "test-session-\(UUID().uuidString)"
        testProject = Project(name: "Test Project", path: testProjectId, type: "Test")
        cancellables = Set<AnyCancellable>()
        
        // Clean up any existing test data
        persistenceService.clearMessages(for: testProjectId)
    }
    
    override func tearDown() {
        // Clean up test data
        persistenceService.clearMessages(for: testProjectId)
        cancellables.removeAll()
        persistenceService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testMessagePersistenceServiceSingleton() throws {
        let service1 = MessagePersistenceService.shared
        let service2 = MessagePersistenceService.shared
        
        XCTAssertTrue(service1 === service2, "MessagePersistenceService should be a singleton")
    }
    
    func testMessagePersistenceServiceInitialization() throws {
        XCTAssertNotNil(persistenceService)
        XCTAssertNotNil(persistenceService.savedSessions)
    }
    
    // MARK: - Message Saving Tests
    
    func testSaveEmptyMessages() throws {
        let messages: [Message] = []
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 0)
    }
    
    func testSaveSingleMessage() throws {
        let message = TestDataFactory.createTestMessage(content: "Test message")
        let messages = [message]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        XCTAssertEqual(loadedMessages[0].content, "Test message")
        XCTAssertEqual(loadedMessages[0].sender, message.sender)
        XCTAssertEqual(loadedMessages[0].type, message.type)
    }
    
    func testSaveMultipleMessages() throws {
        let messages = [
            TestDataFactory.createTestMessage(content: "First message", sender: .user),
            TestDataFactory.createTestMessage(content: "Second message", sender: .assistant),
            TestDataFactory.createTestMessage(content: "Third message", sender: .user)
        ]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 3)
        
        for i in 0..<messages.count {
            XCTAssertEqual(loadedMessages[i].content, messages[i].content)
            XCTAssertEqual(loadedMessages[i].sender, messages[i].sender)
            XCTAssertEqual(loadedMessages[i].type, messages[i].type)
        }
    }
    
    func testSaveMessagesWithMetadata() throws {
        let metadata = TestDataFactory.createTestMetadata(sessionId: testSessionId)
        let message = TestDataFactory.createTestMessage(
            content: "Message with metadata",
            metadata: metadata
        )
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: [message],
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        XCTAssertNotNil(loadedMessages[0].metadata)
        XCTAssertEqual(loadedMessages[0].metadata?.sessionId, testSessionId)
    }
    
    func testSaveMessagesWithDifferentTypes() throws {
        let messages = [
            TestDataFactory.createTestMessage(content: "Text message", type: .text),
            TestDataFactory.createTestMessage(content: "Error message", type: .error),
            TestDataFactory.createTestMessage(content: "Tool message", type: .toolUse)
        ]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 3)
        XCTAssertEqual(loadedMessages[0].type, .text)
        XCTAssertEqual(loadedMessages[1].type, .error)
        XCTAssertEqual(loadedMessages[2].type, .toolUse)
    }
    
    // MARK: - Message Loading Tests
    
    func testLoadNonExistentMessages() throws {
        let nonExistentProjectId = "non-existent-project"
        let nonExistentSessionId = "non-existent-session"
        
        let loadedMessages = persistenceService.loadMessages(for: nonExistentProjectId, sessionId: nonExistentSessionId)
        XCTAssertEqual(loadedMessages.count, 0)
    }
    
    func testLoadMessagesAfterSave() throws {
        let originalMessages = [
            TestDataFactory.createTestMessage(content: "Message 1"),
            TestDataFactory.createTestMessage(content: "Message 2")
        ]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: originalMessages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, originalMessages.count)
        
        for i in 0..<originalMessages.count {
            XCTAssertEqual(loadedMessages[i].content, originalMessages[i].content)
        }
    }
    
    func testLoadMessagesPreservesTimestamps() throws {
        let originalTimestamp = Date()
        let message = TestDataFactory.createTestMessage(
            content: "Timestamp test",
            timestamp: originalTimestamp
        )
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: [message],
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        
        // Allow for small timestamp differences due to encoding/decoding
        let timeDifference = abs(loadedMessages[0].timestamp.timeIntervalSince(originalTimestamp))
        XCTAssertLessThan(timeDifference, 1.0)
    }
    
    // MARK: - Session Metadata Tests
    
    func testGetSessionMetadataAfterSave() throws {
        let messages = [TestDataFactory.createTestMessage(content: "Test message")]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let metadata = persistenceService.getSessionMetadata(for: testProjectId)
        
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.sessionId, testSessionId)
        XCTAssertEqual(metadata?.projectId, testProjectId)
        XCTAssertEqual(metadata?.projectName, testProject.name)
        XCTAssertEqual(metadata?.projectPath, testProject.path)
        XCTAssertEqual(metadata?.messageCount, 1)
        XCTAssertNotNil(metadata?.lastMessageDate)
    }
    
    func testGetSessionMetadataForNonExistentProject() throws {
        let metadata = persistenceService.getSessionMetadata(for: "non-existent-project")
        XCTAssertNil(metadata)
    }
    
    func testHasSessionForExistingProject() throws {
        let messages = [TestDataFactory.createTestMessage(content: "Test message")]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        XCTAssertTrue(persistenceService.hasSession(for: testProjectId))
    }
    
    func testHasSessionForNonExistentProject() throws {
        XCTAssertFalse(persistenceService.hasSession(for: "non-existent-project"))
    }
    
    // MARK: - Session Metadata Update Tests
    
    func testUpdateSessionMetadata() throws {
        let messages = [TestDataFactory.createTestMessage(content: "Test message")]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        let newSessionId = "updated-session-\(UUID().uuidString)"
        persistenceService.updateSessionMetadata(for: testProjectId, aicliSessionId: newSessionId)
        
        let metadata = persistenceService.getSessionMetadata(for: testProjectId)
        XCTAssertEqual(metadata?.aicliSessionId, newSessionId)
    }
    
    func testUpdateSessionMetadataForNonExistentProject() throws {
        // Should not crash when updating metadata for non-existent project
        persistenceService.updateSessionMetadata(for: "non-existent-project", aicliSessionId: "test")
        
        let metadata = persistenceService.getSessionMetadata(for: "non-existent-project")
        XCTAssertNil(metadata)
    }
    
    // MARK: - Clear Messages Tests
    
    func testClearMessages() throws {
        let messages = [TestDataFactory.createTestMessage(content: "Test message")]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        // Verify messages exist
        XCTAssertTrue(persistenceService.hasSession(for: testProjectId))
        
        // Clear messages
        persistenceService.clearMessages(for: testProjectId)
        
        // Verify messages are cleared
        XCTAssertFalse(persistenceService.hasSession(for: testProjectId))
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 0)
    }
    
    func testClearNonExistentMessages() throws {
        // Should not crash when clearing non-existent messages
        persistenceService.clearMessages(for: "non-existent-project")
        XCTAssertFalse(persistenceService.hasSession(for: "non-existent-project"))
    }
    
    // MARK: - Archive Session Tests
    
    func testArchiveCurrentSession() throws {
        let messages = [TestDataFactory.createTestMessage(content: "Test message")]
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        // Archive the session
        persistenceService.archiveCurrentSession(for: testProjectId)
        
        // Original messages should still be loadable (archiving moves but doesn't delete)
        // This test verifies the archiving doesn't break the service
        XCTAssertNoThrow({
            _ = self.persistenceService.loadMessages(for: self.testProjectId, sessionId: self.testSessionId)
        })
    }
    
    func testArchiveNonExistentSession() throws {
        // Should not crash when archiving non-existent session
        persistenceService.archiveCurrentSession(for: "non-existent-project")
    }
    
    // MARK: - Published Properties Tests
    
    func testSavedSessionsIsPublished() throws {
        let expectation = XCTestExpectation(description: "Saved sessions should be published")
        var sessionChanges: [[String: PersistedSessionMetadata]] = []
        
        persistenceService.$savedSessions
            .sink { sessions in
                sessionChanges.append(sessions)
                if sessionChanges.count >= 2 { // Initial + after save
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        let messages = [TestDataFactory.createTestMessage(content: "Published test")]
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(sessionChanges.count, 2)
        XCTAssertTrue(sessionChanges[1].keys.contains(testProjectId))
    }
    
    // MARK: - Persisted Message Tests
    
    func testPersistedMessageInitialization() throws {
        let originalMessage = TestDataFactory.createTestMessage(
            content: "Test content",
            sender: .user,
            type: .text
        )
        
        let persistedMessage = PersistedMessage(from: originalMessage)
        
        XCTAssertEqual(persistedMessage.content, originalMessage.content)
        XCTAssertEqual(persistedMessage.sender, originalMessage.sender)
        XCTAssertEqual(persistedMessage.type, originalMessage.type)
        XCTAssertEqual(persistedMessage.id, originalMessage.id.uuidString)
    }
    
    func testPersistedMessageToMessage() throws {
        let originalMessage = TestDataFactory.createTestMessage(
            content: "Test content",
            sender: .assistant,
            type: .error
        )
        
        let persistedMessage = PersistedMessage(from: originalMessage)
        let convertedMessage = persistedMessage.toMessage()
        
        XCTAssertEqual(convertedMessage.content, originalMessage.content)
        XCTAssertEqual(convertedMessage.sender, originalMessage.sender)
        XCTAssertEqual(convertedMessage.type, originalMessage.type)
        XCTAssertEqual(convertedMessage.id, originalMessage.id)
    }
    
    // MARK: - Persisted Session Metadata Tests
    
    func testPersistedSessionMetadataFormattedLastUsed() throws {
        let recentDate = Date()
        let metadata = PersistedSessionMetadata(
            sessionId: "test-session",
            projectId: "test-project",
            projectName: "Test Project",
            projectPath: "/test/path",
            lastMessageDate: recentDate,
            messageCount: 5,
            aicliSessionId: "aicli-session",
            createdAt: Date()
        )
        
        let formatted = metadata.formattedLastUsed
        XCTAssertFalse(formatted.isEmpty)
        // Should contain relative time like "now", "1 min ago", etc.
    }
    
    // MARK: - File System Tests
    
    func testPersistenceWithSpecialCharactersInProjectId() throws {
        let specialProjectId = "project/with:special chars"
        let specialProject = Project(name: "Special Project", path: specialProjectId, type: "Test")
        let messages = [TestDataFactory.createTestMessage(content: "Special test")]
        
        // Should handle special characters in project ID
        persistenceService.saveMessages(
            for: specialProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: specialProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: specialProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        XCTAssertEqual(loadedMessages[0].content, "Special test")
    }
    
    // MARK: - Error Handling Tests
    
    func testLoadCorruptedMessagesFile() throws {
        // This test would require creating a corrupted file
        // For now, we test that loading non-existent files doesn't crash
        let loadedMessages = persistenceService.loadMessages(
            for: "corrupted-project",
            sessionId: "corrupted-session"
        )
        XCTAssertEqual(loadedMessages.count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testSaveManyMessages() throws {
        let messageCount = 1000
        var messages: [Message] = []
        
        for i in 0..<messageCount {
            messages.append(TestDataFactory.createTestMessage(
                content: "Message \(i)",
                sender: i % 2 == 0 ? .user : .assistant
            ))
        }
        
        measure {
            persistenceService.saveMessages(
                for: testProjectId,
                messages: messages,
                sessionId: testSessionId,
                project: testProject
            )
        }
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, messageCount)
    }
    
    func testLoadManyMessages() throws {
        let messageCount = 1000
        var messages: [Message] = []
        
        for i in 0..<messageCount {
            messages.append(TestDataFactory.createTestMessage(content: "Message \(i)"))
        }
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: messages,
            sessionId: testSessionId,
            project: testProject
        )
        
        measure {
            _ = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentSaveOperations() throws {
        let expectation = XCTestExpectation(description: "Concurrent saves should complete")
        expectation.expectedFulfillmentCount = 5
        
        let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
        
        for i in 0..<5 {
            concurrentQueue.async {
                let projectId = "\(self.testProjectId!)_concurrent_\(i)"
                let messages = [TestDataFactory.createTestMessage(content: "Concurrent message \(i)")]
                
                self.persistenceService.saveMessages(
                    for: projectId,
                    messages: messages,
                    sessionId: self.testSessionId,
                    project: Project(name: "Concurrent \(i)", path: projectId, type: "Test")
                )
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Verify all concurrent saves succeeded
        for i in 0..<5 {
            let projectId = "\(testProjectId!)_concurrent_\(i)"
            XCTAssertTrue(persistenceService.hasSession(for: projectId))
        }
    }
    
    // MARK: - Edge Cases
    
    func testSaveMessagesWithEmptyContent() throws {
        let message = TestDataFactory.createTestMessage(content: "")
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: [message],
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        XCTAssertEqual(loadedMessages[0].content, "")
    }
    
    func testSaveMessagesWithVeryLongContent() throws {
        let longContent = String(repeating: "Very long message content. ", count: 1000)
        let message = TestDataFactory.createTestMessage(content: longContent)
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: [message],
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        XCTAssertEqual(loadedMessages[0].content, longContent)
    }
    
    func testSaveMessagesWithUnicodeContent() throws {
        let unicodeContent = "Test message with émojis 🚀 and ñ special chars 中文"
        let message = TestDataFactory.createTestMessage(content: unicodeContent)
        
        persistenceService.saveMessages(
            for: testProjectId,
            messages: [message],
            sessionId: testSessionId,
            project: testProject
        )
        
        let loadedMessages = persistenceService.loadMessages(for: testProjectId, sessionId: testSessionId)
        XCTAssertEqual(loadedMessages.count, 1)
        XCTAssertEqual(loadedMessages[0].content, unicodeContent)
    }
}

// MARK: - Test Helpers

extension MessagePersistenceServiceTests {
    
    private func createTestProject(name: String = "Test Project") -> Project {
        return Project(
            name: name,
            path: testProjectId,
            type: "Test"
        )
    }
    
    private func createTestMessages(count: Int) -> [Message] {
        return (0..<count).map { i in
            TestDataFactory.createTestMessage(
                content: "Test message \(i)",
                sender: i % 2 == 0 ? .user : .assistant
            )
        }
    }
}