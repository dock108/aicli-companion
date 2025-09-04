//
//  SessionKeyManager.swift
//  AICLICompanion
//
//  Centralized session key management to avoid duplication
//

import Foundation

/// Centralized utility for session key generation and management
/// Eliminates duplicate session key formatting logic across the codebase
public enum SessionKeyManager {
    
    // MARK: - Session Key Generation
    
    /// Generates a UserDefaults key for storing Claude session ID for a given project path
    /// - Parameter projectPath: The project path (e.g., "/Users/name/project")
    /// - Returns: A sanitized key suitable for UserDefaults (e.g., "claude_session_Users_name_project")
    public static func sessionKey(for projectPath: String) -> String {
        let sanitizedPath = projectPath.replacingOccurrences(of: "/", with: "_")
        return "claude_session_\(sanitizedPath)"
    }
    
    /// Generates a UserDefaults key for storing session metadata
    /// - Parameter projectPath: The project path
    /// - Returns: A key for storing session metadata
    public static func sessionMetadataKey(for projectPath: String) -> String {
        let sanitizedPath = projectPath.replacingOccurrences(of: "/", with: "_")
        return "claude_session_metadata_\(sanitizedPath)"
    }
    
    /// Generates a UserDefaults key for storing session timestamps
    /// - Parameter projectPath: The project path
    /// - Returns: A key for storing when the session was last active
    public static func sessionTimestampKey(for projectPath: String) -> String {
        let sanitizedPath = projectPath.replacingOccurrences(of: "/", with: "_")
        return "claude_session_timestamp_\(sanitizedPath)"
    }
    
    // MARK: - Session Storage Helpers
    
    /// Stores a session ID for a project path
    /// - Parameters:
    ///   - sessionId: The Claude session ID to store
    ///   - projectPath: The project path
    public static func storeSessionId(_ sessionId: String, for projectPath: String) {
        let key = sessionKey(for: projectPath)
        UserDefaults.standard.set(sessionId, forKey: key)
        
        // Also store timestamp for session tracking
        let timestampKey = sessionTimestampKey(for: projectPath)
        UserDefaults.standard.set(Date(), forKey: timestampKey)
    }
    
    /// Retrieves a session ID for a project path
    /// - Parameter projectPath: The project path
    /// - Returns: The stored session ID, if any
    public static func sessionId(for projectPath: String) -> String? {
        let key = sessionKey(for: projectPath)
        return UserDefaults.standard.string(forKey: key)
    }
    
    /// Removes stored session data for a project path
    /// - Parameter projectPath: The project path to clear
    public static func clearSession(for projectPath: String) {
        let sessionKey = sessionKey(for: projectPath)
        let metadataKey = sessionMetadataKey(for: projectPath)
        let timestampKey = sessionTimestampKey(for: projectPath)
        
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: metadataKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
    }
    
    /// Gets the timestamp when a session was last active
    /// - Parameter projectPath: The project path
    /// - Returns: The last active timestamp, if available
    public static func lastActiveTimestamp(for projectPath: String) -> Date? {
        let key = sessionTimestampKey(for: projectPath)
        return UserDefaults.standard.object(forKey: key) as? Date
    }
    
    /// Checks if a session exists and is recent (within last 24 hours)
    /// - Parameter projectPath: The project path
    /// - Returns: True if session exists and is recent
    public static func hasRecentSession(for projectPath: String) -> Bool {
        guard sessionId(for: projectPath) != nil,
              let lastActive = lastActiveTimestamp(for: projectPath) else {
            return false
        }
        
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return lastActive > dayAgo
    }
    
    // MARK: - Migration Helpers
    
    /// Lists all stored session keys for cleanup/migration purposes
    /// - Returns: Array of project paths that have stored sessions
    public static func allStoredSessionPaths() -> [String] {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys
        
        return allKeys.compactMap { key in
            if key.hasPrefix("claude_session_") && !key.contains("metadata") && !key.contains("timestamp") {
                let pathPart = String(key.dropFirst("claude_session_".count))
                return pathPart.replacingOccurrences(of: "_", with: "/")
            }
            return nil
        }
    }
    
    /// Clears all stored session data (useful for logout/reset)
    public static func clearAllSessions() {
        let paths = allStoredSessionPaths()
        for path in paths {
            clearSession(for: path)
        }
    }
}