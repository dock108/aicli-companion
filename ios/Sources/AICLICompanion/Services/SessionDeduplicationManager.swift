import Foundation

/// Manages session deduplication by working directory to prevent multiple sessions for the same project
@available(iOS 16.0, macOS 13.0, *)
class SessionDeduplicationManager {
    static let shared = SessionDeduplicationManager()
    
    // MARK: - Private Properties
    
    /// Maps working directory paths to session IDs
    private var activeSessions: [String: SessionInfo] = [:]
    
    /// User defaults key for persistence
    private let persistenceKey = "com.aiclicompanion.session.deduplication"
    
    /// Lock for thread safety
    private let sessionsLock = NSLock()
    
    // MARK: - Types
    
    struct SessionInfo: Codable {
        let sessionId: String
        let workingDirectory: String
        let createdAt: Date
        let lastUsed: Date
        
        var isExpired: Bool {
            // Sessions expire after 7 days of inactivity
            return Date().timeIntervalSince(lastUsed) > 7 * 24 * 60 * 60
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadPersistedSessions()
        performCleanupExpiredSessions()
    }
    
    // MARK: - Public Methods
    
    /// Get or create a session for the given working directory
    /// - Parameters:
    ///   - workingDirectory: The project's working directory path
    ///   - verifySession: Async function to verify if session is still valid with server
    /// - Returns: Session ID (existing or newly generated)
    func getOrCreateSession(
        for workingDirectory: String,
        verifySession: @escaping (String) async throws -> Bool
    ) async throws -> String {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        // Normalize the path
        let normalizedPath = normalizeWorkingDirectory(workingDirectory)
        
        // Check for existing session
        if let existingSession = activeSessions[normalizedPath] {
            // Verify session is still valid
            do {
                let isValid = try await verifySession(existingSession.sessionId)
                if isValid {
                    // Update last used time
                    let updatedSession = SessionInfo(
                        sessionId: existingSession.sessionId,
                        workingDirectory: existingSession.workingDirectory,
                        createdAt: existingSession.createdAt,
                        lastUsed: Date()
                    )
                    activeSessions[normalizedPath] = updatedSession
                    persistSessions()
                    
                    print("✅ Reusing existing session \(existingSession.sessionId) for \(normalizedPath)")
                    return existingSession.sessionId
                } else {
                    // Session is invalid, remove it
                    print("⚠️ Session \(existingSession.sessionId) is invalid, removing")
                    activeSessions.removeValue(forKey: normalizedPath)
                }
            } catch {
                print("❌ Failed to verify session \(existingSession.sessionId): \(error)")
                activeSessions.removeValue(forKey: normalizedPath)
            }
        }
        
        // Create new session ID
        let newSessionId = UUID().uuidString
        let newSession = SessionInfo(
            sessionId: newSessionId,
            workingDirectory: normalizedPath,
            createdAt: Date(),
            lastUsed: Date()
        )
        
        activeSessions[normalizedPath] = newSession
        persistSessions()
        
        print("🆕 Created new session \(newSessionId) for \(normalizedPath)")
        return newSessionId
    }
    
    /// Remove a session from tracking
    func removeSession(for workingDirectory: String) {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        let normalizedPath = normalizeWorkingDirectory(workingDirectory)
        if let removed = activeSessions.removeValue(forKey: normalizedPath) {
            print("🗑 Removed session \(removed.sessionId) for \(normalizedPath)")
            persistSessions()
        }
    }
    
    /// Get session ID for a working directory if it exists
    func getSessionId(for workingDirectory: String) -> String? {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        let normalizedPath = normalizeWorkingDirectory(workingDirectory)
        return activeSessions[normalizedPath]?.sessionId
    }
    
    /// Update last used time for a session
    func touchSession(for workingDirectory: String) {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        let normalizedPath = normalizeWorkingDirectory(workingDirectory)
        if let existing = activeSessions[normalizedPath] {
            let updated = SessionInfo(
                sessionId: existing.sessionId,
                workingDirectory: existing.workingDirectory,
                createdAt: existing.createdAt,
                lastUsed: Date()
            )
            activeSessions[normalizedPath] = updated
            persistSessions()
        }
    }
    
    /// Clear all sessions
    func clearAllSessions() {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        activeSessions.removeAll()
        persistSessions()
        print("🧹 Cleared all sessions")
    }
    
    /// Clean up expired sessions
    func cleanupExpiredSessions() {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        let before = activeSessions.count
        activeSessions = activeSessions.filter { !$0.value.isExpired }
        let removed = before - activeSessions.count
        
        if removed > 0 {
            print("🧹 Cleaned up \(removed) expired sessions in SessionDeduplicationManager")
            persistSessions()
        }
    }
    
    // MARK: - Private Methods
    
    private func normalizeWorkingDirectory(_ path: String) -> String {
        // Remove trailing slashes and resolve relative paths
        let url = URL(fileURLWithPath: path).standardized
        return url.path
    }
    
    private func loadPersistedSessions() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let sessions = try? JSONDecoder().decode([String: SessionInfo].self, from: data) else {
            return
        }
        
        activeSessions = sessions
        print("📂 Loaded \(sessions.count) persisted sessions")
    }
    
    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(activeSessions) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
        print("💾 Persisted \(activeSessions.count) sessions")
    }
    
    private func performCleanupExpiredSessions() {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        
        let before = activeSessions.count
        activeSessions = activeSessions.filter { !$0.value.isExpired }
        let removed = before - activeSessions.count
        
        if removed > 0 {
            print("🧹 Cleaned up \(removed) expired sessions")
            persistSessions()
        }
    }
}