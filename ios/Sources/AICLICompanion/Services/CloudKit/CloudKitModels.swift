import Foundation
import CloudKit

// MARK: - CloudKit Sync Status

public enum SyncStatus: String, CaseIterable, Codable {
    case pending
    case syncing
    case synced
    case failed
    case conflicted
}

// MARK: - Device Info for CloudKit

public struct DeviceInfo: Codable {
    public let deviceId: String
    public let platform: String
    public let appVersion: String
    public let systemVersion: String
    public let deviceName: String
    public let registeredAt: Date
    public var lastSeen: Date
    public var isActive: Bool
    
    public init(
        deviceId: String,
        platform: String = "iOS",
        appVersion: String,
        systemVersion: String,
        deviceName: String,
        registeredAt: Date = Date(),
        lastSeen: Date = Date(),
        isActive: Bool = true
    ) {
        self.deviceId = deviceId
        self.platform = platform
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.deviceName = deviceName
        self.registeredAt = registeredAt
        self.lastSeen = lastSeen
        self.isActive = isActive
    }
}

// MARK: - Session Info for CloudKit

public struct SessionInfo: Codable {
    public let sessionId: String
    public let projectPath: String
    public var lastActivity: Date
    public var activeDevices: [String]
    public var primaryDeviceId: String?
    public var messageCount: Int
    public let createdAt: Date
    public var lastSyncedAt: Date?
    
    public init(
        sessionId: String,
        projectPath: String,
        lastActivity: Date = Date(),
        activeDevices: [String] = [],
        primaryDeviceId: String? = nil,
        messageCount: Int = 0,
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.lastActivity = lastActivity
        self.activeDevices = activeDevices
        self.primaryDeviceId = primaryDeviceId
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Sync Metadata

public struct SyncMetadata: Codable {
    public var lastSyncTimestamp: Date
    public var syncVersion: Int
    public var deviceInfo: DeviceInfo
    public var syncStatus: SyncStatus
    public var errorCount: Int
    public var lastErrorMessage: String?
    public var lastErrorTimestamp: Date?
    
    public init(
        lastSyncTimestamp: Date = Date(),
        syncVersion: Int = 1,
        deviceInfo: DeviceInfo,
        syncStatus: SyncStatus = .pending,
        errorCount: Int = 0,
        lastErrorMessage: String? = nil,
        lastErrorTimestamp: Date? = nil
    ) {
        self.lastSyncTimestamp = lastSyncTimestamp
        self.syncVersion = syncVersion
        self.deviceInfo = deviceInfo
        self.syncStatus = syncStatus
        self.errorCount = errorCount
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorTimestamp = lastErrorTimestamp
    }
}

// MARK: - CloudKit Conversion Extensions

extension DeviceInfo {
    /// Convert DeviceInfo to CloudKit record
    public func toCKRecord(recordName: String? = nil) -> CKRecord {
        let record = CKRecord.deviceRecord(recordName: recordName)
        
        record[CloudKitSchema.DeviceFields.deviceId] = deviceId
        record[CloudKitSchema.DeviceFields.platform] = platform
        record[CloudKitSchema.DeviceFields.appVersion] = appVersion
        record[CloudKitSchema.DeviceFields.systemVersion] = systemVersion
        record[CloudKitSchema.DeviceFields.deviceName] = deviceName
        record[CloudKitSchema.DeviceFields.registeredAt] = registeredAt
        record[CloudKitSchema.DeviceFields.lastSeen] = lastSeen
        record[CloudKitSchema.DeviceFields.isActive] = isActive ? 1 : 0
        
        return record
    }
    
    /// Create DeviceInfo from CloudKit record
    public static func from(ckRecord: CKRecord) -> DeviceInfo? {
        guard let deviceId = ckRecord[CloudKitSchema.DeviceFields.deviceId] as? String,
              let platform = ckRecord[CloudKitSchema.DeviceFields.platform] as? String,
              let appVersion = ckRecord[CloudKitSchema.DeviceFields.appVersion] as? String,
              let systemVersion = ckRecord[CloudKitSchema.DeviceFields.systemVersion] as? String,
              let deviceName = ckRecord[CloudKitSchema.DeviceFields.deviceName] as? String,
              let registeredAt = ckRecord[CloudKitSchema.DeviceFields.registeredAt] as? Date,
              let lastSeen = ckRecord[CloudKitSchema.DeviceFields.lastSeen] as? Date,
              let isActiveInt = ckRecord[CloudKitSchema.DeviceFields.isActive] as? Int else {
            return nil
        }
        
        return DeviceInfo(
            deviceId: deviceId,
            platform: platform,
            appVersion: appVersion,
            systemVersion: systemVersion,
            deviceName: deviceName,
            registeredAt: registeredAt,
            lastSeen: lastSeen,
            isActive: isActiveInt == 1
        )
    }
}

extension SessionInfo {
    /// Convert SessionInfo to CloudKit record
    public func toCKRecord(recordName: String? = nil) -> CKRecord {
        let record = CKRecord.sessionRecord(recordName: recordName)
        
        record[CloudKitSchema.SessionFields.sessionId] = sessionId
        record[CloudKitSchema.SessionFields.projectPath] = projectPath
        record[CloudKitSchema.SessionFields.lastActivity] = lastActivity
        record[CloudKitSchema.SessionFields.activeDevices] = activeDevices
        record[CloudKitSchema.SessionFields.primaryDeviceId] = primaryDeviceId
        record[CloudKitSchema.SessionFields.messageCount] = messageCount
        record[CloudKitSchema.SessionFields.createdAt] = createdAt
        record[CloudKitSchema.SessionFields.lastSyncedAt] = lastSyncedAt
        
        return record
    }
    
    /// Create SessionInfo from CloudKit record
    public static func from(ckRecord: CKRecord) -> SessionInfo? {
        guard let sessionId = ckRecord[CloudKitSchema.SessionFields.sessionId] as? String,
              let projectPath = ckRecord[CloudKitSchema.SessionFields.projectPath] as? String,
              let lastActivity = ckRecord[CloudKitSchema.SessionFields.lastActivity] as? Date,
              let activeDevices = ckRecord[CloudKitSchema.SessionFields.activeDevices] as? [String],
              let messageCount = ckRecord[CloudKitSchema.SessionFields.messageCount] as? Int,
              let createdAt = ckRecord[CloudKitSchema.SessionFields.createdAt] as? Date else {
            return nil
        }
        
        let primaryDeviceId = ckRecord[CloudKitSchema.SessionFields.primaryDeviceId] as? String
        let lastSyncedAt = ckRecord[CloudKitSchema.SessionFields.lastSyncedAt] as? Date
        
        return SessionInfo(
            sessionId: sessionId,
            projectPath: projectPath,
            lastActivity: lastActivity,
            activeDevices: activeDevices,
            primaryDeviceId: primaryDeviceId,
            messageCount: messageCount,
            createdAt: createdAt,
            lastSyncedAt: lastSyncedAt
        )
    }
}

extension SyncMetadata {
    /// Convert SyncMetadata to CloudKit record
    public func toCKRecord(recordName: String? = nil) -> CKRecord {
        let record = CKRecord.syncMetadataRecord(recordName: recordName)
        
        record[CloudKitSchema.SyncMetadataFields.lastSyncTimestamp] = lastSyncTimestamp
        record[CloudKitSchema.SyncMetadataFields.syncVersion] = syncVersion
        record[CloudKitSchema.SyncMetadataFields.syncStatus] = syncStatus.rawValue
        record[CloudKitSchema.SyncMetadataFields.errorCount] = errorCount
        record[CloudKitSchema.SyncMetadataFields.lastErrorMessage] = lastErrorMessage
        record[CloudKitSchema.SyncMetadataFields.lastErrorTimestamp] = lastErrorTimestamp
        
        // Store device info as encoded data
        if let deviceInfoData = try? JSONEncoder().encode(deviceInfo) {
            record[CloudKitSchema.SyncMetadataFields.deviceInfo] = deviceInfoData
        }
        
        return record
    }
    
    /// Create SyncMetadata from CloudKit record
    public static func from(ckRecord: CKRecord) -> SyncMetadata? {
        guard let lastSyncTimestamp = ckRecord[CloudKitSchema.SyncMetadataFields.lastSyncTimestamp] as? Date,
              let syncVersion = ckRecord[CloudKitSchema.SyncMetadataFields.syncVersion] as? Int,
              let syncStatusString = ckRecord[CloudKitSchema.SyncMetadataFields.syncStatus] as? String,
              let syncStatus = SyncStatus(rawValue: syncStatusString),
              let errorCount = ckRecord[CloudKitSchema.SyncMetadataFields.errorCount] as? Int,
              let deviceInfoData = ckRecord[CloudKitSchema.SyncMetadataFields.deviceInfo] as? Data,
              let deviceInfo = try? JSONDecoder().decode(DeviceInfo.self, from: deviceInfoData) else {
            return nil
        }
        
        let lastErrorMessage = ckRecord[CloudKitSchema.SyncMetadataFields.lastErrorMessage] as? String
        let lastErrorTimestamp = ckRecord[CloudKitSchema.SyncMetadataFields.lastErrorTimestamp] as? Date
        
        return SyncMetadata(
            lastSyncTimestamp: lastSyncTimestamp,
            syncVersion: syncVersion,
            deviceInfo: deviceInfo,
            syncStatus: syncStatus,
            errorCount: errorCount,
            lastErrorMessage: lastErrorMessage,
            lastErrorTimestamp: lastErrorTimestamp
        )
    }
}

// MARK: - CloudKit Query Helpers

extension CloudKitSchema {
    /// Create a predicate to fetch messages for a specific session
    public static func messageQuery(for sessionId: String) -> CKQuery {
        let predicate = NSPredicate(format: "%K == %@", MessageFields.sessionId, sessionId)
        let query = CKQuery(recordType: RecordType.message, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: MessageFields.timestamp, ascending: true)]
        return query
    }
    
    /// Create a predicate to fetch messages for a specific project
    public static func messageQuery(for projectPath: String, limit: Int? = nil) -> CKQuery {
        let predicate = NSPredicate(format: "%K == %@", MessageFields.projectPath, projectPath)
        let query = CKQuery(recordType: RecordType.message, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: MessageFields.timestamp, ascending: false)]
        return query
    }
    
    /// Create a predicate to fetch recent messages (last 24 hours)
    public static func recentMessagesQuery(hours: Int = 24) -> CKQuery {
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
        let predicate = NSPredicate(format: "%K > %@", MessageFields.timestamp, cutoffDate as NSDate)
        let query = CKQuery(recordType: RecordType.message, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: MessageFields.timestamp, ascending: false)]
        return query
    }
    
    /// Create a predicate to fetch active sessions
    public static func activeSessionsQuery(since: Date) -> CKQuery {
        let predicate = NSPredicate(format: "%K > %@", SessionFields.lastActivity, since as NSDate)
        let query = CKQuery(recordType: RecordType.session, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: SessionFields.lastActivity, ascending: false)]
        return query
    }
    
    /// Create a predicate to fetch device info for current user
    public static func deviceQuery(for deviceId: String) -> CKQuery {
        let predicate = NSPredicate(format: "%K == %@", DeviceFields.deviceId, deviceId)
        return CKQuery(recordType: RecordType.device, predicate: predicate)
    }
}
