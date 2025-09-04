import Foundation
import CloudKit

// MARK: - CloudKit Extensions for Message Model

extension Message {
    // MARK: - CloudKit Properties (Internal)
    
    /// CloudKit record ID (not part of Codable)
    internal var cloudKitRecordID: CKRecord.ID? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.cloudKitRecordID) as? CKRecord.ID
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.cloudKitRecordID, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// Last CloudKit sync timestamp (not part of Codable)
    internal var lastSyncedAt: Date? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.lastSyncedAt) as? Date
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.lastSyncedAt, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// CloudKit sync status (not part of Codable)
    internal var cloudKitSyncStatus: SyncStatus {
        get {
            if let status = objc_getAssociatedObject(self, &AssociatedKeys.syncStatus) as? SyncStatus {
                return status
            }
            return needsSync ? .pending : .synced
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.syncStatus, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// Message hash for duplicate detection (not part of Codable)
    internal var messageHash: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.messageHash) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.messageHash, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    // MARK: - CloudKit Conversion
    
    /// Convert Message to CloudKit record
    public mutating func toCKRecord(projectPath: String? = nil, deviceId: String? = nil) -> CKRecord {
        let record: CKRecord
        
        if let existingRecordID = cloudKitRecordID {
            record = CKRecord(recordType: CloudKitSchema.RecordType.message, recordID: existingRecordID)
        } else {
            record = CKRecord.messageRecord(recordName: id.uuidString)
            cloudKitRecordID = record.recordID
        }
        
        // Core message fields
        record[CloudKitSchema.MessageFields.content] = content
        record[CloudKitSchema.MessageFields.timestamp] = timestamp
        record[CloudKitSchema.MessageFields.messageType] = type.rawValue
        record[CloudKitSchema.MessageFields.sender] = sender.rawValue  // Save sender to CloudKit
        record[CloudKitSchema.MessageFields.requestId] = requestId
        
        // Session and project info
        if let sessionId = metadata?.sessionId {
            record[CloudKitSchema.MessageFields.sessionId] = sessionId
        }
        
        // Use the instance projectPath first, then parameter, then try to extract
        if let projectPath = self.projectPath ?? projectPath ?? extractProjectPath() {
            record[CloudKitSchema.MessageFields.projectPath] = projectPath
        }
        
        if let deviceId = deviceId {
            record[CloudKitSchema.MessageFields.deviceId] = deviceId
        }
        
        // Sync metadata
        record[CloudKitSchema.MessageFields.readByDevices] = readByDevices
        record[CloudKitSchema.MessageFields.deletedByDevices] = deletedByDevices
        record[CloudKitSchema.MessageFields.syncedAt] = syncedAt ?? Date()
        record[CloudKitSchema.MessageFields.lastModified] = Date()
        
        // Message hash for duplicate detection
        let hash = messageHash ?? generateMessageHash()
        record[CloudKitSchema.MessageFields.messageHash] = hash
        messageHash = hash
        
        // Handle attachments if present
        if let richContent = richContent,
           case .attachments(let attachmentsData) = richContent.data {
            let attachmentInfo = attachmentsData.attachments.map { attachment in
                return [
                    "id": attachment.id.uuidString,
                    "name": attachment.name,
                    "mimeType": attachment.mimeType,
                    "size": attachment.size
                ]
            }
            
            // Convert to Data for CloudKit storage
            if let attachmentData = try? JSONSerialization.data(withJSONObject: attachmentInfo) {
                record[CloudKitSchema.MessageFields.attachments] = attachmentData
            }
        }
        
        return record
    }
    
    /// Create Message from CloudKit record
    public static func from(ckRecord: CKRecord) -> Message? {
        guard let content = ckRecord[CloudKitSchema.MessageFields.content] as? String,
              let timestamp = ckRecord[CloudKitSchema.MessageFields.timestamp] as? Date,
              let messageTypeString = ckRecord[CloudKitSchema.MessageFields.messageType] as? String,
              let messageType = MessageType(rawValue: messageTypeString) else {
            return nil
        }
        
        // Extract sender from CloudKit record
        let senderString = ckRecord[CloudKitSchema.MessageFields.sender] as? String ?? "assistant"
        let sender = MessageSender(rawValue: senderString) ?? .assistant
        
        // Extract session info for metadata
        let sessionId = ckRecord[CloudKitSchema.MessageFields.sessionId] as? String ?? ""
        let metadata = AICLIMessageMetadata(sessionId: sessionId, duration: 0)
        
        let requestId = ckRecord[CloudKitSchema.MessageFields.requestId] as? String
        
        // Create message
        var message = Message(
            id: UUID(uuidString: ckRecord.recordID.recordName) ?? UUID(),
            content: content,
            sender: sender,  // Use the sender from CloudKit
            timestamp: timestamp,
            type: messageType,
            metadata: metadata,
            requestId: requestId
        )
        
        // Set CloudKit properties
        message.cloudKitRecordID = ckRecord.recordID
        message.readByDevices = ckRecord[CloudKitSchema.MessageFields.readByDevices] as? [String] ?? []
        message.deletedByDevices = ckRecord[CloudKitSchema.MessageFields.deletedByDevices] as? [String] ?? []
        message.syncedAt = ckRecord[CloudKitSchema.MessageFields.syncedAt] as? Date
        message.lastSyncedAt = ckRecord[CloudKitSchema.MessageFields.syncedAt] as? Date
        message.messageHash = ckRecord[CloudKitSchema.MessageFields.messageHash] as? String
        message.needsSync = false
        message.cloudKitSyncStatus = .synced
        
        return message
    }
    
    // MARK: - Sync Helper Methods
    
    /// Mark message as read by a specific device
    public mutating func markAsRead(by deviceId: String) {
        if !readByDevices.contains(deviceId) {
            readByDevices.append(deviceId)
            needsSync = true
            cloudKitSyncStatus = .pending
        }
    }
    
    /// Mark message as deleted by a specific device
    public mutating func markAsDeleted(by deviceId: String) {
        if !deletedByDevices.contains(deviceId) {
            deletedByDevices.append(deviceId)
            needsSync = true
            cloudKitSyncStatus = .pending
        }
    }
    
    /// Check if message is deleted for a specific device
    public func isDeleted(for deviceId: String) -> Bool {
        return deletedByDevices.contains(deviceId)
    }
    
    /// Check if message is read by a specific device
    public func isRead(by deviceId: String) -> Bool {
        return readByDevices.contains(deviceId)
    }
    
    /// Generate message hash for duplicate detection
    internal func generateMessageHash() -> String {
        let hashContent = [
            content,
            metadata?.sessionId ?? "",
            type.rawValue,
            timestamp.timeIntervalSince1970.description
        ].joined(separator: "|")
        
        return hashContent.sha256
    }
    
    /// Extract project path from metadata or content
    private func extractProjectPath() -> String? {
        // This would extract project path from message content or metadata
        // Implementation depends on how project paths are stored in messages
        return metadata?.additionalInfo?["projectPath"]?.value as? String
    }
    
    /// Update sync status after successful sync
    public mutating func markAsSynced() {
        syncedAt = Date()
        lastSyncedAt = Date()
        needsSync = false
        cloudKitSyncStatus = .synced
    }
    
    /// Mark message as needing sync
    public mutating func markAsNeedingSync() {
        needsSync = true
        cloudKitSyncStatus = .pending
    }
}

// MARK: - Associated Object Keys

private struct AssociatedKeys {
    static var cloudKitRecordID = "cloudKitRecordID"
    static var lastSyncedAt = "lastSyncedAt"
    static var syncStatus = "syncStatus"
    static var messageHash = "messageHash"
}

// MARK: - String Hashing Extension

private extension String {
    var sha256: String {
        guard let data = data(using: .utf8) else { return "" }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto

// MARK: - CloudKit Query Helpers for Messages

extension Message {
    /// Create a query to find messages by session ID
    public static func cloudKitQueryForSession(_ sessionId: String) -> CKQuery {
        return CloudKitSchema.messageQuery(for: sessionId)
    }
    
    /// Create a query to find messages by project path
    public static func cloudKitQueryForProject(_ projectPath: String) -> CKQuery {
        return CloudKitSchema.messageQuery(for: projectPath)
    }
    
    /// Create a query to find recent messages
    public static func recentMessagesQuery(hours: Int = 24) -> CKQuery {
        return CloudKitSchema.recentMessagesQuery(hours: hours)
    }
}

// MARK: - Batch Operations

extension Array where Element == Message {
    /// Convert array of messages to CloudKit records
    public mutating func toCKRecords(projectPath: String? = nil, deviceId: String? = nil) -> [CKRecord] {
        return compactMap { message in
            var mutableMessage = message
            return mutableMessage.toCKRecord(projectPath: projectPath, deviceId: deviceId)
        }
    }
    
    /// Create array of messages from CloudKit records
    public static func from(ckRecords: [CKRecord]) -> [Message] {
        return ckRecords.compactMap { record in
            Message.from(ckRecord: record)
        }
    }
    
    /// Get all messages that need syncing
    public var needingSync: [Message] {
        return filter { $0.needsSync }
    }
    
    /// Mark all messages as synced
    public mutating func markAllAsSynced() {
        for index in indices {
            self[index].markAsSynced()
        }
    }
}

// MARK: - MessageCore Typealias for Backwards Compatibility (deprecated)

// Use Message directly instead of MessageCore
