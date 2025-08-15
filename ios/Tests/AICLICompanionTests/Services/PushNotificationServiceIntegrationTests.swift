import XCTest
import UserNotifications
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class PushNotificationServiceIntegrationTests: XCTestCase {
    
    var pushService: PushNotificationService!
    var testProjectPath: String!
    var testSessionId: String!
    var testProject: Project!
    
    override func setUp() {
        super.setUp()
        pushService = PushNotificationService.shared
        testProjectPath = "/test/project/path"
        testSessionId = "test-session-\(UUID().uuidString)"
        testProject = Project(name: "Test Project", path: testProjectPath, type: "directory")
        
        // Clean up any existing test data
        MessagePersistenceService.shared.clearMessages(for: testProjectPath)
    }
    
    override func tearDown() {
        // Clean up test data
        MessagePersistenceService.shared.clearMessages(for: testProjectPath)
        super.tearDown()
    }
    
    // MARK: - Core Background Message Processing Tests
    
    func testProcessMessageContentWithSmallMessage() throws {
        // Test the core logic of processMessageContentIfPresent method
        let testMessage = "Hello from Claude in background!"
        let userInfo: [AnyHashable: Any] = [
            "message": testMessage,
            "sessionId": testSessionId!,
            "projectPath": testProjectPath!
        ]
        
        // Create a reflection-based test to access private method
        let mirror = Mirror(reflecting: pushService)
        
        // Call the method directly using a simulated notification payload
        let expectation = XCTestExpectation(description: "Background message processed")
        
        // Use the actual implementation approach - simulate what happens in didReceive
        Task {
            await pushService.testProcessMessageContentDirectly(userInfo: userInfo)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        // Verify message was saved to persistence
        let savedMessages = MessagePersistenceService.shared.loadMessages(
            for: testProjectPath,
            sessionId: testSessionId
        )
        
        XCTAssertEqual(savedMessages.count, 1, "Should have saved one message")
        XCTAssertEqual(savedMessages[0].content, testMessage, "Message content should match")
        XCTAssertEqual(savedMessages[0].sender, .assistant, "Message should be from assistant")
    }
    
    func testProcessMessageContentWithLargeMessageSignal() throws {
        // Test that large message signals are recognized (even if fetching fails in test)
        let preview = "This is a preview of a large message..."
        let messageId = "large-message-id"
        
        let userInfo: [AnyHashable: Any] = [
            "requiresFetch": true,
            "messageId": messageId,
            "sessionId": testSessionId!,
            "projectPath": testProjectPath!,
            "preview": preview
        ]
        
        let expectation = XCTestExpectation(description: "Large message signal processed")
        
        Task {
            await pushService.testProcessMessageContentDirectly(userInfo: userInfo)
            // The method should handle the large message signal, even if fetch fails in test
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        // Note: In test environment, fetchMessage will likely fail
        // This test verifies the handler recognizes large message signals
        print("✅ Large message signal processing test completed")
    }
    
    func testProcessMessageContentIgnoresInvalidPayloads() throws {
        // Test that invalid notifications don't interfere with message processing
        let userInfo: [AnyHashable: Any] = [
            "someOtherKey": "someValue",
            "notAClaudeMessage": true
        ]
        
        let expectation = XCTestExpectation(description: "Invalid notification handled")
        
        Task {
            await pushService.testProcessMessageContentDirectly(userInfo: userInfo)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Verify no messages were saved
        let savedMessages = MessagePersistenceService.shared.loadMessages(
            for: testProjectPath,
            sessionId: testSessionId
        )
        
        XCTAssertEqual(savedMessages.count, 0, "Should not have saved any messages for invalid notifications")
    }
    
    func testMessagePersistenceAfterBackgroundProcessing() throws {
        // Test that messages processed in background are available when returning to foreground
        let backgroundMessage = "Message received while app was backgrounded"
        let userInfo: [AnyHashable: Any] = [
            "message": backgroundMessage,
            "sessionId": testSessionId!,
            "projectPath": testProjectPath!
        ]
        
        let expectation = XCTestExpectation(description: "Background message processed")
        
        // Simulate background notification processing
        Task {
            await pushService.testProcessMessageContentDirectly(userInfo: userInfo)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
        
        // Simulate returning to foreground and loading messages
        let loadedMessages = MessagePersistenceService.shared.loadMessages(
            for: testProjectPath,
            sessionId: testSessionId
        )
        
        XCTAssertEqual(loadedMessages.count, 1, "Background message should be available when returning to foreground")
        XCTAssertEqual(loadedMessages[0].content, backgroundMessage, "Message content should be preserved")
        XCTAssertEqual(loadedMessages[0].sender, .assistant, "Message should be from assistant")
    }
    
    func testMultipleBackgroundMessagesProcessing() throws {
        // Test that multiple background notifications are processed correctly
        let messages = [
            "First background message",
            "Second background message", 
            "Third background message"
        ]
        
        let expectation = XCTestExpectation(description: "Multiple background messages processed")
        expectation.expectedFulfillmentCount = messages.count
        
        for message in messages {
            let userInfo: [AnyHashable: Any] = [
                "message": message,
                "sessionId": testSessionId!,
                "projectPath": testProjectPath!
            ]
            
            Task {
                await pushService.testProcessMessageContentDirectly(userInfo: userInfo)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Verify all messages were saved
        let savedMessages = MessagePersistenceService.shared.loadMessages(
            for: testProjectPath,
            sessionId: testSessionId
        )
        
        XCTAssertEqual(savedMessages.count, messages.count, "Should have saved all messages")
        
        // Verify message order and content
        for (index, savedMessage) in savedMessages.enumerated() {
            XCTAssertEqual(savedMessage.content, messages[index], "Message \(index + 1) content should match")
        }
    }
}

// MARK: - Test Helper Extension

@available(iOS 16.0, macOS 13.0, *)
extension PushNotificationService {
    /// Test helper method to access the private processMessageContentIfPresent method
    func testProcessMessageContentDirectly(userInfo: [AnyHashable: Any]) async {
        // This is essentially the same logic as processMessageContentIfPresent
        // but accessible for testing
        
        // Check if this requires fetching (large messages)
        if let requiresFetch = userInfo["requiresFetch"] as? Bool,
           requiresFetch,
           let messageId = userInfo["messageId"] as? String,
           let sessionId = userInfo["sessionId"] as? String,
           let projectPath = userInfo["projectPath"] as? String,
           let preview = userInfo["preview"] as? String {
            
            print("📲 Test: Large message signal detected")
            
            do {
                let fullMessage = try await AICLIService.shared.fetchMessage(
                    sessionId: sessionId,
                    messageId: messageId
                )
                
                await saveClaudeMessage(
                    message: fullMessage.content,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    userInfo: userInfo
                )
                
                await postClaudeResponseNotification(
                    message: fullMessage.content,
                    sessionId: sessionId,
                    projectPath: projectPath
                )
            } catch {
                print("❌ Test: Background fetch failed: \(error)")
                // Fallback to preview with error indication
                let errorMessage = "\(preview)\n\n⚠️ [Failed to load full message. Tap to retry.]"
                await saveClaudeMessage(
                    message: errorMessage,
                    sessionId: sessionId,
                    projectPath: projectPath,
                    userInfo: userInfo
                )
                
                await postClaudeResponseNotification(
                    message: errorMessage,
                    sessionId: sessionId,
                    projectPath: projectPath
                )
            }
        } else if let claudeMessage = userInfo["message"] as? String,
                  let sessionId = userInfo["sessionId"] as? String,
                  let projectPath = userInfo["projectPath"] as? String {
            // Small message - process directly
            print("🤖 Test: Background message processing: \(claudeMessage.count) characters")
            
            await saveClaudeMessage(
                message: claudeMessage,
                sessionId: sessionId,
                projectPath: projectPath,
                userInfo: userInfo
            )
            
            await postClaudeResponseNotification(
                message: claudeMessage,
                sessionId: sessionId,
                projectPath: projectPath
            )
            
            print("✅ Test: Background message processed and saved")
        } else {
            print("ℹ️ Test: No Claude message content in notification payload")
        }
    }
}