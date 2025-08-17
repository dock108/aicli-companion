import Foundation
import SwiftUI

/// Extension to ChatViewModel that adds interactive session lifecycle management
@available(iOS 16.0, macOS 13.0, *)
extension ChatViewModel {
    
    // Helper to access logger
    private var sessionLogger: LoggingManager {
        return LoggingManager.shared
    }
    
    // Helper to get server URL
    private func getServerURL() -> String? {
        // Try to get from active session or settings
        if let activeSession = activeSession as? ExtendedProjectSession,
           let serverURL = activeSession.serverURL {
            return serverURL
        }
        // Fallback to settings
        return SettingsManager.shared.serverURL?.absoluteString
    }
    
    // Helper to get project session ID
    func getProjectSessionId(_ projectPath: String) -> String? {
        // This would need to be exposed in ChatViewModel or use a different approach
        return currentSessionId
    }
    
    // Helper to update project session ID
    func updateProjectSessionId(_ projectPath: String, sessionId: String) {
        // Store in currentSessionId for now
        currentSessionId = sessionId
    }
    
    // MARK: - Session Lifecycle Management
    
    /// Start monitoring the current session for expiry
    @MainActor
    func startSessionMonitoring() {
        guard let sessionId = currentSessionId else { return }
        
        sessionLogger.debug("Starting session monitoring for \(sessionId)")
        
        // Start keep-alive monitoring
        SessionKeepAliveService.shared.startMonitoring(
            sessionId: sessionId,
            projectPath: currentProject?.path ?? ""
        )
    }
    
    /// Stop monitoring the current session
    @MainActor
    func stopSessionMonitoring() {
        guard let sessionId = currentSessionId else { return }
        
        sessionLogger.debug("Stopping session monitoring for \(sessionId)")
        
        SessionKeepAliveService.shared.stopMonitoring(sessionId: sessionId)
    }
    
    /// Check and refresh session status from server
    @MainActor
    func refreshSessionStatus() async {
        guard let sessionId = currentSessionId,
              let serverURL = getServerURL() else { return }
        
        do {
            let url = URL(string: "\(serverURL)/api/sessions/interactive/\(sessionId)/status")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Update session metadata
                if let active = json["active"] as? Bool,
                   let messageCount = json["messageCount"] as? Int {
                    
                    sessionLogger.info("Session status refreshed: \(sessionId), active: \(active), messages: \(messageCount)")
                    
                    // If session is no longer active, handle expiry
                    if !active {
                        await handleSessionExpired(sessionId: sessionId)
                    }
                }
            }
        } catch {
            sessionLogger.error("Failed to refresh session status for \(sessionId): \(error.localizedDescription)")
        }
    }
    
    /// Handle session expiry
    @MainActor
    private func handleSessionExpired(sessionId: String) async {
        sessionLogger.warning("Session expired: \(sessionId)")
        
        // Clear current session ID
        if currentSessionId == sessionId {
            currentSessionId = nil
            
            // Show expiry message to user
            let expiryMessage = Message(
                content: "⚠️ Your Claude session has expired. Your next message will start a new session.",
                sender: .system,
                timestamp: Date()
            )
            // Append directly to the published messages array
            messages.append(expiryMessage)
            
            // Also persist the message
            if let project = currentProject,
               let sessionId = currentSessionId {
                MessagePersistenceService.shared.appendMessage(
                    expiryMessage,
                    to: project.path,
                    sessionId: sessionId,
                    project: project
                )
            }
            
            // Stop monitoring
            stopSessionMonitoring()
        }
    }
    
    /// Extend the current session
    @MainActor
    func extendSession(withRecap: Bool = false) async -> Bool {
        guard let sessionId = currentSessionId,
              let serverURL = getServerURL() else { return false }
        
        sessionLogger.debug("Extending session \(sessionId) with recap: \(withRecap)")
        
        let extended = await SessionKeepAliveService.shared.sendKeepAlive(
            sessionId: sessionId,
            serverURL: serverURL,
            withRecap: withRecap
        )
        
        if extended {
            // Refresh status after extension
            await refreshSessionStatus()
        }
        
        return extended
    }
    
    /// Get all active interactive sessions from server
    @MainActor
    func fetchActiveSessions() async -> [InteractiveSessionInfo] {
        guard let serverURL = getServerURL() else { return [] }
        
        do {
            let url = URL(string: "\(serverURL)/api/sessions/active")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sessions = json["sessions"] as? [[String: Any]] {
                
                return sessions.compactMap { sessionData in
                    guard let sessionId = sessionData["sessionId"] as? String,
                          let projectPath = sessionData["projectPath"] as? String,
                          let createdAt = sessionData["createdAt"] as? TimeInterval,
                          let expiresAt = sessionData["expiresAt"] as? TimeInterval else {
                        return nil
                    }
                    
                    return InteractiveSessionInfo(
                        sessionId: sessionId,
                        projectPath: projectPath,
                        createdAt: Date(timeIntervalSince1970: createdAt / 1000),
                        expiresAt: Date(timeIntervalSince1970: expiresAt / 1000),
                        messageCount: sessionData["messageCount"] as? Int ?? 0,
                        isActive: true
                    )
                }
            }
        } catch {
            sessionLogger.error("Failed to fetch active sessions: \(error.localizedDescription)")
        }
        
        return []
    }
    
    /// Kill a specific interactive session
    @MainActor
    func killSession(_ sessionId: String) async -> Bool {
        guard let serverURL = getServerURL() else { return false }
        
        sessionLogger.info("Killing interactive session: \(sessionId)")
        
        do {
            let url = URL(string: "\(serverURL)/api/sessions/interactive/\(sessionId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                
                // If this was our current session, clear it
                if currentSessionId == sessionId {
                    currentSessionId = nil
                    stopSessionMonitoring()
                }
                
                return true
            }
        } catch {
            sessionLogger.error("Failed to kill session \(sessionId): \(error.localizedDescription)")
        }
        
        return false
    }
    
    // MARK: - Session State Updates
    
    /// Update when a new session is created
    @MainActor
    func onSessionCreated(sessionId: String) {
        sessionLogger.info("New interactive session created: \(sessionId) for project: \(currentProject?.path ?? "unknown")")
        
        // Store the session ID
        currentSessionId = sessionId
        
        // Start monitoring
        startSessionMonitoring()
        
        // Update project mapping
        if let project = currentProject {
            updateProjectSessionId(project.path, sessionId: sessionId)
        }
    }
    
    /// Update when switching projects
    @MainActor
    func onProjectSwitched(to project: Project) {
        // Stop monitoring old session
        stopSessionMonitoring()
        
        // Check if this project has an existing session
        if let existingSessionId = getProjectSessionId(project.path) {
            currentSessionId = existingSessionId
            
            // Check if session is still valid
            Task {
                await refreshSessionStatus()
                
                // Start monitoring if session is still active
                if currentSessionId != nil {
                    startSessionMonitoring()
                }
            }
        } else {
            // No existing session for this project
            currentSessionId = nil
        }
    }
}

// MARK: - Supporting Types

// Extended project session with server URL
struct ExtendedProjectSession: Codable {
    let sessionId: String
    let projectName: String
    let projectPath: String
    let status: String
    let startedAt: String
    let serverURL: String?
}

struct InteractiveSessionInfo {
    let sessionId: String
    let projectPath: String
    let createdAt: Date
    let expiresAt: Date
    let messageCount: Int
    let isActive: Bool
    
    var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
    
    var isExpiringSoon: Bool {
        timeRemaining < 3600 // Less than 1 hour
    }
}