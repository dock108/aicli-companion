//
//  NotificationManagerTests.swift
//  AICLICompanionHostTests
//
//  Unit tests for NotificationManager
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class NotificationManagerTests: XCTestCase {
    
    var mockNotificationManager: MockNotificationManager!
    
    override func setUp() {
        super.setUp()
        mockNotificationManager = MockNotificationManager()
    }
    
    override func tearDown() {
        mockNotificationManager.reset()
        mockNotificationManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testNotificationManagerInitialState() throws {
        XCTAssertTrue(mockNotificationManager.hasPermission)
        XCTAssertTrue(mockNotificationManager.notifications.isEmpty)
    }
    
    func testNotificationManagerSingleton() throws {
        let manager1 = MockNotificationManager.shared
        let manager2 = MockNotificationManager.shared
        
        // Should be the same instance
        XCTAssertTrue(manager1 === manager2)
    }
    
    // MARK: - Permission Tests
    
    func testRequestPermissionGranted() async throws {
        mockNotificationManager.permissionGranted = true
        
        let granted = await mockNotificationManager.requestPermission()
        
        XCTAssertTrue(granted)
        XCTAssertTrue(mockNotificationManager.requestPermissionCalled)
        XCTAssertEqual(mockNotificationManager.requestPermissionCallCount, 1)
        XCTAssertTrue(mockNotificationManager.hasPermission)
    }
    
    func testRequestPermissionDenied() async throws {
        mockNotificationManager.permissionGranted = false
        
        let granted = await mockNotificationManager.requestPermission()
        
        XCTAssertFalse(granted)
        XCTAssertTrue(mockNotificationManager.requestPermissionCalled)
        XCTAssertFalse(mockNotificationManager.hasPermission)
    }
    
    func testRequestPermissionMultipleTimes() async throws {
        _ = await mockNotificationManager.requestPermission()
        _ = await mockNotificationManager.requestPermission()
        _ = await mockNotificationManager.requestPermission()
        
        XCTAssertEqual(mockNotificationManager.requestPermissionCallCount, 3)
    }
    
    // MARK: - Basic Notification Tests
    
    func testShowNotification() throws {
        mockNotificationManager.showNotification(
            title: "Test Title",
            body: "Test Body"
        )
        
        XCTAssertTrue(mockNotificationManager.showNotificationCalled)
        XCTAssertEqual(mockNotificationManager.showNotificationCallCount, 1)
        XCTAssertEqual(mockNotificationManager.notifications.count, 1)
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, "Test Title")
        XCTAssertEqual(notification.body, "Test Body")
        XCTAssertTrue(notification.sound)
    }
    
    func testShowNotificationWithoutSound() throws {
        mockNotificationManager.showNotification(
            title: "Silent",
            body: "No sound",
            sound: false
        )
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, "Silent")
        XCTAssertEqual(notification.body, "No sound")
        XCTAssertFalse(notification.sound)
    }
    
    func testShowNotificationWithoutPermission() throws {
        mockNotificationManager.hasPermission = false
        
        mockNotificationManager.showNotification(
            title: "No Permission",
            body: "Should not appear"
        )
        
        XCTAssertTrue(mockNotificationManager.showNotificationCalled)
        XCTAssertTrue(mockNotificationManager.notifications.isEmpty)
    }
    
    func testShowNotificationWhenFailureConfigured() throws {
        mockNotificationManager.shouldFailToShowNotification = true
        
        mockNotificationManager.showNotification(
            title: "Fail",
            body: "Should fail"
        )
        
        XCTAssertTrue(mockNotificationManager.showNotificationCalled)
        XCTAssertTrue(mockNotificationManager.notifications.isEmpty)
    }
    
    // MARK: - Specialized Notification Tests
    
    func testShowServerStartedNotification() throws {
        let port = 3001
        
        mockNotificationManager.showServerStartedNotification(port: port)
        
        XCTAssertEqual(mockNotificationManager.notifications.count, 1)
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, "Server Started")
        XCTAssertEqual(notification.body, "AICLI Companion server is running on port \(port)")
    }
    
    func testShowServerStoppedNotification() throws {
        mockNotificationManager.showServerStoppedNotification()
        
        XCTAssertEqual(mockNotificationManager.notifications.count, 1)
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, "Server Stopped")
        XCTAssertEqual(notification.body, "AICLI Companion server has been stopped")
    }
    
    func testShowServerErrorNotification() throws {
        let errorMessage = "Port already in use"
        
        mockNotificationManager.showServerErrorNotification(error: errorMessage)
        
        XCTAssertEqual(mockNotificationManager.notifications.count, 1)
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, "Server Error")
        XCTAssertEqual(notification.body, errorMessage)
    }
    
    // MARK: - Multiple Notifications Tests
    
    func testMultipleNotifications() throws {
        mockNotificationManager.showNotification(title: "First", body: "Body 1")
        mockNotificationManager.showNotification(title: "Second", body: "Body 2")
        mockNotificationManager.showNotification(title: "Third", body: "Body 3")
        
        XCTAssertEqual(mockNotificationManager.notifications.count, 3)
        XCTAssertEqual(mockNotificationManager.showNotificationCallCount, 3)
        
        XCTAssertEqual(mockNotificationManager.notifications[0].title, "First")
        XCTAssertEqual(mockNotificationManager.notifications[1].title, "Second")
        XCTAssertEqual(mockNotificationManager.notifications[2].title, "Third")
    }
    
    func testNotificationTimestamps() throws {
        let before = Date()
        
        mockNotificationManager.showNotification(title: "Test", body: "Body")
        
        let after = Date()
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertGreaterThanOrEqual(notification.timestamp, before)
        XCTAssertLessThanOrEqual(notification.timestamp, after)
    }
    
    // MARK: - Test Helper Methods
    
    func testGetLastNotification() throws {
        mockNotificationManager.showNotification(title: "First", body: "1")
        mockNotificationManager.showNotification(title: "Second", body: "2")
        mockNotificationManager.showNotification(title: "Last", body: "3")
        
        let last = mockNotificationManager.getLastNotification()
        
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.title, "Last")
        XCTAssertEqual(last?.body, "3")
    }
    
    func testGetLastNotificationWhenEmpty() throws {
        let last = mockNotificationManager.getLastNotification()
        XCTAssertNil(last)
    }
    
    func testGetAllNotifications() throws {
        mockNotificationManager.showNotification(title: "A", body: "1")
        mockNotificationManager.showNotification(title: "B", body: "2")
        mockNotificationManager.showNotification(title: "C", body: "3")
        
        let all = mockNotificationManager.getAllNotifications()
        
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].title, "A")
        XCTAssertEqual(all[1].title, "B")
        XCTAssertEqual(all[2].title, "C")
    }
    
    func testClearNotifications() throws {
        // Add some notifications
        mockNotificationManager.showNotification(title: "1", body: "A")
        mockNotificationManager.showNotification(title: "2", body: "B")
        XCTAssertEqual(mockNotificationManager.notifications.count, 2)
        
        // Clear them
        mockNotificationManager.clearNotifications()
        
        XCTAssertTrue(mockNotificationManager.notifications.isEmpty)
    }
    
    // MARK: - Reset Tests
    
    func testResetClearsAllState() async throws {
        // Set up complex state
        mockNotificationManager.hasPermission = false
        mockNotificationManager.permissionGranted = false
        mockNotificationManager.shouldFailToShowNotification = true
        
        // Add notifications
        mockNotificationManager.showNotification(title: "Test", body: "Body")
        mockNotificationManager.showServerStartedNotification(port: 8080)
        
        // Trigger tracking
        _ = await mockNotificationManager.requestPermission()
        
        // Verify state before reset
        XCTAssertFalse(mockNotificationManager.hasPermission)
        XCTAssertTrue(mockNotificationManager.requestPermissionCalled)
        XCTAssertTrue(mockNotificationManager.showNotificationCalled)
        
        // Reset
        mockNotificationManager.reset()
        
        // Verify everything is cleared
        XCTAssertTrue(mockNotificationManager.notifications.isEmpty)
        XCTAssertFalse(mockNotificationManager.requestPermissionCalled)
        XCTAssertEqual(mockNotificationManager.requestPermissionCallCount, 0)
        XCTAssertFalse(mockNotificationManager.showNotificationCalled)
        XCTAssertEqual(mockNotificationManager.showNotificationCallCount, 0)
        XCTAssertTrue(mockNotificationManager.permissionGranted)
        XCTAssertFalse(mockNotificationManager.shouldFailToShowNotification)
        XCTAssertTrue(mockNotificationManager.hasPermission)
    }
    
    // MARK: - Notification Equality Tests
    
    func testNotificationEquality() throws {
        let sameTime = Date()
        
        let notification1 = MockNotificationManager.MockNotification(
            title: "Same",
            body: "Same Body",
            timestamp: sameTime,
            sound: true
        )
        
        let notification2 = MockNotificationManager.MockNotification(
            title: "Same",
            body: "Same Body",
            timestamp: sameTime,
            sound: true
        )
        
        // Notifications with same content should be equal
        XCTAssertEqual(notification1, notification2)
        
        let notification3 = MockNotificationManager.MockNotification(
            title: "Different",
            body: "Same Body",
            timestamp: sameTime,
            sound: true
        )
        
        // Different title means not equal
        XCTAssertNotEqual(notification1, notification3)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyTitleAndBody() throws {
        mockNotificationManager.showNotification(title: "", body: "")
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, "")
        XCTAssertEqual(notification.body, "")
    }
    
    func testVeryLongNotificationContent() throws {
        let longTitle = String(repeating: "Title ", count: 100)
        let longBody = String(repeating: "Body text ", count: 500)
        
        mockNotificationManager.showNotification(title: longTitle, body: longBody)
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, longTitle)
        XCTAssertEqual(notification.body, longBody)
    }
    
    func testUnicodeInNotifications() throws {
        let unicodeTitle = "Test 🚀 Emoji"
        let unicodeBody = "Special chars: ñ é 中文 العربية"
        
        mockNotificationManager.showNotification(title: unicodeTitle, body: unicodeBody)
        
        let notification = mockNotificationManager.notifications.first!
        XCTAssertEqual(notification.title, unicodeTitle)
        XCTAssertEqual(notification.body, unicodeBody)
    }
}