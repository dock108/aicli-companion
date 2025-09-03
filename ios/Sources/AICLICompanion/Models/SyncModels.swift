import Foundation
import CloudKit

// MARK: - Sync Operation Models

/// Represents a sync operation between local storage and CloudKit
public struct SyncOperation: Identifiable {
    public let id = UUID()
    public let type: SyncOperationType
    public let recordType: String
    public let recordID: CKRecord.ID?
    public let timestamp: Date
    public var status: SyncOperationStatus
    public var error: Error?
    public var retryCount: Int = 0
    public let maxRetries: Int = 3
    
    public init(
        type: SyncOperationType,
        recordType: String,
        recordID: CKRecord.ID? = nil,
        status: SyncOperationStatus = .pending
    ) {
        self.type = type
        self.recordType = recordType
        self.recordID = recordID
        self.timestamp = Date()
        self.status = status
    }
    
    public var canRetry: Bool {
        return retryCount < maxRetries && (status == .failed || status == .conflicted)
    }
}

public enum SyncOperationType: String, CaseIterable, Codable {
    case save = "save"
    case fetch = "fetch"
    case delete = "delete"
    case update = "update"
    case fullSync = "fullSync"
    case incrementalSync = "incrementalSync"
}

public enum SyncOperationStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case inProgress = "inProgress"
    case completed = "completed"
    case failed = "failed"
    case conflicted = "conflicted"
    case cancelled = "cancelled"
}

// MARK: - Sync Statistics

public struct SyncStatistics {
    public let totalOperations: Int
    public let pendingOperations: Int
    public let completedOperations: Int
    public let failedOperations: Int
    public let lastSyncDate: Date?
    public let syncDuration: TimeInterval?
    public let recordsSynced: Int
    public let conflictsResolved: Int
    public let errorsEncountered: Int
    
    public init(
        totalOperations: Int = 0,
        pendingOperations: Int = 0,
        completedOperations: Int = 0,
        failedOperations: Int = 0,
        lastSyncDate: Date? = nil,
        syncDuration: TimeInterval? = nil,
        recordsSynced: Int = 0,
        conflictsResolved: Int = 0,
        errorsEncountered: Int = 0
    ) {
        self.totalOperations = totalOperations
        self.pendingOperations = pendingOperations
        self.completedOperations = completedOperations
        self.failedOperations = failedOperations
        self.lastSyncDate = lastSyncDate
        self.syncDuration = syncDuration
        self.recordsSynced = recordsSynced
        self.conflictsResolved = conflictsResolved
        self.errorsEncountered = errorsEncountered
    }
    
    public var successRate: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(completedOperations) / Double(totalOperations)
    }
    
    public var failureRate: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(failedOperations) / Double(totalOperations)
    }
}

// MARK: - Sync Conflict Resolution

public struct SyncConflict: Identifiable {
    public let id = UUID()
    public let recordType: String
    public let recordID: CKRecord.ID
    public let clientRecord: CKRecord
    public let serverRecord: CKRecord
    public let detectedAt: Date
    public var resolution: ConflictResolution?
    public var resolvedAt: Date?
    
    public init(
        recordType: String,
        recordID: CKRecord.ID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        self.recordType = recordType
        self.recordID = recordID
        self.clientRecord = clientRecord
        self.serverRecord = serverRecord
        self.detectedAt = Date()
    }
}

public struct ConflictResolution {
    public let strategy: CloudKitSchema.ConflictResolutionPolicy
    public let resolvedRecord: CKRecord
    public let clientWon: Bool
    public let serverWon: Bool
    public let merged: Bool
    public let timestamp: Date
    
    public init(
        strategy: CloudKitSchema.ConflictResolutionPolicy,
        resolvedRecord: CKRecord,
        clientWon: Bool = false,
        serverWon: Bool = false,
        merged: Bool = false
    ) {
        self.strategy = strategy
        self.resolvedRecord = resolvedRecord
        self.clientWon = clientWon
        self.serverWon = serverWon
        self.merged = merged
        self.timestamp = Date()
    }
}

// MARK: - Sync Progress Tracking

public struct SyncProgress {
    public let phase: SyncPhase
    public let totalItems: Int
    public let completedItems: Int
    public let failedItems: Int
    public let currentItem: String?
    public let estimatedTimeRemaining: TimeInterval?
    public let startTime: Date
    public var endTime: Date?
    
    public init(
        phase: SyncPhase,
        totalItems: Int,
        completedItems: Int = 0,
        failedItems: Int = 0,
        currentItem: String? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        startTime: Date = Date()
    ) {
        self.phase = phase
        self.totalItems = totalItems
        self.completedItems = completedItems
        self.failedItems = failedItems
        self.currentItem = currentItem
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.startTime = startTime
    }
    
    public var progress: Double {
        guard totalItems > 0 else { return 0.0 }
        return Double(completedItems) / Double(totalItems)
    }
    
    public var remainingItems: Int {
        return totalItems - completedItems - failedItems
    }
    
    public var isComplete: Bool {
        return completedItems + failedItems >= totalItems
    }
}

public enum SyncPhase: String, CaseIterable {
    case initializing = "initializing"
    case fetchingChanges = "fetchingChanges"
    case processingMessages = "processingMessages"
    case processingSessions = "processingSessions"
    case processingDevices = "processingDevices"
    case resolvingConflicts = "resolvingConflicts"
    case uploadingChanges = "uploadingChanges"
    case finalizingSync = "finalizingSync"
    case completed = "completed"
    case failed = "failed"
    
    public var displayName: String {
        switch self {
        case .initializing:
            return "Initializing sync..."
        case .fetchingChanges:
            return "Fetching changes from iCloud..."
        case .processingMessages:
            return "Processing messages..."
        case .processingSessions:
            return "Processing sessions..."
        case .processingDevices:
            return "Processing device information..."
        case .resolvingConflicts:
            return "Resolving conflicts..."
        case .uploadingChanges:
            return "Uploading changes to iCloud..."
        case .finalizingSync:
            return "Finalizing sync..."
        case .completed:
            return "Sync completed"
        case .failed:
            return "Sync failed"
        }
    }
}

// MARK: - Device Sync State

public struct DeviceSyncState: Codable {
    public let deviceId: String
    public let deviceName: String
    public let platform: String
    public var lastSyncDate: Date?
    public var syncToken: String?
    public var pendingOperations: [String] // Operation IDs
    public var failedOperations: [String] // Operation IDs
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        deviceId: String,
        deviceName: String,
        platform: String,
        lastSyncDate: Date? = nil,
        syncToken: String? = nil
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.lastSyncDate = lastSyncDate
        self.syncToken = syncToken
        self.pendingOperations = []
        self.failedOperations = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Sync Queue Item

public struct SyncQueueItem: Identifiable, Codable {
    public let id: UUID
    public let operation: SyncOperationType
    public let recordType: String
    public let recordData: Data // Encoded record data
    public let priority: SyncPriority
    public let createdAt: Date
    public var attempts: Int = 0
    public var lastAttemptAt: Date?
    public var nextRetryAt: Date?
    public var error: String?
    
    public init(
        operation: SyncOperationType,
        recordType: String,
        recordData: Data,
        priority: SyncPriority = .normal
    ) {
        self.id = UUID()
        self.operation = operation
        self.recordType = recordType
        self.recordData = recordData
        self.priority = priority
        self.createdAt = Date()
    }
}

public enum SyncPriority: Int, Codable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    public var retryDelay: TimeInterval {
        switch self {
        case .low:
            return 300.0 // 5 minutes
        case .normal:
            return 60.0 // 1 minute
        case .high:
            return 10.0 // 10 seconds
        case .critical:
            return 5.0 // 5 seconds
        }
    }
}

// MARK: - Sync Event

public struct SyncEvent {
    public let type: SyncEventType
    public let timestamp: Date
    public let recordType: String?
    public let recordID: String?
    public let deviceId: String
    public let details: [String: Any]?
    public let error: Error?
    
    public init(
        type: SyncEventType,
        recordType: String? = nil,
        recordID: String? = nil,
        deviceId: String,
        details: [String: Any]? = nil,
        error: Error? = nil
    ) {
        self.type = type
        self.timestamp = Date()
        self.recordType = recordType
        self.recordID = recordID
        self.deviceId = deviceId
        self.details = details
        self.error = error
    }
}

public enum SyncEventType: String, CaseIterable {
    case syncStarted = "syncStarted"
    case syncCompleted = "syncCompleted"
    case syncFailed = "syncFailed"
    case recordSaved = "recordSaved"
    case recordFetched = "recordFetched"
    case recordDeleted = "recordDeleted"
    case conflictDetected = "conflictDetected"
    case conflictResolved = "conflictResolved"
    case operationQueued = "operationQueued"
    case operationRetried = "operationRetried"
    case deviceRegistered = "deviceRegistered"
    case deviceUnregistered = "deviceUnregistered"
    case subscriptionCreated = "subscriptionCreated"
    case notificationReceived = "notificationReceived"
}

// MARK: - Sync Configuration

public struct SyncConfiguration: Codable {
    public var isEnabled: Bool = true
    public var syncInterval: TimeInterval = 300.0 // 5 minutes
    public var batchSize: Int = 50
    public var maxRetries: Int = 3
    public var conflictResolutionPolicy: CloudKitSchema.ConflictResolutionPolicy = .lastWriterWins
    public var syncOnAppLaunch: Bool = true
    public var syncOnAppForeground: Bool = true
    public var syncOnNetworkChange: Bool = true
    public var backgroundSyncEnabled: Bool = false
    public var retentionDays: Int = 30
    public var enableTelemetry: Bool = true
    
    public init() {}
    
    public var nextSyncDate: Date {
        return Date().addingTimeInterval(syncInterval)
    }
}

// MARK: - Helper Extensions

extension Array where Element == SyncOperation {
    
    public var pendingOperations: [SyncOperation] {
        return filter { $0.status == .pending }
    }
    
    public var failedOperations: [SyncOperation] {
        return filter { $0.status == .failed }
    }
    
    public var completedOperations: [SyncOperation] {
        return filter { $0.status == .completed }
    }
    
    public var retryableOperations: [SyncOperation] {
        return filter { $0.canRetry }
    }
}

extension Array where Element == SyncQueueItem {
    
    public var sortedByPriority: [SyncQueueItem] {
        return sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    public var readyForRetry: [SyncQueueItem] {
        let now = Date()
        return filter { item in
            guard let nextRetry = item.nextRetryAt else { return true }
            return now >= nextRetry
        }
    }
}