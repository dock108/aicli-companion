//
//  NotificationManager.swift
//  ClaudeCompanionHost
//
//  Manages system notifications
//

import Foundation
import UserNotifications
import AppKit

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    // MARK: - Properties
    @Published var isAuthorized = false
    private lazy var notificationCenter = UNUserNotificationCenter.current()

    // MARK: - Initialization
    override private init() {
        super.init()
        setupNotifications()
    }

    // MARK: - Public Methods
    func requestAuthorization() async {
        do {
            let authorized = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                self.isAuthorized = authorized
            }
        } catch {
            print("Failed to request notification authorization: \(error)")
        }
    }

    func showNotification(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        sound: UNNotificationSound? = .default,
        badge: NSNumber? = nil,
        userInfo: [String: Any] = [:]
    ) {
        guard SettingsManager.shared.enableNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo

        if SettingsManager.shared.enableSounds, let sound = sound {
            content.sound = sound
        }

        if let badge = badge {
            content.badge = badge
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Show immediately
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
            }
        }
    }

    func showServerNotification(title: String, body: String, isError: Bool = false) {
        showNotification(
            title: title,
            body: body,
            sound: isError ? .defaultCritical : .default,
            userInfo: ["type": "server", "isError": isError]
        )
    }

    func showSessionNotification(title: String, body: String, sessionId: String) {
        showNotification(
            title: title,
            body: body,
            userInfo: ["type": "session", "sessionId": sessionId]
        )
    }

    func clearAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
    }

    func clearNotification(withIdentifier identifier: String) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: - Private Methods
    private func setupNotifications() {
        notificationCenter.delegate = self

        Task {
            await checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        await MainActor.run {
            self.isAuthorized = settings.authorizationStatus == .authorized
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification actions
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String {
            Task { @MainActor in
                switch type {
                case "server":
                    // Open activity monitor
                    NSApp.sendAction(#selector(AppCommands.openActivityMonitor), to: nil, from: nil)

                case "session":
                    if let sessionId = userInfo["sessionId"] as? String {
                        // Handle session-specific action
                        print("Session notification tapped: \(sessionId)")
                    }

                default:
                    break
                }
            }
        }

        completionHandler()
    }
}

// MARK: - App Commands
@objc protocol AppCommands {
    func openActivityMonitor()
}
