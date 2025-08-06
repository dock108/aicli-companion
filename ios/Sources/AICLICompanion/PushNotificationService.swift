import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Service that manages push notifications for Claude responses
@available(iOS 17.0, macOS 14.0, *)
public class PushNotificationService: NSObject, ObservableObject {
    public static let shared = PushNotificationService()

    @Published public var isAuthorized = false
    @Published public var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()

    override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    public func requestAuthorization() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

            await MainActor.run {
                self.isAuthorized = granted
                self.checkAuthorizationStatus()
            }

            if granted {
                print("✅ Push notification authorization granted")
                await setupCategories()

                // Register for remote notifications
                await MainActor.run {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
            } else {
                print("❌ Push notification authorization denied")
            }
        } catch {
            print("❌ Failed to request notification authorization: \(error)")
        }
    }

    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Categories

    private func setupCategories() async {
        // Define actions for Claude response notifications
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Response",
            options: [.foreground]
        )

        let copyAction = UNNotificationAction(
            identifier: "COPY_ACTION",
            title: "Copy",
            options: []
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: [.destructive]
        )

        // Create category
        let claudeResponseCategory = UNNotificationCategory(
            identifier: "CLAUDE_RESPONSE",
            actions: [viewAction, copyAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Claude has responded",
            categorySummaryFormat: "%u Claude responses",
            options: [.customDismissAction]
        )

        // Register categories
        notificationCenter.setNotificationCategories([claudeResponseCategory])
    }

    // MARK: - Send Notifications

    /// Send a notification for a completed Claude response
    func sendResponseNotification(
        sessionId: String,
        projectName: String,
        responsePreview: String,
        totalChunks: Int,
        fullResponse: String? = nil
    ) async {
        guard isAuthorized else {
            print("⚠️ Push notifications not authorized")
            return
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Claude Response Ready"
        content.subtitle = projectName
        content.body = truncateForNotification(responsePreview)
        content.sound = .default
        content.categoryIdentifier = "CLAUDE_RESPONSE"
        content.threadIdentifier = sessionId

        // Add metadata
        content.userInfo = [
            "sessionId": sessionId,
            "projectName": projectName,
            "totalChunks": totalChunks,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Store full response if provided (for copy action)
        if let fullResponse = fullResponse {
            content.userInfo["fullResponse"] = fullResponse
        }

        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create request
        let requestId = "claude-\(sessionId)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: requestId,
            content: content,
            trigger: trigger
        )

        // Schedule notification
        do {
            try await notificationCenter.add(request)
            print("📱 Push notification scheduled for session \(sessionId)")
        } catch {
            print("❌ Failed to schedule notification: \(error)")
        }
    }

    /// Send a notification for an error
    func sendErrorNotification(
        sessionId: String,
        projectName: String,
        error: String
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Error"
        content.subtitle = projectName
        content.body = error
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "claude-error-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await notificationCenter.add(request)
    }

    // MARK: - Helper Methods

    private func truncateForNotification(_ text: String, maxLength: Int = 150) -> String {
        if text.count <= maxLength {
            return text
        }

        let truncated = String(text.prefix(maxLength))
        return truncated + "..."
    }

    // MARK: - Clear Notifications

    func clearNotifications(for sessionId: String) {
        notificationCenter.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .filter { notification in
                    if let userInfo = notification.request.content.userInfo as? [String: Any],
                       let notificationSessionId = userInfo["sessionId"] as? String {
                        return notificationSessionId == sessionId
                    }
                    return false
                }
                .map { $0.request.identifier }

            if !identifiers.isEmpty {
                self.notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
                print("🧹 Cleared \(identifiers.count) notifications for session \(sessionId)")
            }
        }
    }

    func clearAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

@available(iOS 17.0, macOS 14.0, *)
extension PushNotificationService: UNUserNotificationCenterDelegate {
    // Handle notification while app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        #if os(iOS)
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
        #else
        completionHandler([.alert, .sound, .badge])
        #endif
    }

    // Handle notification actions
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "VIEW_ACTION", UNNotificationDefaultActionIdentifier:
            // User tapped notification or view action
            if let sessionId = userInfo["sessionId"] as? String {
                // Post notification to open the specific session
                NotificationCenter.default.post(
                    name: .openChatSession,
                    object: nil,
                    userInfo: ["sessionId": sessionId]
                )
            }

        case "COPY_ACTION":
            // Copy full response to clipboard
            if let fullResponse = userInfo["fullResponse"] as? String {
                #if os(iOS)
                UIPasteboard.general.string = fullResponse
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullResponse, forType: .string)
                #endif
                print("📋 Response copied to clipboard")
            }

        case "DISMISS_ACTION":
            // Just dismiss
            break

        default:
            break
        }

        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openChatSession = Notification.Name("openChatSession")
}
