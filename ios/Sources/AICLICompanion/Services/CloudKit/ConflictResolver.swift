import Foundation
import CloudKit
import OSLog

/// Handles CloudKit sync conflicts using various resolution strategies
public class ConflictResolver {
    
    // MARK: - Properties
    
    private let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "AICLICompanion", category: "ConflictResolver")
    
    // MARK: - Public Methods
    
    /// Resolve conflicts for message records
    public func resolveMessageConflict(
        clientRecord: CKRecord,
        serverRecord: CKRecord,
        policy: CloudKitSchema.ConflictResolutionPolicy = .lastWriterWins
    ) -> CKRecord {
        logger.info("Resolving message conflict with policy: \(String(describing: policy))")
        
        switch policy {
        case .lastWriterWins:
            return resolveWithLastWriterWins(clientRecord: clientRecord, serverRecord: serverRecord)
        case .firstWriterWins:
            return resolveWithFirstWriterWins(clientRecord: clientRecord, serverRecord: serverRecord)
        case .merge:
            return resolveMessageWithMerge(clientRecord: clientRecord, serverRecord: serverRecord)
        }
    }
    
    /// Resolve conflicts for session records
    public func resolveSessionConflict(
        clientRecord: CKRecord,
        serverRecord: CKRecord,
        policy: CloudKitSchema.ConflictResolutionPolicy = .lastWriterWins
    ) -> CKRecord {
        logger.info("Resolving session conflict with policy: \(String(describing: policy))")
        
        switch policy {
        case .lastWriterWins:
            return resolveWithLastWriterWins(clientRecord: clientRecord, serverRecord: serverRecord)
        case .firstWriterWins:
            return resolveWithFirstWriterWins(clientRecord: clientRecord, serverRecord: serverRecord)
        case .merge:
            return resolveSessionWithMerge(clientRecord: clientRecord, serverRecord: serverRecord)
        }
    }
    
    /// Resolve conflicts for device records
    public func resolveDeviceConflict(
        clientRecord: CKRecord,
        serverRecord: CKRecord,
        policy: CloudKitSchema.ConflictResolutionPolicy = .lastWriterWins
    ) -> CKRecord {
        logger.info("Resolving device conflict with policy: \(String(describing: policy))")
        
        switch policy {
        case .lastWriterWins:
            return resolveWithLastWriterWins(clientRecord: clientRecord, serverRecord: serverRecord)
        case .firstWriterWins:
            return resolveWithFirstWriterWins(clientRecord: clientRecord, serverRecord: serverRecord)
        case .merge:
            return resolveDeviceWithMerge(clientRecord: clientRecord, serverRecord: serverRecord)
        }
    }
    
    // MARK: - Basic Resolution Strategies
    
    private func resolveWithLastWriterWins(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        let clientModified = clientRecord.modificationDate ?? Date.distantPast
        let serverModified = serverRecord.modificationDate ?? Date.distantPast
        
        if clientModified >= serverModified {
            logger.debug("Client record wins (newer)")
            return clientRecord
        } else {
            logger.debug("Server record wins (newer)")
            return serverRecord
        }
    }
    
    private func resolveWithFirstWriterWins(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        let clientCreated = clientRecord.creationDate ?? Date.distantFuture
        let serverCreated = serverRecord.creationDate ?? Date.distantFuture
        
        if clientCreated <= serverCreated {
            logger.debug("Client record wins (older)")
            return clientRecord
        } else {
            logger.debug("Server record wins (older)")
            return serverRecord
        }
    }
    
    // MARK: - Message-Specific Merge Resolution
    
    private func resolveMessageWithMerge(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        logger.debug("Performing merge resolution for message record")
        
        // For messages, we generally want to preserve the original content
        // and merge metadata like read/deleted status
        let resolvedRecord = clientRecord.copy() as! CKRecord
        
        // Merge read and deleted device arrays
        mergeDeviceArrays(
            clientRecord: clientRecord,
            serverRecord: serverRecord,
            resolvedRecord: resolvedRecord,
            fieldName: CloudKitSchema.MessageFields.readByDevices
        )
        
        mergeDeviceArrays(
            clientRecord: clientRecord,
            serverRecord: serverRecord,
            resolvedRecord: resolvedRecord,
            fieldName: CloudKitSchema.MessageFields.deletedByDevices
        )
        
        // Take the latest sync timestamp
        let clientSyncedAt = clientRecord[CloudKitSchema.MessageFields.syncedAt] as? Date
        let serverSyncedAt = serverRecord[CloudKitSchema.MessageFields.syncedAt] as? Date
        
        let latestSyncedAt = max(clientSyncedAt ?? Date.distantPast, serverSyncedAt ?? Date.distantPast)
        resolvedRecord[CloudKitSchema.MessageFields.syncedAt] = latestSyncedAt
        
        // Update last modified to current time
        resolvedRecord[CloudKitSchema.MessageFields.lastModified] = Date()
        
        return resolvedRecord
    }
    
    // MARK: - Session-Specific Merge Resolution
    
    private func resolveSessionWithMerge(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        logger.debug("Performing merge resolution for session record")
        
        let resolvedRecord = clientRecord.copy() as! CKRecord
        
        // Merge active devices arrays
        mergeDeviceArrays(
            clientRecord: clientRecord,
            serverRecord: serverRecord,
            resolvedRecord: resolvedRecord,
            fieldName: CloudKitSchema.SessionFields.activeDevices
        )
        
        // Take the latest activity timestamp
        let clientActivity = clientRecord[CloudKitSchema.SessionFields.lastActivity] as? Date ?? Date.distantPast
        let serverActivity = serverRecord[CloudKitSchema.SessionFields.lastActivity] as? Date ?? Date.distantPast
        
        resolvedRecord[CloudKitSchema.SessionFields.lastActivity] = max(clientActivity, serverActivity)
        
        // Take the higher message count
        let clientCount = clientRecord[CloudKitSchema.SessionFields.messageCount] as? Int ?? 0
        let serverCount = serverRecord[CloudKitSchema.SessionFields.messageCount] as? Int ?? 0
        
        resolvedRecord[CloudKitSchema.SessionFields.messageCount] = max(clientCount, serverCount)
        
        // Primary device: prefer the one that's most recently active
        let clientPrimary = clientRecord[CloudKitSchema.SessionFields.primaryDeviceId] as? String
        let serverPrimary = serverRecord[CloudKitSchema.SessionFields.primaryDeviceId] as? String
        
        if clientActivity >= serverActivity {
            resolvedRecord[CloudKitSchema.SessionFields.primaryDeviceId] = clientPrimary
        } else {
            resolvedRecord[CloudKitSchema.SessionFields.primaryDeviceId] = serverPrimary
        }
        
        return resolvedRecord
    }
    
    // MARK: - Device-Specific Merge Resolution
    
    private func resolveDeviceWithMerge(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord {
        logger.debug("Performing merge resolution for device record")
        
        let resolvedRecord = clientRecord.copy() as! CKRecord
        
        // Take the latest last seen timestamp
        let clientLastSeen = clientRecord[CloudKitSchema.DeviceFields.lastSeen] as? Date ?? Date.distantPast
        let serverLastSeen = serverRecord[CloudKitSchema.DeviceFields.lastSeen] as? Date ?? Date.distantPast
        
        resolvedRecord[CloudKitSchema.DeviceFields.lastSeen] = max(clientLastSeen, serverLastSeen)
        
        // Take the active status from the most recently seen device
        if clientLastSeen >= serverLastSeen {
            resolvedRecord[CloudKitSchema.DeviceFields.isActive] = clientRecord[CloudKitSchema.DeviceFields.isActive]
        } else {
            resolvedRecord[CloudKitSchema.DeviceFields.isActive] = serverRecord[CloudKitSchema.DeviceFields.isActive]
        }
        
        // Prefer client device info (app version, system version) as it's more current
        resolvedRecord[CloudKitSchema.DeviceFields.appVersion] = clientRecord[CloudKitSchema.DeviceFields.appVersion]
        resolvedRecord[CloudKitSchema.DeviceFields.systemVersion] = clientRecord[CloudKitSchema.DeviceFields.systemVersion]
        
        return resolvedRecord
    }
    
    // MARK: - Helper Methods
    
    private func mergeDeviceArrays(
        clientRecord: CKRecord,
        serverRecord: CKRecord,
        resolvedRecord: CKRecord,
        fieldName: String
    ) {
        let clientDevices = Set(clientRecord[fieldName] as? [String] ?? [])
        let serverDevices = Set(serverRecord[fieldName] as? [String] ?? [])
        
        let mergedDevices = clientDevices.union(serverDevices)
        resolvedRecord[fieldName] = Array(mergedDevices).sorted()
    }
}

// MARK: - Error Handling

extension ConflictResolver {
    
    public enum ConflictResolutionError: Error, LocalizedError {
        case incompatibleRecordTypes
        case missingRequiredFields
        case corruptedRecord
        case resolutionStrategyNotSupported
        
        public var errorDescription: String? {
            switch self {
            case .incompatibleRecordTypes:
                return "Cannot resolve conflicts between different record types"
            case .missingRequiredFields:
                return "One or more records are missing required fields"
            case .corruptedRecord:
                return "One or more records appear to be corrupted"
            case .resolutionStrategyNotSupported:
                return "The specified conflict resolution strategy is not supported"
            }
        }
    }
}

// MARK: - Conflict Resolution Result

public struct ConflictResolutionResult {
    public let resolvedRecord: CKRecord
    public let strategy: CloudKitSchema.ConflictResolutionPolicy
    public let clientWon: Bool
    public let serverWon: Bool
    public let merged: Bool
    public let timestamp: Date
    
    public init(
        resolvedRecord: CKRecord,
        strategy: CloudKitSchema.ConflictResolutionPolicy,
        clientWon: Bool = false,
        serverWon: Bool = false,
        merged: Bool = false
    ) {
        self.resolvedRecord = resolvedRecord
        self.strategy = strategy
        self.clientWon = clientWon
        self.serverWon = serverWon
        self.merged = merged
        self.timestamp = Date()
    }
}

// MARK: - Logger Extension for Conflict Resolution

extension Logger {
    fileprivate init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "AICLICompanion", category: category)
    }
}