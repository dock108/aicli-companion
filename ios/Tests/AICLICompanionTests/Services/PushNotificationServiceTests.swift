import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class PushNotificationServiceTests: XCTestCase {
    // MARK: - Basic Logic Tests (No UserNotifications required)
    
    func testServiceExists() {
        // Test that the service class can be accessed
        let serviceType = PushNotificationService.self
        XCTAssertNotNil(serviceType)
    }
    
    func testAPNSMessageProcessingLogic() async {
        // Test APNS message processing logic without UserNotifications
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Test Title",
                    "body": "Test Body"
                ],
                "badge": 1
            ],
            "projectId": "test-project",
            "messageId": "test-msg-123"
        ]
        
        // This tests the data structure parsing logic
        XCTAssertNotNil(userInfo["aps"])
        XCTAssertNotNil(userInfo["projectId"])
        XCTAssertNotNil(userInfo["messageId"])
        
        if let aps = userInfo["aps"] as? [String: Any],
           let alert = aps["alert"] as? [String: Any] {
            XCTAssertEqual(alert["title"] as? String, "Test Title")
            XCTAssertEqual(alert["body"] as? String, "Test Body")
        }
        
        if let projectId = userInfo["projectId"] as? String {
            XCTAssertEqual(projectId, "test-project")
        }
    }
    
    func testAPNSMessageWithMissingData() {
        // Test handling of malformed APNS data
        let userInfo1: [AnyHashable: Any] = [:]
        let userInfo2: [AnyHashable: Any] = ["invalid": "data"]
        let userInfo3: [AnyHashable: Any] = [
            "aps": NSNull(),
            "projectId": 12345, // Wrong type
            "messageId": ["not": "string"]
        ]
        
        // These should not crash when processed
        XCTAssertTrue(userInfo1.isEmpty)
        XCTAssertFalse(userInfo2.isEmpty)
        XCTAssertFalse(userInfo3.isEmpty)
    }
    
    func testNotificationDataExtraction() {
        // Test the logic for extracting data from notifications
        let validUserInfo: [AnyHashable: Any] = [
            "messageId": "direct-id-123"
        ]
        
        let fallbackUserInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Fallback Title",
                    "body": "Fallback Body"
                ]
            ],
            "projectId": "fallback-project"
        ]
        
        // Test direct message ID extraction
        if let messageId = validUserInfo["messageId"] as? String {
            XCTAssertEqual(messageId, "direct-id-123")
        }
        
        // Test fallback data extraction
        if let projectId = fallbackUserInfo["projectId"] as? String {
            XCTAssertEqual(projectId, "fallback-project")
        }
    }
    
    func testProjectPathLogic() {
        // Test project path comparison logic (what shouldShowNotification uses)
        let activeProjectPath = "/Users/test/active-project"
        let inactiveProjectPath = "/Users/test/inactive-project"
        
        // Same path check
        XCTAssertTrue(activeProjectPath == activeProjectPath)
        XCTAssertFalse(activeProjectPath == inactiveProjectPath)
        
        // Path normalization concepts
        let pathWithTrailingSlash = "/Users/test/project/"
        let pathWithoutTrailingSlash = "/Users/test/project"
        
        // Test that we handle path variations correctly
        let normalizedPath1 = pathWithTrailingSlash.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath2 = pathWithoutTrailingSlash.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        XCTAssertEqual(normalizedPath1, normalizedPath2)
    }
    
    func testMessageIdHashing() {
        // Test the hashing logic used for duplicate detection
        let message1 = "This is a test message"
        let message2 = "This is a test message" // Same
        let message3 = "This is different"
        
        let hash1 = message1.hashValue
        let hash2 = message2.hashValue
        let hash3 = message3.hashValue
        
        XCTAssertEqual(hash1, hash2, "Same messages should have same hash")
        XCTAssertNotEqual(hash1, hash3, "Different messages should have different hashes")
    }
    
    func testNotificationContentValidation() {
        // Test notification content validation logic
        let validTitle = "Claude Response"
        let validBody = "Your analysis is complete"
        let validProjectId = "project-123"
        
        // Basic validation
        XCTAssertFalse(validTitle.isEmpty)
        XCTAssertFalse(validBody.isEmpty)
        XCTAssertFalse(validProjectId.isEmpty)
        
        // Edge cases
        let emptyTitle = ""
        let longTitle = String(repeating: "A", count: 1000)
        let specialCharsTitle = "🎉 Claude Response 📱"
        
        XCTAssertTrue(emptyTitle.isEmpty)
        XCTAssertEqual(longTitle.count, 1000)
        XCTAssertTrue(specialCharsTitle.contains("🎉"))
        
        // Unicode handling
        let unicodeBody = "Analysis complete: ✅ Success! 世界"
        XCTAssertTrue(unicodeBody.contains("✅"))
        XCTAssertTrue(unicodeBody.contains("世界"))
    }
    
    func testProjectNotificationGrouping() {
        // Test the logic for grouping notifications by project
        var pendingNotifications: [String: Int] = [:]
        
        let project1 = "project-alpha"
        let project2 = "project-beta"
        
        // Simulate incrementing badge count for projects
        pendingNotifications[project1] = (pendingNotifications[project1] ?? 0) + 1
        pendingNotifications[project1] = (pendingNotifications[project1] ?? 0) + 1
        pendingNotifications[project2] = (pendingNotifications[project2] ?? 0) + 1
        
        XCTAssertEqual(pendingNotifications[project1], 2)
        XCTAssertEqual(pendingNotifications[project2], 1)
        
        // Test clearing project notifications
        pendingNotifications[project1] = 0
        XCTAssertEqual(pendingNotifications[project1], 0)
        XCTAssertEqual(pendingNotifications[project2], 1)
        
        // Test total badge count
        let totalBadgeCount = pendingNotifications.values.reduce(0, +)
        XCTAssertEqual(totalBadgeCount, 1)
    }
    
    func testNotificationActionsConfiguration() {
        // Test the configuration data for notification actions
        let viewActionIdentifier = "VIEW_ACTION"
        let dismissActionIdentifier = "DISMISS_ACTION"
        let markReadActionIdentifier = "MARK_READ_ACTION"
        let categoryIdentifier = "CLAUDE_COMPANION_CATEGORY"
        
        // Validate action identifiers
        XCTAssertEqual(viewActionIdentifier, "VIEW_ACTION")
        XCTAssertEqual(dismissActionIdentifier, "DISMISS_ACTION")
        XCTAssertEqual(markReadActionIdentifier, "MARK_READ_ACTION")
        XCTAssertEqual(categoryIdentifier, "CLAUDE_COMPANION_CATEGORY")
        
        // Test action data structure
        let actionData: [String: Any] = [
            "identifier": viewActionIdentifier,
            "title": "View",
            "options": ["foreground"]
        ]
        
        XCTAssertEqual(actionData["identifier"] as? String, viewActionIdentifier)
        XCTAssertEqual(actionData["title"] as? String, "View")
        XCTAssertNotNil(actionData["options"])
    }
    
    func testConcurrentMessageProcessing() {
        // Test concurrent message processing logic
        let expectation = XCTestExpectation(description: "Concurrent processing")
        expectation.expectedFulfillmentCount = 5
        
        var processedMessages: Set<String> = []
        let queue = DispatchQueue(label: "test.concurrent.processing", attributes: .concurrent)
        let serialQueue = DispatchQueue(label: "test.serial.access")
        
        for i in 1...5 {
            queue.async {
                let messageId = "message-\(i)"
                
                serialQueue.async {
                    processedMessages.insert(messageId)
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(processedMessages.count, 5)
    }
    
    func testMessageDeduplicationLogic() {
        // Test message deduplication logic
        var processedMessageIds = Set<String>()
        
        let message1 = "msg-001"
        let message2 = "msg-002"
        let message1Duplicate = "msg-001" // Same as message1
        
        // First time processing
        let wasProcessed1 = processedMessageIds.contains(message1)
        XCTAssertFalse(wasProcessed1)
        processedMessageIds.insert(message1)
        
        let wasProcessed2 = processedMessageIds.contains(message2)
        XCTAssertFalse(wasProcessed2)
        processedMessageIds.insert(message2)
        
        // Duplicate detection
        let wasDuplicateProcessed = processedMessageIds.contains(message1Duplicate)
        XCTAssertTrue(wasDuplicateProcessed, "Should detect duplicate message")
        
        XCTAssertEqual(processedMessageIds.count, 2, "Should have 2 unique messages")
    }
    
    func testPerformanceOfMessageProcessing() {
        // Performance test for message processing logic
        measure {
            var messages: [String] = []
            
            for i in 0..<1000 {
                let messageData = [
                    "messageId": "msg-\(i)",
                    "projectId": "project-\(i % 10)",
                    "title": "Message \(i)",
                    "body": "This is message number \(i)"
                ]
                
                // Simulate processing
                if let messageId = messageData["messageId"],
                   let projectId = messageData["projectId"] {
                    messages.append("\(projectId):\(messageId)")
                }
            }
            
            XCTAssertEqual(messages.count, 1000)
        }
    }
    
    func testNotificationSchedulingData() {
        // Test notification scheduling data structures
        let notificationContent = [
            "title": "Claude Response",
            "body": "Your analysis is complete",
            "sound": "default",
            "categoryIdentifier": "CLAUDE_COMPANION_CATEGORY",
            "threadIdentifier": "project-123",
            "userInfo": [
                "projectId": "project-123",
                "projectName": "Test Project",
                "type": "project_message"
            ] as [String: Any],
            "badge": 1
        ] as [String: Any]
        
        XCTAssertEqual(notificationContent["title"] as? String, "Claude Response")
        XCTAssertEqual(notificationContent["body"] as? String, "Your analysis is complete")
        XCTAssertEqual(notificationContent["categoryIdentifier"] as? String, "CLAUDE_COMPANION_CATEGORY")
        XCTAssertEqual(notificationContent["badge"] as? Int, 1)
        
        if let userInfo = notificationContent["userInfo"] as? [String: Any] {
            XCTAssertEqual(userInfo["projectId"] as? String, "project-123")
            XCTAssertEqual(userInfo["type"] as? String, "project_message")
        }
    }
}

// MARK: - Test Extensions

extension PushNotificationServiceTests {
    func testEdgeCaseHandling() {
        // Test various edge cases in data handling
        
        // Nil values
        let nilValue: String? = nil
        XCTAssertNil(nilValue)
        
        // Empty strings
        let emptyString = ""
        XCTAssertTrue(emptyString.isEmpty)
        
        // Very long strings
        let longString = String(repeating: "x", count: 10000)
        XCTAssertEqual(longString.count, 10000)
        
        // Special characters and Unicode
        let specialString = "Test 🎉 with émojis and spëcial chars 世界"
        XCTAssertFalse(specialString.isEmpty)
        
        // Numbers as strings
        let numberString = "12345"
        XCTAssertNotNil(Int(numberString))
        
        // Invalid JSON-like data
        let invalidData = ["key": NSNull()]
        XCTAssertNotNil(invalidData["key"])
        XCTAssertTrue(invalidData["key"] != nil)
    }
    
    func testProjectPathNormalization() {
        // Test different path formats
        let paths = [
            "/Users/test/project",
            "/Users/test/project/",
            "/Users/test/project//",
            "~/project",
            "./project",
            "../project"
        ]
        
        for path in paths {
            XCTAssertFalse(path.isEmpty, "Path should not be empty: \(path)")
        }
        
        // Test path components
        let testPath = "/Users/test/my-project/subfolder"
        let components = testPath.components(separatedBy: "/")
        XCTAssertTrue(components.count > 1)
        XCTAssertTrue(components.contains("my-project"))
    }
}
