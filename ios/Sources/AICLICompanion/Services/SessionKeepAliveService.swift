import Foundation
import Combine
#if os(iOS)
import UIKit
import UserNotifications
#endif

/// Service that manages automatic keep-alive for interactive Claude sessions
/// Monitors session activity and sends keep-alive requests before expiry
@available(iOS 16.0, macOS 13.0, *)
@MainActor
class SessionKeepAliveService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = SessionKeepAliveService()
    
    // MARK: - Configuration
    private let warningThreshold: TimeInterval = 60 * 60 * 20  // 20 hours - warn before 24h expiry
    private let autoExtendThreshold: TimeInterval = 60 * 60 * 23  // 23 hours - auto-extend
    private let checkInterval: TimeInterval = 60 * 30  // Check every 30 minutes
    
    // MARK: - Published State
    @Published var isMonitoring = false
    @Published var lastKeepAliveTime: Date?
    @Published var nextCheckTime: Date?
    @Published var sessionWarnings: [String: SessionWarning] = [:]
    
    // MARK: - Private State
    private var monitoringTimer: Timer?
    private var activeSessions: Set<String> = []
    private let logger = LoggingManager.shared
    
    // MARK: - Session Tracking
    struct SessionWarning {
        let sessionId: String
        let projectPath: String
        let warningTime: Date
        let expiresAt: Date
        var wasNotified: Bool = false
    }
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public API
    
    /// Start monitoring a session for expiry
    func startMonitoring(sessionId: String, projectPath: String) {
        logger.debug("Starting keep-alive monitoring for session \(sessionId) at \(projectPath)")
        
        activeSessions.insert(sessionId)
        
        // Start monitoring timer if not already running
        if monitoringTimer == nil {
            startMonitoringTimer()
        }
        
        // Immediately check this session
        Task {
            await checkSession(sessionId: sessionId, projectPath: projectPath)
        }
    }
    
    /// Stop monitoring a session
    func stopMonitoring(sessionId: String) {
        logger.debug("Stopping keep-alive monitoring for session \(sessionId)")
        
        activeSessions.remove(sessionId)
        sessionWarnings.removeValue(forKey: sessionId)
        
        // Stop timer if no sessions left
        if activeSessions.isEmpty {
            stopMonitoringTimer()
        }
    }
    
    /// Manually trigger a keep-alive for a session
    func sendKeepAlive(sessionId: String, serverURL: String, withRecap: Bool = false) async -> Bool {
        logger.debug("Sending keep-alive request for \(sessionId), withRecap: \(withRecap)")
        
        do {
            let url = URL(string: "\(serverURL)/api/sessions/keep-alive")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "sessionId": sessionId,
                "action": withRecap ? "recap" : "extend"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                lastKeepAliveTime = Date()
                
                // Parse response for recap if requested
                if withRecap,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let recap = json["recap"] as? String {
                    await handleRecapResponse(sessionId: sessionId, recap: recap)
                }
                
                logger.info("Keep-alive successful for session \(sessionId)")
                
                return true
            }
        } catch {
            logger.error("Keep-alive failed for \(sessionId): \(error.localizedDescription)")
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // Listen for app lifecycle events
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func appDidBecomeActive() {
        // Check all sessions when app becomes active
        Task {
            await checkAllSessions()
        }
    }
    
    @objc private func appWillResignActive() {
        // Schedule background task if needed
        scheduleBackgroundKeepAlive()
    }
    
    private func startMonitoringTimer() {
        stopMonitoringTimer()
        
        isMonitoring = true
        nextCheckTime = Date().addingTimeInterval(checkInterval)
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.checkAllSessions()
            }
        }
    }
    
    private func stopMonitoringTimer() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        nextCheckTime = nil
    }
    
    private func checkAllSessions() async {
        logger.debug("Checking \(activeSessions.count) sessions for keep-alive")
        
        nextCheckTime = Date().addingTimeInterval(checkInterval)
        
        // Get session details from ChatViewModel
        guard let chatViewModel = await getActiveChatViewModel() else { return }
        
        for sessionId in activeSessions {
            if let project = await chatViewModel.getProjectForSession(sessionId) {
                await checkSession(sessionId: sessionId, projectPath: project.path)
            }
        }
    }
    
    private func checkSession(sessionId: String, projectPath: String) async {
        // Get session status from server
        guard let serverURL = await getServerURL() else { return }
        
        do {
            let url = URL(string: "\(serverURL)/api/sessions/interactive/\(sessionId)/status")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let expiresAt = json["expiresAt"] as? TimeInterval {
                
                let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000)
                let timeUntilExpiry = expiryDate.timeIntervalSinceNow
                
                // Check if we need to warn
                if timeUntilExpiry < warningThreshold && timeUntilExpiry > 0 {
                    await handleSessionWarning(
                        sessionId: sessionId,
                        projectPath: projectPath,
                        expiresAt: expiryDate
                    )
                }
                
                // Check if we need to auto-extend
                if timeUntilExpiry < autoExtendThreshold && timeUntilExpiry > 0 {
                    let extended = await sendKeepAlive(
                        sessionId: sessionId,
                        serverURL: serverURL,
                        withRecap: false
                    )
                    
                    if extended {
                        // Clear warning after successful extension
                        sessionWarnings.removeValue(forKey: sessionId)
                    }
                }
            }
        } catch {
            logger.error("Failed to check session \(sessionId) status: \(error.localizedDescription)")
        }
    }
    
    private func handleSessionWarning(sessionId: String, projectPath: String, expiresAt: Date) async {
        // Check if we already warned about this
        if let existing = sessionWarnings[sessionId], existing.wasNotified {
            return
        }
        
        let warning = SessionWarning(
            sessionId: sessionId,
            projectPath: projectPath,
            warningTime: Date(),
            expiresAt: expiresAt,
            wasNotified: false
        )
        
        sessionWarnings[sessionId] = warning
        
        // Send local notification
        await sendExpiryNotification(for: warning)
    }
    
    private func sendExpiryNotification(for warning: SessionWarning) async {
        #if os(iOS)
        let content = UNMutableNotificationContent()
        content.title = "Session Expiring Soon"
        content.body = "Your Claude session for \(warning.projectPath.split(separator: "/").last ?? "project") will expire soon. Open the app to extend it."
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "SESSION_EXPIRY"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "session-expiry-\(warning.sessionId)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            
            // Mark as notified
            var updatedWarning = warning
            updatedWarning.wasNotified = true
            sessionWarnings[warning.sessionId] = updatedWarning
        } catch {
            logger.error("Failed to send expiry notification: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func handleRecapResponse(sessionId: String, recap: String) async {
        // Store recap in message history or show to user
        logger.info("Received session recap for \(sessionId), length: \(recap.count)")
        
        // Could emit this through a publisher for UI to display
    }
    
    private func scheduleBackgroundKeepAlive() {
        #if os(iOS)
        // Schedule background task for keep-alive
        // This would use BGTaskScheduler on iOS 13+
        logger.debug("Scheduling background keep-alive task")
        #endif
    }
    
    // MARK: - Helper Methods
    
    private func getActiveChatViewModel() async -> ChatViewModel? {
        return await MainActor.run {
            return ChatViewModel.shared
        }
    }
    
    private func getServerURL() async -> String? {
        return await MainActor.run { () -> String? in
            // Get server URL from settings instead of session
            return SettingsManager.shared.serverURL?.absoluteString
        }
    }
}

// MARK: - ChatViewModel Extension

extension ChatViewModel {
    /// Get project for a given session ID
    @MainActor
    func getProjectForSession(_ sessionId: String) -> Project? {
        // If this is the current session, return current project
        if sessionId == currentSessionId {
            return currentProject
        }
        // Otherwise, we'd need to look it up from persistence
        // For now, return current project if session matches
        return nil
    }
}