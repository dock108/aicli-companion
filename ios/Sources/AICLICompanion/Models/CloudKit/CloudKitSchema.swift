import CloudKit
import Foundation

// MARK: - Record Types
public enum CKRecordType {
    static let message = "Message"
    static let session = "Session"
    static let syncMetadata = "SyncMetadata"
}

// MARK: - Field Keys
public enum CKField {
    // Message fields
    static let messageId = "messageId"
    static let content = "content"
    static let sender = "sender"
    static let timestamp = "timestamp"
    static let projectPath = "projectPath"
    static let sessionId = "sessionId"
    static let readByDevices = "readByDevices"
    static let deletedByDevices = "deletedByDevices"
    static let messageType = "messageType"
    static let metadata = "metadata"
    
    // Session fields
    static let claudeSessionId = "claudeSessionId"
    static let projectName = "projectName"
    static let createdAt = "createdAt"
    static let lastActivity = "lastActivity"
    static let deviceId = "deviceId"
    
    // Sync metadata
    static let lastSyncDate = "lastSyncDate"
    static let syncVersion = "syncVersion"
}