//
//  MockNotificationManager.swift
//  AICLICompanionHostTests
//
//  Mock notification manager for unit testing without system notifications
//

import Foundation
@testable import AICLICompanionHost

@MainActor
class MockNotificationManager: ObservableObject {
    // MARK: - Notification Storage
    struct MockNotification: Equatable {
        let title: String
        let body: String
        let timestamp: Date
        let sound: Bool
    }

    private(set) var notifications: [MockNotification] = []

    // MARK: - Test Tracking Properties
    var requestPermissionCalled = false
    var requestPermissionCallCount = 0
    var showNotificationCalled = false
    var showNotificationCallCount = 0

    // Test control properties
    var permissionGranted = true
    var shouldFailToShowNotification = false

    // MARK: - Published Properties
    @Published var hasPermission: Bool = true

    // MARK: - Singleton
    static let shared = MockNotificationManager()

    // MARK: - Public Methods

    func requestPermission() async -> Bool {
        requestPermissionCalled = true
        requestPermissionCallCount += 1

        hasPermission = permissionGranted
        return permissionGranted
    }

    func showNotification(title: String, body: String, sound: Bool = true) {
        showNotificationCalled = true
        showNotificationCallCount += 1

        guard !shouldFailToShowNotification else {
            return
        }

        guard hasPermission else {
            return
        }

        let notification = MockNotification(
            title: title,
            body: body,
            timestamp: Date(),
            sound: sound
        )

        notifications.append(notification)
    }

    func showServerStartedNotification(port: Int) {
        showNotification(
            title: "Server Started",
            body: "AICLI Companion server is running on port \(port)"
        )
    }

    func showServerStoppedNotification() {
        showNotification(
            title: "Server Stopped",
            body: "AICLI Companion server has been stopped"
        )
    }

    func showServerErrorNotification(error: String) {
        showNotification(
            title: "Server Error",
            body: error
        )
    }

    // MARK: - Test Helpers

    func getLastNotification() -> MockNotification? {
        return notifications.last
    }

    func getAllNotifications() -> [MockNotification] {
        return notifications
    }

    func clearNotifications() {
        notifications.removeAll()
    }

    func reset() {
        notifications.removeAll()

        requestPermissionCalled = false
        requestPermissionCallCount = 0
        showNotificationCalled = false
        showNotificationCallCount = 0

        permissionGranted = true
        shouldFailToShowNotification = false
        hasPermission = true
    }
}
