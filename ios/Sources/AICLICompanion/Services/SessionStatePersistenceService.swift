import Foundation
import CoreData

/// Enhanced session state persistence service with expiry tracking and cleanup
@available(iOS 16.0, macOS 13.0, *)
class SessionStatePersistenceService: ObservableObject {
    static let shared = SessionStatePersistenceService()
    
    // MARK: - Constants
    
    /// Session expiry duration (7 days)
    private let sessionExpiryDuration: TimeInterval = 7 * 24 * 60 * 60
    
    /// Cleanup interval (1 day)
    private let cleanupInterval: TimeInterval = 24 * 60 * 60
    
    // MARK: - Properties
    
    @Published var activeSessions: [SessionStateInfo] = []
    
    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "com.aiclicompanion.session.states"
    private let lastCleanupKey = "com.aiclicompanion.session.lastCleanup"
    
    private let queue = DispatchQueue(label: "com.aiclicompanion.sessionstate", attributes: .concurrent)
    
    // MARK: - Types
    
    struct SessionStateInfo: Codable, Identifiable {
        let id: String // Session ID
        let projectId: String
        let projectName: String
        let projectPath: String
        let createdAt: Date
        let lastActiveAt: Date
        let messageCount: Int
        let aicliSessionId: String?
        let metadata: [String: String]
        
        var isExpired: Bool {
            Date().timeIntervalSince(lastActiveAt) > SessionStatePersistenceService.shared.sessionExpiryDuration
        }
        
        var expiresAt: Date {
            lastActiveAt.addingTimeInterval(SessionStatePersistenceService.shared.sessionExpiryDuration)
        }
        
        var formattedExpiry: String {
            if #available(macOS 10.15, iOS 13.0, *) {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                return formatter.localizedString(for: expiresAt, relativeTo: Date())
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return formatter.string(from: expiresAt)
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadSessions()
        performStartupCleanup()
    }
    
    // MARK: - Public Methods
    
    /// Save or update session state
    func saveSessionState(
        sessionId: String,
        projectId: String,
        projectName: String,
        projectPath: String,
        messageCount: Int,
        aicliSessionId: String?,
        metadata: [String: String] = [:]
    ) {
        queue.async(flags: .barrier) {
            var sessions = self.loadSessionsFromDefaults()
            
            // Check if session already exists
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                // Update existing session
                sessions[index] = SessionStateInfo(
                    id: sessionId,
                    projectId: projectId,
                    projectName: projectName,
                    projectPath: projectPath,
                    createdAt: sessions[index].createdAt,
                    lastActiveAt: Date(),
                    messageCount: messageCount,
                    aicliSessionId: aicliSessionId,
                    metadata: metadata
                )
            } else {
                // Create new session
                let newSession = SessionStateInfo(
                    id: sessionId,
                    projectId: projectId,
                    projectName: projectName,
                    projectPath: projectPath,
                    createdAt: Date(),
                    lastActiveAt: Date(),
                    messageCount: messageCount,
                    aicliSessionId: aicliSessionId,
                    metadata: metadata
                )
                sessions.append(newSession)
            }
            
            self.saveSessionsToDefaults(sessions)
            
            DispatchQueue.main.async {
                self.activeSessions = sessions.filter { !$0.isExpired }
            }
        }
    }
    
    /// Get session state for a project
    func getSessionState(for projectId: String) -> SessionStateInfo? {
        queue.sync {
            activeSessions.first { $0.projectId == projectId && !$0.isExpired }
        }
    }
    
    /// Get session state by session ID
    func getSessionStateById(_ sessionId: String) -> SessionStateInfo? {
        queue.sync {
            activeSessions.first { $0.id == sessionId && !$0.isExpired }
        }
    }
    
    /// Update last active time for a session
    func touchSession(_ sessionId: String) {
        queue.async(flags: .barrier) {
            var sessions = self.loadSessionsFromDefaults()
            
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                var session = sessions[index]
                session = SessionStateInfo(
                    id: session.id,
                    projectId: session.projectId,
                    projectName: session.projectName,
                    projectPath: session.projectPath,
                    createdAt: session.createdAt,
                    lastActiveAt: Date(),
                    messageCount: session.messageCount,
                    aicliSessionId: session.aicliSessionId,
                    metadata: session.metadata
                )
                sessions[index] = session
                self.saveSessionsToDefaults(sessions)
                
                DispatchQueue.main.async {
                    self.activeSessions = sessions.filter { !$0.isExpired }
                }
            }
        }
    }
    
    /// Remove a session
    func removeSession(_ sessionId: String) {
        queue.async(flags: .barrier) {
            var sessions = self.loadSessionsFromDefaults()
            sessions.removeAll { $0.id == sessionId }
            self.saveSessionsToDefaults(sessions)
            
            DispatchQueue.main.async {
                self.activeSessions = sessions.filter { !$0.isExpired }
            }
        }
    }
    
    /// Cleanup expired sessions
    func cleanupExpiredSessions() {
        queue.async(flags: .barrier) {
            let sessions = self.loadSessionsFromDefaults()
            let activeSessions = sessions.filter { !$0.isExpired }
            
            if activeSessions.count != sessions.count {
                print("🧹 Cleaning up \(sessions.count - activeSessions.count) expired sessions")
                self.saveSessionsToDefaults(activeSessions)
                
                DispatchQueue.main.async {
                    self.activeSessions = activeSessions
                }
            }
            
            // Update last cleanup time
            self.userDefaults.set(Date(), forKey: self.lastCleanupKey)
        }
    }
    
    /// Get all active (non-expired) sessions
    func getActiveSessions() -> [SessionStateInfo] {
        queue.sync {
            activeSessions.filter { !$0.isExpired }
        }
    }
    
    /// Check if a session exists and is active
    func isSessionActive(_ sessionId: String) -> Bool {
        queue.sync {
            activeSessions.contains { $0.id == sessionId && !$0.isExpired }
        }
    }
    
    /// Get session expiry information
    func getSessionExpiry(_ sessionId: String) -> Date? {
        queue.sync {
            activeSessions.first { $0.id == sessionId }?.expiresAt
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSessions() {
        queue.sync {
            let sessions = loadSessionsFromDefaults()
            DispatchQueue.main.async {
                self.activeSessions = sessions.filter { !$0.isExpired }
            }
        }
    }
    
    private func loadSessionsFromDefaults() -> [SessionStateInfo] {
        guard let data = userDefaults.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([SessionStateInfo].self, from: data) else {
            return []
        }
        return sessions
    }
    
    private func saveSessionsToDefaults(_ sessions: [SessionStateInfo]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        userDefaults.set(data, forKey: sessionsKey)
    }
    
    private func performStartupCleanup() {
        // Check if we need to perform cleanup
        let lastCleanup = userDefaults.object(forKey: lastCleanupKey) as? Date ?? Date.distantPast
        let timeSinceLastCleanup = Date().timeIntervalSince(lastCleanup)
        
        if timeSinceLastCleanup > cleanupInterval {
            print("🧹 Performing startup session cleanup")
            cleanupExpiredSessions()
        }
    }
}
