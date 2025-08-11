import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class ConversationPersistenceServiceTests: XCTestCase {
    
    var persistenceService: ConversationPersistenceService!
    var testConversationId: UUID!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        persistenceService = ConversationPersistenceService()
        testConversationId = UUID()
        cancellables = Set<AnyCancellable>()
        
        // Clear any existing test conversations
        cleanup()
    }
    
    override func tearDown() {
        cleanup()
        cancellables.removeAll()
        persistenceService = nil
        super.tearDown()
    }
    
    private func cleanup() {
        // Remove all test conversations
        let testConversations = persistenceService.conversations.filter { 
            $0.title.contains("Test") || $0.title.contains("testConversation") 
        }
        
        for conversation in testConversations {
            persistenceService.deleteConversation(conversation)
        }
    }
    
    // MARK: - Initialization Tests
    
    func testConversationPersistenceServiceInitialization() throws {
        XCTAssertNotNil(persistenceService)
        XCTAssertNotNil(persistenceService.conversations)
    }
    
    // MARK: - Conversation Creation Tests
    
    func testCreateNewConversation() throws {
        let initialCount = persistenceService.conversations.count
        
        let conversation = persistenceService.createNewConversation(title: "Test Conversation")
        
        XCTAssertEqual(persistenceService.conversations.count, initialCount + 1)
        XCTAssertEqual(conversation.title, "Test Conversation")
        XCTAssertEqual(conversation.messages.count, 0)
        XCTAssertNotNil(conversation.id)
        XCTAssertEqual(persistenceService.currentConversation?.id, conversation.id)
    }
    
    func testCreateNewConversationWithDefaultTitle() throws {
        let conversation = persistenceService.createNewConversation()
        
        XCTAssertEqual(conversation.title, "New Conversation")
        XCTAssertEqual(conversation.messages.count, 0)
    }
    
    func testCreateNewConversationWithSessionId() throws {
        let sessionId = "test-session-123"
        let conversation = persistenceService.createNewConversation(
            title: "Test with Session",
            sessionId: sessionId
        )
        
        XCTAssertEqual(conversation.sessionId, sessionId)
        XCTAssertEqual(conversation.title, "Test with Session")
    }
    
    func testCreateNewConversationWithWorkingDirectory() throws {
        let workingDir = "/test/working/directory"
        let conversation = persistenceService.createNewConversation(
            title: "Test with Working Dir",
            workingDirectory: workingDir
        )
        
        XCTAssertEqual(conversation.workingDirectory, workingDir)
        XCTAssertEqual(conversation.title, "Test with Working Dir")
    }
    
    // MARK: - Message Management Tests
    
    func testAddMessageToCurrentConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testConversation")
        let message = TestDataFactory.createTestMessage(content: "Test message")
        
        persistenceService.addMessageToCurrentConversation(message)
        
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(persistenceService.currentConversation?.messages.count, 1)
        XCTAssertEqual(persistenceService.currentConversation?.messages.first?.content, "Test message")
    }
    
    func testAddMessageToCurrentConversationCreatesNewWhenNone() throws {
        persistenceService.currentConversation = nil
        let message = TestDataFactory.createTestMessage(content: "Auto-create test")
        
        persistenceService.addMessageToCurrentConversation(message)
        
        XCTAssertNotNil(persistenceService.currentConversation)
        XCTAssertEqual(persistenceService.currentConversation?.messages.count, 1)
        XCTAssertEqual(persistenceService.currentConversation?.messages.first?.content, "Auto-create test")
    }
    
    func testAddMultipleMessages() throws {
        let conversation = persistenceService.createNewConversation(title: "testConversation")
        let messages = [
            TestDataFactory.createTestMessage(content: "First message", sender: .user),
            TestDataFactory.createTestMessage(content: "Second message", sender: .assistant),
            TestDataFactory.createTestMessage(content: "Third message", sender: .user)
        ]
        
        for message in messages {
            persistenceService.addMessageToCurrentConversation(message)
        }
        
        XCTAssertEqual(persistenceService.currentConversation?.messages.count, 3)
        XCTAssertEqual(persistenceService.currentConversation?.messages[0].content, "First message")
        XCTAssertEqual(persistenceService.currentConversation?.messages[1].content, "Second message")
        XCTAssertEqual(persistenceService.currentConversation?.messages[2].content, "Third message")
    }
    
    // MARK: - Title Management Tests
    
    func testUpdateCurrentConversationTitle() throws {
        let conversation = persistenceService.createNewConversation(title: "testConversation")
        let newTitle = "Updated Test Title"
        
        persistenceService.updateCurrentConversationTitle(newTitle)
        
        XCTAssertEqual(persistenceService.currentConversation?.title, newTitle)
        
        // Find the conversation in the array
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertEqual(updatedConversation?.title, newTitle)
    }
    
    func testUpdateTitleWithNoCurrentConversation() throws {
        persistenceService.currentConversation = nil
        
        // Should not crash
        persistenceService.updateCurrentConversationTitle("Should not update")
        
        XCTAssertNil(persistenceService.currentConversation)
    }
    
    // MARK: - Working Directory Tests
    
    func testUpdateCurrentConversationWorkingDirectory() throws {
        let conversation = persistenceService.createNewConversation(title: "testConversation")
        let workingDir = "/new/working/directory"
        
        persistenceService.updateCurrentConversationWorkingDirectory(workingDir)
        
        XCTAssertEqual(persistenceService.currentConversation?.workingDirectory, workingDir)
        
        // Find the conversation in the array
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertEqual(updatedConversation?.workingDirectory, workingDir)
    }
    
    func testUpdateWorkingDirectoryWithNoCurrentConversation() throws {
        persistenceService.currentConversation = nil
        
        // Should not crash
        persistenceService.updateCurrentConversationWorkingDirectory("/should/not/update")
        
        XCTAssertNil(persistenceService.currentConversation)
    }
    
    // MARK: - Conversation Switching Tests
    
    func testSwitchToConversation() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testConversation1")
        let conversation2 = persistenceService.createNewConversation(title: "testConversation2")
        
        XCTAssertEqual(persistenceService.currentConversation?.id, conversation2.id)
        
        persistenceService.switchToConversation(conversation1)
        
        XCTAssertEqual(persistenceService.currentConversation?.id, conversation1.id)
    }
    
    // MARK: - Conversation Deletion Tests
    
    func testDeleteConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testConversationToDelete")
        let initialCount = persistenceService.conversations.count
        
        persistenceService.deleteConversation(conversation)
        
        XCTAssertEqual(persistenceService.conversations.count, initialCount - 1)
        XCTAssertFalse(persistenceService.conversations.contains { $0.id == conversation.id })
    }
    
    func testDeleteCurrentConversation() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testConversation1")
        let conversation2 = persistenceService.createNewConversation(title: "testConversation2")
        
        // conversation2 should be current
        XCTAssertEqual(persistenceService.currentConversation?.id, conversation2.id)
        
        persistenceService.deleteConversation(conversation2)
        
        // Should switch to first available conversation
        XCTAssertNotEqual(persistenceService.currentConversation?.id, conversation2.id)
    }
    
    // MARK: - Conversation Duplication Tests
    
    func testDuplicateConversation() throws {
        let originalConversation = persistenceService.createNewConversation(title: "testOriginal")
        let message = TestDataFactory.createTestMessage(content: "Test message")
        persistenceService.addMessageToCurrentConversation(message)
        
        let duplicatedConversation = persistenceService.duplicateConversation(originalConversation)
        
        XCTAssertNotEqual(duplicatedConversation.id, originalConversation.id)
        XCTAssertEqual(duplicatedConversation.title, "testOriginal (Copy)")
        XCTAssertEqual(duplicatedConversation.messages.count, originalConversation.messages.count)
        XCTAssertEqual(duplicatedConversation.messages.first?.content, "Test message")
        XCTAssertNil(duplicatedConversation.sessionId) // Should not copy session ID
    }
    
    // MARK: - Search Tests
    
    func testSearchConversations() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testSearchableTitle")
        let conversation2 = persistenceService.createNewConversation(title: "testDifferentTitle")
        
        // Add message to conversation2
        persistenceService.switchToConversation(conversation2)
        persistenceService.addMessageToCurrentConversation(
            TestDataFactory.createTestMessage(content: "Searchable content in message")
        )
        
        // Search by title
        let titleResults = persistenceService.searchConversations(query: "Searchable")
        XCTAssertEqual(titleResults.count, 1)
        XCTAssertEqual(titleResults.first?.id, conversation1.id)
        
        // Search by message content
        let contentResults = persistenceService.searchConversations(query: "message")
        XCTAssertEqual(contentResults.count, 1)
        XCTAssertEqual(contentResults.first?.id, conversation2.id)
        
        // Search with empty query returns all
        let allResults = persistenceService.searchConversations(query: "")
        XCTAssertGreaterThanOrEqual(allResults.count, 2)
    }
    
    // MARK: - Tag Management Tests
    
    func testAddTagToConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testTaggedConversation")
        let tag = "important"
        
        persistenceService.addTagToConversation(conversation, tag: tag)
        
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertTrue(updatedConversation?.metadata.tags.contains(tag) ?? false)
    }
    
    func testRemoveTagFromConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testTaggedConversation")
        let tag = "remove-me"
        
        persistenceService.addTagToConversation(conversation, tag: tag)
        persistenceService.removeTagFromConversation(conversation, tag: tag)
        
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertFalse(updatedConversation?.metadata.tags.contains(tag) ?? true)
    }
    
    func testGetConversationsWithTag() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testTagged1")
        let conversation2 = persistenceService.createNewConversation(title: "testTagged2")
        let conversation3 = persistenceService.createNewConversation(title: "testUntagged")
        
        let tag = "test-tag"
        persistenceService.addTagToConversation(conversation1, tag: tag)
        persistenceService.addTagToConversation(conversation2, tag: tag)
        
        let taggedConversations = persistenceService.getConversationsWithTag(tag)
        
        XCTAssertEqual(taggedConversations.count, 2)
        XCTAssertTrue(taggedConversations.contains { $0.id == conversation1.id })
        XCTAssertTrue(taggedConversations.contains { $0.id == conversation2.id })
        XCTAssertFalse(taggedConversations.contains { $0.id == conversation3.id })
    }
    
    func testGetAllTags() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testConversation1")
        let conversation2 = persistenceService.createNewConversation(title: "testConversation2")
        
        persistenceService.addTagToConversation(conversation1, tag: "tag1")
        persistenceService.addTagToConversation(conversation1, tag: "tag2")
        persistenceService.addTagToConversation(conversation2, tag: "tag2")
        persistenceService.addTagToConversation(conversation2, tag: "tag3")
        
        let allTags = persistenceService.getAllTags()
        
        XCTAssertEqual(Set(allTags), Set(["tag1", "tag2", "tag3"]))
    }
    
    // MARK: - Archive and Favorite Tests
    
    func testArchiveConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testArchiveConversation")
        
        persistenceService.archiveConversation(conversation)
        
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertTrue(updatedConversation?.metadata.isArchived ?? false)
    }
    
    func testUnarchiveConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testUnarchiveConversation")
        
        persistenceService.archiveConversation(conversation)
        persistenceService.unarchiveConversation(conversation)
        
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertFalse(updatedConversation?.metadata.isArchived ?? true)
    }
    
    func testFavoriteConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testFavoriteConversation")
        
        persistenceService.favoriteConversation(conversation)
        
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertTrue(updatedConversation?.metadata.isFavorite ?? false)
    }
    
    func testUnfavoriteConversation() throws {
        let conversation = persistenceService.createNewConversation(title: "testUnfavoriteConversation")
        
        persistenceService.favoriteConversation(conversation)
        persistenceService.unfavoriteConversation(conversation)
        
        let updatedConversation = persistenceService.conversations.first { $0.id == conversation.id }
        XCTAssertFalse(updatedConversation?.metadata.isFavorite ?? true)
    }
    
    func testGetFavoriteConversations() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testFavorite1")
        let conversation2 = persistenceService.createNewConversation(title: "testFavorite2")
        let conversation3 = persistenceService.createNewConversation(title: "testNotFavorite")
        
        persistenceService.favoriteConversation(conversation1)
        persistenceService.favoriteConversation(conversation2)
        
        let favorites = persistenceService.getFavoriteConversations()
        
        XCTAssertEqual(favorites.count, 2)
        XCTAssertTrue(favorites.contains { $0.id == conversation1.id })
        XCTAssertTrue(favorites.contains { $0.id == conversation2.id })
        XCTAssertFalse(favorites.contains { $0.id == conversation3.id })
    }
    
    func testGetArchivedConversations() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testArchived1")
        let conversation2 = persistenceService.createNewConversation(title: "testArchived2")
        let conversation3 = persistenceService.createNewConversation(title: "testActive")
        
        persistenceService.archiveConversation(conversation1)
        persistenceService.archiveConversation(conversation2)
        
        let archived = persistenceService.getArchivedConversations()
        
        XCTAssertEqual(archived.count, 2)
        XCTAssertTrue(archived.contains { $0.id == conversation1.id })
        XCTAssertTrue(archived.contains { $0.id == conversation2.id })
        XCTAssertFalse(archived.contains { $0.id == conversation3.id })
    }
    
    func testGetActiveConversations() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testActive1")
        let conversation2 = persistenceService.createNewConversation(title: "testActive2")
        let conversation3 = persistenceService.createNewConversation(title: "testArchivedConversation")
        
        persistenceService.archiveConversation(conversation3)
        
        let active = persistenceService.getActiveConversations()
        
        XCTAssertTrue(active.contains { $0.id == conversation1.id })
        XCTAssertTrue(active.contains { $0.id == conversation2.id })
        XCTAssertFalse(active.contains { $0.id == conversation3.id })
    }
    
    // MARK: - Tool Usage Tests
    
    func testGetConversationsWithToolUsage() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testWithTools")
        let conversation2 = persistenceService.createNewConversation(title: "testWithoutTools")
        
        // Add a tool message to conversation1
        persistenceService.switchToConversation(conversation1)
        persistenceService.addMessageToCurrentConversation(
            TestDataFactory.createTestMessage(content: "Tool message", type: .toolUse)
        )
        
        // Add a regular message to conversation2
        persistenceService.switchToConversation(conversation2)
        persistenceService.addMessageToCurrentConversation(
            TestDataFactory.createTestMessage(content: "Regular message", type: .text)
        )
        
        let toolConversations = persistenceService.getConversationsWithToolUsage()
        
        XCTAssertTrue(toolConversations.contains { $0.id == conversation1.id })
        XCTAssertFalse(toolConversations.contains { $0.id == conversation2.id })
    }
    
    // MARK: - Published Properties Tests
    
    func testConversationsIsPublished() throws {
        let expectation = XCTestExpectation(description: "Conversations should be published")
        var conversationChanges: [[Conversation]] = []
        
        persistenceService.$conversations
            .sink { conversations in
                conversationChanges.append(conversations)
                if conversationChanges.count >= 2 { // Initial + after creation
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        _ = persistenceService.createNewConversation(title: "testPublished")
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(conversationChanges.count, 2)
        XCTAssertTrue(conversationChanges[1].contains { $0.title == "testPublished" })
    }
    
    func testCurrentConversationIsPublished() throws {
        let expectation = XCTestExpectation(description: "Current conversation should be published")
        var currentConversationChanges: [Conversation?] = []
        
        persistenceService.$currentConversation
            .sink { conversation in
                currentConversationChanges.append(conversation)
                if currentConversationChanges.count >= 2 { // Initial + after creation
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        let conversation = persistenceService.createNewConversation(title: "testCurrentPublished")
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(currentConversationChanges.count, 2)
        XCTAssertEqual(currentConversationChanges[1]?.id, conversation.id)
    }
    
    // MARK: - Statistics Tests
    
    func testGetStatistics() throws {
        // Create conversations with various properties
        let conversation1 = persistenceService.createNewConversation(title: "testStats1")
        let conversation2 = persistenceService.createNewConversation(title: "testStats2")
        
        // Add messages
        persistenceService.switchToConversation(conversation1)
        persistenceService.addMessageToCurrentConversation(
            TestDataFactory.createTestMessage(content: "Message 1")
        )
        persistenceService.addMessageToCurrentConversation(
            TestDataFactory.createTestMessage(content: "Message 2", type: .toolUse)
        )
        
        persistenceService.switchToConversation(conversation2)
        persistenceService.addMessageToCurrentConversation(
            TestDataFactory.createTestMessage(content: "Message 3")
        )
        
        let stats = persistenceService.getStatistics()
        
        XCTAssertGreaterThanOrEqual(stats.totalConversations, 2)
        XCTAssertGreaterThanOrEqual(stats.totalMessages, 3)
        XCTAssertGreaterThanOrEqual(stats.conversationsWithTools, 1)
        XCTAssertGreaterThan(stats.averageMessagesPerConversation, 0)
    }
    
    // MARK: - Bulk Operations Tests
    
    func testBulkDeleteConversations() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testBulkDelete1")
        let conversation2 = persistenceService.createNewConversation(title: "testBulkDelete2")
        let conversation3 = persistenceService.createNewConversation(title: "testKeep")
        
        let idsToDelete = [conversation1.id, conversation2.id]
        let initialCount = persistenceService.conversations.count
        
        persistenceService.bulkDeleteConversations(idsToDelete)
        
        XCTAssertEqual(persistenceService.conversations.count, initialCount - 2)
        XCTAssertFalse(persistenceService.conversations.contains { $0.id == conversation1.id })
        XCTAssertFalse(persistenceService.conversations.contains { $0.id == conversation2.id })
        XCTAssertTrue(persistenceService.conversations.contains { $0.id == conversation3.id })
    }
    
    func testBulkArchiveConversations() throws {
        let conversation1 = persistenceService.createNewConversation(title: "testBulkArchive1")
        let conversation2 = persistenceService.createNewConversation(title: "testBulkArchive2")
        let conversation3 = persistenceService.createNewConversation(title: "testStayActive")
        
        let idsToArchive = [conversation1.id, conversation2.id]
        
        persistenceService.bulkArchiveConversations(idsToArchive)
        
        let updatedConversation1 = persistenceService.conversations.first { $0.id == conversation1.id }
        let updatedConversation2 = persistenceService.conversations.first { $0.id == conversation2.id }
        let updatedConversation3 = persistenceService.conversations.first { $0.id == conversation3.id }
        
        XCTAssertTrue(updatedConversation1?.metadata.isArchived ?? false)
        XCTAssertTrue(updatedConversation2?.metadata.isArchived ?? false)
        XCTAssertFalse(updatedConversation3?.metadata.isArchived ?? true)
    }
    
    // MARK: - Conversation Model Tests
    
    func testConversationAddMessage() throws {
        var conversation = Conversation(title: "Test Conversation")
        let message = TestDataFactory.createTestMessage(content: "Test message")
        
        conversation.addMessage(message)
        
        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages.first?.content, "Test message")
        XCTAssertEqual(conversation.metadata.messageCount, 1)
    }
    
    func testConversationAutoGenerateTitle() throws {
        var conversation = Conversation(title: "New Conversation")
        let userMessage = TestDataFactory.createTestMessage(
            content: "Hello this is my first message",
            sender: .user
        )
        
        conversation.addMessage(userMessage)
        
        XCTAssertEqual(conversation.title, "Hello this is my first message")
    }
    
    func testConversationAutoGenerateTitleWithLongMessage() throws {
        var conversation = Conversation(title: "New Conversation")
        let longMessage = TestDataFactory.createTestMessage(
            content: "This is a very long message that should be truncated to only the first six words for the title",
            sender: .user
        )
        
        conversation.addMessage(longMessage)
        
        XCTAssertEqual(conversation.title, "This is a very long message that")
    }
    
    func testConversationMetadataUpdates() throws {
        var conversation = Conversation(title: "Test Conversation")
        
        // Add tool message
        let toolMessage = TestDataFactory.createTestMessage(content: "Tool used", type: .toolUse)
        conversation.addMessage(toolMessage)
        
        XCTAssertTrue(conversation.metadata.hasToolUsage)
        XCTAssertEqual(conversation.metadata.messageCount, 1)
    }
    
    // MARK: - Export Format Tests
    
    func testExportFormatProperties() throws {
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.text.fileExtension, "txt")
        XCTAssertEqual(ExportFormat.html.fileExtension, "html")
        XCTAssertEqual(ExportFormat.csv.fileExtension, "csv")
        
        XCTAssertEqual(ExportFormat.json.icon, "doc.text")
        XCTAssertEqual(ExportFormat.markdown.icon, "doc.richtext")
        XCTAssertEqual(ExportFormat.text.icon, "doc.plaintext")
        XCTAssertEqual(ExportFormat.html.icon, "globe")
        XCTAssertEqual(ExportFormat.csv.icon, "tablecells")
    }
    
    // MARK: - Performance Tests
    
    func testCreateManyConversations() throws {
        let initialCount = persistenceService.conversations.count
        
        measure {
            for i in 0..<100 {
                _ = persistenceService.createNewConversation(title: "Performance Test \(i)")
            }
        }
        
        XCTAssertEqual(persistenceService.conversations.count, initialCount + 100)
        
        // Clean up performance test data
        let perfConversations = persistenceService.conversations.filter { 
            $0.title.contains("Performance Test")
        }
        for conversation in perfConversations {
            persistenceService.deleteConversation(conversation)
        }
    }
    
    // MARK: - Edge Cases
    
    func testConversationWithEmptyTitle() throws {
        let conversation = persistenceService.createNewConversation(title: "")
        
        XCTAssertEqual(conversation.title, "")
        XCTAssertNotNil(conversation.id)
    }
    
    func testConversationWithLongTitle() throws {
        let longTitle = String(repeating: "Very Long Title ", count: 100)
        let conversation = persistenceService.createNewConversation(title: longTitle)
        
        XCTAssertEqual(conversation.title, longTitle)
    }
    
    func testConversationWithUnicodeContent() throws {
        let unicodeTitle = "Test with émojis 🚀 and ñ special chars 中文"
        let conversation = persistenceService.createNewConversation(title: unicodeTitle)
        
        XCTAssertEqual(conversation.title, unicodeTitle)
    }
}

// MARK: - Test Helpers

extension ConversationPersistenceServiceTests {
    
    private func createTestConversationWithMessages(
        title: String = "Test Conversation",
        messageCount: Int = 3
    ) -> Conversation {
        let conversation = persistenceService.createNewConversation(title: title)
        
        for i in 0..<messageCount {
            let message = TestDataFactory.createTestMessage(
                content: "Test message \(i + 1)",
                sender: i % 2 == 0 ? .user : .assistant
            )
            persistenceService.addMessageToCurrentConversation(message)
        }
        
        return conversation
    }
}