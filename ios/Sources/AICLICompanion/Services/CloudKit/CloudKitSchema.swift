import Foundation
import CloudKit

/// Centralized CloudKit schema definitions for AICLI Companion
public enum CloudKitSchema {
    
    // MARK: - Record Types
    
    public enum RecordType {
        public static let message = "Message"
        public static let session = "Session"
        public static let syncMetadata = "SyncMetadata"
        public static let device = "Device"
    }
    
    // MARK: - Message Record Fields
    
    public enum MessageFields {
        public static let content = "content"
        public static let timestamp = "timestamp"
        public static let sessionId = "sessionId"
        public static let projectPath = "projectPath"
        public static let deviceId = "deviceId"
        public static let messageType = "messageType"
        public static let requestId = "requestId"
        public static let attachments = "attachments"
        public static let readByDevices = "readByDevices"
        public static let deletedByDevices = "deletedByDevices"
        public static let syncedAt = "syncedAt"
        public static let lastModified = "lastModified"
        public static let messageHash = "messageHash"
    }
    
    // MARK: - Session Record Fields
    
    public enum SessionFields {
        public static let sessionId = "sessionId"
        public static let projectPath = "projectPath"
        public static let lastActivity = "lastActivity"
        public static let activeDevices = "activeDevices"
        public static let primaryDeviceId = "primaryDeviceId"
        public static let messageCount = "messageCount"
        public static let createdAt = "createdAt"
        public static let lastSyncedAt = "lastSyncedAt"
    }
    
    // MARK: - Device Record Fields
    
    public enum DeviceFields {
        public static let deviceId = "deviceId"
        public static let platform = "platform"
        public static let appVersion = "appVersion"
        public static let lastSeen = "lastSeen"
        public static let isActive = "isActive"
        public static let registeredAt = "registeredAt"
        public static let deviceName = "deviceName"
        public static let systemVersion = "systemVersion"
    }
    
    // MARK: - Sync Metadata Fields
    
    public enum SyncMetadataFields {
        public static let lastSyncTimestamp = "lastSyncTimestamp"
        public static let syncVersion = "syncVersion"
        public static let deviceInfo = "deviceInfo"
        public static let syncStatus = "syncStatus"
        public static let errorCount = "errorCount"
        public static let lastErrorMessage = "lastErrorMessage"
        public static let lastErrorTimestamp = "lastErrorTimestamp"
    }
    
    // MARK: - Container Configuration
    
    public static let containerIdentifier = "iCloud.com.aicli.companion"
    
    // MARK: - Subscription Names
    
    public enum Subscriptions {
        public static let messages = "MessageSubscription"
        public static let sessions = "SessionSubscription"
        public static let devices = "DeviceSubscription"
    }
    
    // MARK: - Zone Configuration
    
    public static let customZoneName = "AICLICompanionZone"
    public static let customZoneID = CKRecordZone.ID(zoneName: customZoneName)
    
    // MARK: - Sync Configuration
    
    public enum SyncConfig {
        public static let batchSize: Int = 100
        public static let maxRetries: Int = 3
        public static let syncTimeoutInterval: TimeInterval = 30.0
        public static let conflictResolutionPolicy: ConflictResolutionPolicy = .lastWriterWins
        public static let subscriptionNotificationDelay: TimeInterval = 2.0
    }
    
    // MARK: - Conflict Resolution
    
    public enum ConflictResolutionPolicy: String, Codable {
        case lastWriterWins = "lastWriterWins"
        case firstWriterWins = "firstWriterWins"
        case merge = "merge"
    }
}

/// CloudKit error handling extensions
extension CloudKitSchema {
    
    public enum SyncError: Error, LocalizedError {
        case iCloudUnavailable
        case accountNotAvailable
        case networkUnavailable
        case quotaExceeded
        case unknownError(Error)
        case recordNotFound
        case conflictResolutionFailed
        case subscriptionFailed
        case zoneNotFound
        case permissionFailure
        
        public var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud is not available. Please check your iCloud settings."
            case .accountNotAvailable:
                return "iCloud account is not available. Please sign in to iCloud."
            case .networkUnavailable:
                return "Network connection is unavailable. Sync will resume when connected."
            case .quotaExceeded:
                return "iCloud storage quota exceeded. Please free up space."
            case .unknownError(let error):
                return "An unknown error occurred: \(error.localizedDescription)"
            case .recordNotFound:
                return "The requested record was not found."
            case .conflictResolutionFailed:
                return "Failed to resolve sync conflict."
            case .subscriptionFailed:
                return "Failed to set up CloudKit subscriptions."
            case .zoneNotFound:
                return "CloudKit zone not found."
            case .permissionFailure:
                return "Permission denied for CloudKit operation."
            }
        }
    }
}

/// CloudKit record convenience extensions
extension CKRecord {
    
    /// Create a Message record with proper field types
    public static func messageRecord(
        recordName: String? = nil,
        zoneID: CKRecordZone.ID = CloudKitSchema.customZoneID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName ?? UUID().uuidString, zoneID: zoneID)
        return CKRecord(recordType: CloudKitSchema.RecordType.message, recordID: recordID)
    }
    
    /// Create a Session record with proper field types
    public static func sessionRecord(
        recordName: String? = nil,
        zoneID: CKRecordZone.ID = CloudKitSchema.customZoneID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName ?? UUID().uuidString, zoneID: zoneID)
        return CKRecord(recordType: CloudKitSchema.RecordType.session, recordID: recordID)
    }
    
    /// Create a Device record with proper field types
    public static func deviceRecord(
        recordName: String? = nil,
        zoneID: CKRecordZone.ID = CloudKitSchema.customZoneID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName ?? UUID().uuidString, zoneID: zoneID)
        return CKRecord(recordType: CloudKitSchema.RecordType.device, recordID: recordID)
    }
    
    /// Create a SyncMetadata record with proper field types
    public static func syncMetadataRecord(
        recordName: String? = nil,
        zoneID: CKRecordZone.ID = CloudKitSchema.customZoneID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName ?? UUID().uuidString, zoneID: zoneID)
        return CKRecord(recordType: CloudKitSchema.RecordType.syncMetadata, recordID: recordID)
    }
}