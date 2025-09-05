import Foundation
import CloudKit
import Combine
import OSLog
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Main CloudKit synchronization service for AICLI Companion
@MainActor
public class CloudKitSyncManager: ObservableObject {
    // MARK: - Singleton
    
    public static let shared = CloudKitSyncManager()
    
    // MARK: - Published Properties
    
    @Published public var iCloudAvailable: Bool = false
    @Published public var syncStatus: SyncStatus = .pending
    @Published public var lastSyncDate: Date?
    @Published public var syncProgress: Double = 0.0
    @Published public var errorMessage: String?
    @Published public var isInitialSyncComplete: Bool = false
    
    // MARK: - Private Properties
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let conflictResolver = ConflictResolver()
    private let logger = LoggerFactory.cloudKitSync
    
    private var subscriptions = Set<AnyCancellable>()
    private var syncQueue: OperationQueue
    private var customZone: CKRecordZone?
    private var changeToken: CKServerChangeToken?
    private var pendingOperations: Set<String> = []
    
    // Device info
    private let deviceInfo: DeviceInfo
    
    // MARK: - Initialization
    
    public init() {
        // Initialize CloudKit container
        self.container = CKContainer(identifier: CloudKitSchema.containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
        
        // Initialize device info
        #if canImport(UIKit)
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let platform = "iOS"
        let systemVersion = UIDevice.current.systemVersion
        let deviceName = UIDevice.current.name
        #else
        let deviceId = UUID().uuidString
        let platform = "macOS"
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceName = ProcessInfo.processInfo.hostName
        #endif
        
        self.deviceInfo = DeviceInfo(
            deviceId: deviceId,
            platform: platform,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            systemVersion: systemVersion,
            deviceName: deviceName
        )
        
        // Configure sync queue
        self.syncQueue = OperationQueue()
        self.syncQueue.maxConcurrentOperationCount = 1
        self.syncQueue.qualityOfService = .userInitiated
        
        Task {
            await initializeCloudKit()
        }
    }
    
    // MARK: - Public Methods
    
    /// Initialize CloudKit services
    public func initializeCloudKit() async {
        print("☁️ CloudKitSyncManager: Starting CloudKit initialization...")
        logger.info("Initializing CloudKit services")
        
        do {
            // Check iCloud account status
            print("☁️ CloudKitSyncManager: Checking iCloud account status...")
            let accountStatus = try await container.accountStatus()
            print("☁️ CloudKitSyncManager: Account status: \(accountStatus)")
            
            switch accountStatus {
            case .available:
                iCloudAvailable = true
                print("✅ CloudKitSyncManager: iCloud account available")
                logger.info("iCloud account available")
                
                await setupCloudKitServices()
                
            case .noAccount:
                iCloudAvailable = false
                errorMessage = "No iCloud account found. Please sign in to iCloud."
                print("❌ CloudKitSyncManager: No iCloud account")
                logger.error("No iCloud account")
                
            case .restricted:
                iCloudAvailable = false
                errorMessage = "iCloud access is restricted on this device."
                print("❌ CloudKitSyncManager: iCloud access restricted")
                logger.error("iCloud access restricted")
                
            case .couldNotDetermine:
                iCloudAvailable = false
                errorMessage = "Could not determine iCloud status."
                print("❌ CloudKitSyncManager: Could not determine iCloud status")
                logger.error("Could not determine iCloud status")
                
            case .temporarilyUnavailable:
                iCloudAvailable = false
                errorMessage = "iCloud is temporarily unavailable. Please try again later."
                print("❌ CloudKitSyncManager: iCloud temporarily unavailable")
                logger.error("iCloud temporarily unavailable")
                
            @unknown default:
                iCloudAvailable = false
                errorMessage = "Unknown iCloud account status."
                logger.error("Unknown iCloud status")
            }
        } catch {
            iCloudAvailable = false
            errorMessage = "Failed to check iCloud status: \(error.localizedDescription)"
            print("❌ CloudKitSyncManager: Failed to check iCloud status: \(error.localizedDescription)")
            logger.error("Failed to check iCloud status: \(error.localizedDescription)")
        }
    }
    
    /// Sync messages for a specific session
    public func syncMessages(for sessionId: String, projectPath: String) async throws {
        guard iCloudAvailable else {
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        logger.info("Starting message sync for session: \(sessionId)")
        syncStatus = .syncing
        
        do {
            // Fetch messages from CloudKit
            let query = CloudKitSchema.messageQuery(for: sessionId)
            let (records, _) = try await privateDatabase.records(matching: query)
            
            logger.info("Fetched \(records.count) message records from CloudKit")
            
            // Convert CloudKit records to messages
            var messages: [Message] = []
            for (_, result) in records {
                switch result {
                case .success(let record):
                    if let message = Message.from(ckRecord: record) {
                        messages.append(message)
                    }
                case .failure(let error):
                    logger.error("Failed to fetch record: \(error.localizedDescription)")
                }
            }
            
            // Notify completion via delegate or combine
            await MainActor.run {
                syncStatus = .synced
                lastSyncDate = Date()
            }
            
            logger.info("Message sync completed successfully")
        } catch {
            await MainActor.run {
                syncStatus = .failed
                errorMessage = error.localizedDescription
            }
            logger.error("Message sync failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Fetch messages for a specific project from CloudKit
    public func fetchMessages(for projectPath: String) async throws -> [Message] {
        print("☁️ CloudKitSyncManager.fetchMessages called. iCloudAvailable: \(iCloudAvailable)")
        guard iCloudAvailable else {
            print("❌ CloudKitSyncManager: iCloud not available, cannot fetch messages")
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        print("☁️ CloudKitSyncManager: Fetching messages from CloudKit for project: \(projectPath)")
        logger.info("Fetching messages from CloudKit for project: \(projectPath)")
        
        // Get current device ID for filtering deleted messages (consistent with DeviceCoordinator)
        let currentDeviceId = DeviceCoordinator.shared.currentDeviceId
        
        do {
            // Create predicate to fetch messages for this project
            let predicate = NSPredicate(format: "%K == %@", CloudKitSchema.MessageFields.projectPath, projectPath)
            let query = CKQuery(recordType: CloudKitSchema.RecordType.message, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: CloudKitSchema.MessageFields.timestamp, ascending: true)]
            
            // Fetch records from CloudKit
            let (records, _) = try await privateDatabase.records(matching: query)
            
            logger.info("Fetched \(records.count) message records from CloudKit for project")
            
            // Convert CloudKit records to messages, filtering out deleted ones
            var messages: [Message] = []
            var deletedCount = 0
            
            for (_, result) in records {
                switch result {
                case .success(let record):
                    // Check if this message has been marked as deleted by current device
                    if let deletedByDevices = record[CloudKitSchema.MessageFields.deletedByDevices] as? [String] {
                        print("☁️ CloudKitSyncManager: Message \(record.recordID.recordName) deletedByDevices: \(deletedByDevices), currentDeviceId: \(currentDeviceId)")
                        if deletedByDevices.contains(currentDeviceId) {
                            deletedCount += 1
                            print("☁️ CloudKitSyncManager: Skipping message marked as deleted by current device")
                            logger.debug("Skipping message marked as deleted by current device")
                            continue
                        }
                    } else {
                        print("☁️ CloudKitSyncManager: Message \(record.recordID.recordName) has no deletedByDevices array")
                    }
                    
                    if let message = Message.from(ckRecord: record) {
                        messages.append(message)
                    }
                case .failure(let error):
                    logger.error("Failed to fetch record: \(error.localizedDescription)")
                }
            }
            
            logger.info("Successfully converted \(messages.count) CloudKit messages (filtered \(deletedCount) deleted)")
            print("☁️ CloudKitSyncManager: Fetched \(messages.count) messages, filtered out \(deletedCount) deleted")
            return messages
        } catch {
            logger.error("Failed to fetch messages from CloudKit: \(error.localizedDescription)")
            
            // Check for specific CloudKit errors
            if let ckError = error as? CKError {
                switch ckError.code {
                case .invalidArguments:
                    // This often happens when a field isn't marked as queryable
                    if error.localizedDescription.contains("not marked queryable") || 
                       error.localizedDescription.contains("Field 'timestamp'") {
                        logger.error("CloudKit schema issue: timestamp field not queryable. CloudKit sync disabled for this query.")
                        self.errorMessage = "CloudKit configuration issue. Local storage will be used."
                        // Don't throw - allow app to continue without CloudKit sync
                        return []
                    }
                default:
                    break
                }
            }
            
            throw error
        }
    }
    
    /// Save a message to CloudKit
    public func saveMessage(_ message: Message) async throws {
        print("☁️ CloudKitSyncManager.saveMessage called. iCloudAvailable: \(iCloudAvailable)")
        guard iCloudAvailable else {
            print("❌ CloudKitSyncManager: iCloud not available, cannot save message")
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        let operationId = UUID().uuidString
        pendingOperations.insert(operationId)
        defer { pendingOperations.remove(operationId) }
        
        print("☁️ CloudKitSyncManager: Saving message to CloudKit: \(message.id)")
        logger.info("Saving message to CloudKit: \(message.id)")
        
        do {
            var mutableMessage = message
            let record = mutableMessage.toCKRecord()
            let savedRecord = try await privateDatabase.save(record)
            
            print("✅ CloudKitSyncManager: Message saved to CloudKit successfully: \(savedRecord.recordID)")
            logger.info("Message saved to CloudKit successfully: \(savedRecord.recordID)")
        } catch {
            print("❌ CloudKitSyncManager: Failed to save message to CloudKit: \(error.localizedDescription)")
            logger.error("Failed to save message to CloudKit: \(error.localizedDescription)")
            
            if let ckError = error as? CKError {
                await handleCloudKitError(ckError, for: operationId)
            }
            
            throw error
        }
    }
    
    /// Delete a message from CloudKit
    public func deleteMessage(recordID: CKRecord.ID) async throws {
        guard iCloudAvailable else {
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        logger.info("Deleting message from CloudKit: \(recordID)")
        
        do {
            _ = try await privateDatabase.deleteRecord(withID: recordID)
            logger.info("Message deleted from CloudKit successfully")
        } catch {
            logger.error("Failed to delete message from CloudKit: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Mark all messages for a project as deleted for the current device
    public func markMessagesAsDeleted(for projectPath: String) async throws {
        print("☁️ CloudKitSyncManager: Marking messages as deleted for project: \(projectPath)")
        guard iCloudAvailable else {
            print("❌ CloudKitSyncManager: iCloud not available, cannot mark messages as deleted")
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        // Get current device ID (consistent with DeviceCoordinator)
        let deviceId = DeviceCoordinator.shared.currentDeviceId
        print("☁️ CloudKitSyncManager: Using device ID: \(deviceId)")
        
        do {
            // Fetch all messages for this project
            let predicate = NSPredicate(format: "%K == %@", CloudKitSchema.MessageFields.projectPath, projectPath)
            let query = CKQuery(recordType: CloudKitSchema.RecordType.message, predicate: predicate)
            
            let (records, _) = try await privateDatabase.records(matching: query)
            print("☁️ CloudKitSyncManager: Found \(records.count) messages to mark as deleted")
            
            // Update each message to mark as deleted for this device
            var recordsToUpdate: [CKRecord] = []
            
            for (_, result) in records {
                switch result {
                case .success(let record):
                    // Get existing deletedByDevices array
                    var deletedByDevices = record[CloudKitSchema.MessageFields.deletedByDevices] as? [String] ?? []
                    
                    // Add this device if not already marked
                    if !deletedByDevices.contains(deviceId) {
                        deletedByDevices.append(deviceId)
                        record[CloudKitSchema.MessageFields.deletedByDevices] = deletedByDevices
                        recordsToUpdate.append(record)
                    }
                    
                case .failure(let error):
                    print("❌ Failed to fetch record: \(error.localizedDescription)")
                }
            }
            
            // Batch update all records
            if !recordsToUpdate.isEmpty {
                print("☁️ CloudKitSyncManager: Updating \(recordsToUpdate.count) messages with deletion marker")
                
                let operation = CKModifyRecordsOperation(recordsToSave: recordsToUpdate, recordIDsToDelete: nil)
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .userInitiated
                
                await withCheckedContinuation { continuation in
                    operation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            print("✅ CloudKitSyncManager: Successfully marked \(recordsToUpdate.count) messages as deleted")
                        case .failure(let error):
                            print("❌ CloudKitSyncManager: Failed to mark messages as deleted: \(error.localizedDescription)")
                        }
                        continuation.resume()
                    }
                    
                    privateDatabase.add(operation)
                }
            } else {
                print("☁️ CloudKitSyncManager: No messages needed updating")
            }
        } catch {
            print("❌ CloudKitSyncManager: Failed to mark messages as deleted: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Perform full sync of all data
    public func performFullSync() async throws {
        guard iCloudAvailable else {
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        logger.info("Starting full sync")
        syncStatus = .syncing
        syncProgress = 0.0
        
        do {
            // Sync messages
            syncProgress = 0.2
            try await syncAllMessages()
            
            // Sync sessions
            syncProgress = 0.5
            try await syncAllSessions()
            
            // Sync device info
            syncProgress = 0.8
            try await syncDeviceInfo()
            
            // Update sync metadata
            syncProgress = 0.9
            try await updateSyncMetadata()
            
            await MainActor.run {
                syncStatus = .synced
                lastSyncDate = Date()
                syncProgress = 1.0
                isInitialSyncComplete = true
                errorMessage = nil
            }
            
            logger.info("Full sync completed successfully")
        } catch {
            await MainActor.run {
                syncStatus = .failed
                errorMessage = error.localizedDescription
            }
            logger.error("Full sync failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Force refresh CloudKit data
    public func refreshFromCloudKit() async throws {
        changeToken = nil
        try await performFullSync()
    }
    
    // MARK: - Private Methods
    
    private func setupCloudKitServices() async {
        do {
            // Create custom zone if needed
            await createCustomZoneIfNeeded()
            
            // Set up subscriptions
            await setupSubscriptions()
            
            // Perform initial sync
            if !isInitialSyncComplete {
                try await performFullSync()
            }
        } catch {
            logger.error("Failed to setup CloudKit services: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = "Failed to setup CloudKit: \(error.localizedDescription)"
            }
        }
    }
    
    private func createCustomZoneIfNeeded() async {
        do {
            let zone = CKRecordZone(zoneID: CloudKitSchema.customZoneID)
            
            let savedZone = try await privateDatabase.save(zone)
            customZone = savedZone
            
            logger.info("Custom zone created/verified: \(savedZone.zoneID)")
        } catch let error as CKError where error.code == .zoneNotFound {
            logger.error("Failed to create custom zone: \(error.localizedDescription)")
        } catch {
            logger.info("Custom zone already exists or other error: \(error.localizedDescription)")
        }
    }
    
    private func setupSubscriptions() async {
        do {
            // Create subscription for message changes
            let messageSubscription = CKQuerySubscription(
                recordType: CloudKitSchema.RecordType.message,
                predicate: NSPredicate(value: true),
                subscriptionID: CloudKitSchema.Subscriptions.messages,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
            )
            
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            messageSubscription.notificationInfo = notificationInfo
            
            _ = try await privateDatabase.save(messageSubscription)
            logger.info("Message subscription created")
            
            // Create subscription for session changes
            let sessionSubscription = CKQuerySubscription(
                recordType: CloudKitSchema.RecordType.session,
                predicate: NSPredicate(value: true),
                subscriptionID: CloudKitSchema.Subscriptions.sessions,
                options: [.firesOnRecordCreation, .firesOnRecordUpdate]
            )
            
            sessionSubscription.notificationInfo = notificationInfo
            _ = try await privateDatabase.save(sessionSubscription)
            logger.info("Session subscription created")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Check if it's a duplicate subscription error
            let errorMessage = error.localizedDescription
            if errorMessage.contains("duplicate") {
                logger.info("Subscriptions already exist")
            } else {
                logger.error("Server rejected subscription: \(error.localizedDescription)")
            }
        } catch {
            logger.error("Failed to create subscriptions: \(error.localizedDescription)")
        }
    }
    
    private func syncAllMessages() async throws {
        let query = CloudKitSchema.recentMessagesQuery(hours: 168) // Last week
        let (records, _) = try await privateDatabase.records(matching: query)
        
        for (_, result) in records {
            switch result {
            case .success(let record):
                // Process message record
                logger.debug("Synced message: \(record.recordID)")
            case .failure(let error):
                logger.error("Failed to sync message: \(error.localizedDescription)")
            }
        }
    }
    
    private func syncAllSessions() async throws {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let query = CloudKitSchema.activeSessionsQuery(since: since)
        let (records, _) = try await privateDatabase.records(matching: query)
        
        for (_, result) in records {
            switch result {
            case .success(let record):
                // Process session record
                logger.debug("Synced session: \(record.recordID)")
            case .failure(let error):
                logger.error("Failed to sync session: \(error.localizedDescription)")
            }
        }
    }
    
    private func syncDeviceInfo() async throws {
        let record = deviceInfo.toCKRecord(recordName: deviceInfo.deviceId)
        _ = try await privateDatabase.save(record)
        logger.info("Device info synced to CloudKit")
    }
    
    private func updateSyncMetadata() async throws {
        let metadata = SyncMetadata(
            lastSyncTimestamp: Date(),
            syncVersion: 1,
            deviceInfo: deviceInfo,
            syncStatus: .synced
        )
        
        let record = metadata.toCKRecord(recordName: "sync_metadata_\(deviceInfo.deviceId)")
        _ = try await privateDatabase.save(record)
        logger.info("Sync metadata updated")
    }
    
    private func handleCloudKitError(_ error: CKError, for operationId: String) async {
        logger.error("CloudKit error for operation \(operationId): \(error.localizedDescription)")
        
        switch error.code {
        case .networkUnavailable, .networkFailure:
            await MainActor.run {
                errorMessage = "Network unavailable. Sync will resume when connected."
            }
            
        case .quotaExceeded:
            await MainActor.run {
                errorMessage = "iCloud storage quota exceeded. Please free up space."
            }
            
        case .notAuthenticated:
            await MainActor.run {
                iCloudAvailable = false
                errorMessage = "Please sign in to iCloud."
            }
            
        case .serverRecordChanged:
            // Handle conflict resolution
            await handleServerRecordChanged(error)
            
        default:
            await MainActor.run {
                errorMessage = "CloudKit error: \(error.localizedDescription)"
            }
        }
    }
    
    private func handleServerRecordChanged(_ error: CKError) async {
        guard let userInfo = error.userInfo as? [String: Any],
              let serverRecord = userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
              let clientRecord = userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord else {
            logger.error("Could not extract records from server change error")
            return
        }
        
        logger.info("Resolving server record conflict")
        
        let resolvedRecord = conflictResolver.resolveMessageConflict(
            clientRecord: clientRecord,
            serverRecord: serverRecord,
            policy: CloudKitSchema.SyncConfig.conflictResolutionPolicy
        )
        
        do {
            _ = try await privateDatabase.save(resolvedRecord)
            logger.info("Conflict resolved and record saved")
        } catch {
            logger.error("Failed to save resolved record: \(error.localizedDescription)")
        }
    }
}

// MARK: - Remote Notifications

extension CloudKitSyncManager {
    /// Handle CloudKit remote notification
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }
        
        switch notification.notificationType {
        case .query:
            if let queryNotification = notification as? CKQueryNotification {
                await handleQueryNotification(queryNotification)
            }
            
        case .database:
            if let databaseNotification = notification as? CKDatabaseNotification {
                await handleDatabaseNotification(databaseNotification)
            }
            
        default:
            logger.info("Received other CloudKit notification type")
        }
    }
    
    private func handleQueryNotification(_ notification: CKQueryNotification) async {
        logger.info("Received CloudKit query notification")
        
        guard notification.subscriptionID == CloudKitSchema.Subscriptions.messages else {
            return
        }
        
        // Trigger incremental sync
        do {
            try await Task.sleep(nanoseconds: UInt64(CloudKitSchema.SyncConfig.subscriptionNotificationDelay * 1_000_000_000))
            try await performIncrementalSync()
        } catch {
            logger.error("Failed to perform incremental sync: \(error.localizedDescription)")
        }
    }
    
    private func handleDatabaseNotification(_ notification: CKDatabaseNotification) async {
        logger.info("Received CloudKit database notification")
        
        // Perform full sync on database changes
        do {
            try await performFullSync()
        } catch {
            logger.error("Failed to perform full sync after database notification: \(error.localizedDescription)")
        }
    }
    
    private func performIncrementalSync() async throws {
        logger.info("Performing incremental sync")
        
        // Use change token for efficient incremental sync
        let changesOperation = CKFetchDatabaseChangesOperation(previousServerChangeToken: changeToken)
        
        return try await withCheckedThrowingContinuation { continuation in
            changesOperation.changeTokenUpdatedBlock = { [weak self] token in
                self?.changeToken = token
            }
            
            changesOperation.fetchDatabaseChangesResultBlock = { [weak self] result in
                switch result {
                case .success(let (serverChangeToken, moreComing)):
                    self?.changeToken = serverChangeToken
                    if !moreComing {
                        continuation.resume()
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            privateDatabase.add(changesOperation)
        }
    }
}

// MARK: - Public Utilities

extension CloudKitSyncManager {
    /// Get current sync statistics
    public var syncStats: (pending: Int, synced: Int, failed: Int) {
        // This would be implemented to return actual stats
        return (pending: pendingOperations.count, synced: 0, failed: 0)
    }
    
    /// Clear all sync data and reset
    public func resetSyncState() async {
        await MainActor.run {
            syncStatus = .pending
            lastSyncDate = nil
            syncProgress = 0.0
            errorMessage = nil
            isInitialSyncComplete = false
            changeToken = nil
            pendingOperations.removeAll()
        }
        
        logger.info("Sync state reset")
    }
}
