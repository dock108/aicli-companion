import CloudKit
import Combine
import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
@MainActor
class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()
    
    // MARK: - Properties
    private let container = CKContainer(identifier: "iCloud.com.aicli.companion")
    private let privateDB: CKDatabase
    
    @Published var iCloudAvailable = false
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var syncErrors: [CloudKitError] = []
    
    private var currentDeviceId: String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        // macOS fallback
        return UUID().uuidString
        #endif
    }
    
    enum SyncStatus: Equatable {
        case idle
        case checking
        case syncing(progress: Double)
        case completed
        case error(String)
    }
    
    // MARK: - Initialization
    private init() {
        self.privateDB = container.privateCloudDatabase
        
        Task {
            await checkiCloudAvailability()
            if iCloudAvailable {
                await setupSubscriptions()
                await performInitialSync()
            }
        }
    }
    
    // MARK: - iCloud Availability
    func checkiCloudAvailability() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                self.iCloudAvailable = (status == .available)
                if !self.iCloudAvailable {
                    self.syncStatus = .error("iCloud not available. Please sign in to iCloud in Settings.")
                }
            }
        } catch {
            print("Failed to check iCloud status: \(error)")
            await MainActor.run {
                self.iCloudAvailable = false
                self.syncStatus = .error("Cannot access iCloud")
            }
        }
    }
    
    // MARK: - Message Operations
    func saveMessage(_ message: Message, projectPath: String? = nil) async throws {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        syncStatus = .syncing(progress: 0.3)
        
        var mutableMessage = message
        let record = mutableMessage.toCKRecord()
        
        // Add project path if available
        if let projectPath = projectPath {
            record[CKField.projectPath] = projectPath
        }
        
        // Mark as read by current device
        if !mutableMessage.readByDevices.contains(currentDeviceId) {
            mutableMessage.readByDevices.append(currentDeviceId)
            record[CKField.readByDevices] = mutableMessage.readByDevices as CKRecordValue
        }
        
        do {
            let savedRecord = try await privateDB.save(record)
            print("✅ Saved message to CloudKit: \(message.id)")
            
            syncStatus = .completed
            lastSyncDate = Date()
            
            // Update local message with CloudKit ID
            mutableMessage.cloudKitRecordID = savedRecord.recordID
            mutableMessage.syncedAt = Date()
            mutableMessage.needsSync = false
        } catch {
            print("❌ Failed to save message to CloudKit: \(error)")
            syncStatus = .error("Failed to sync message")
            throw CloudKitError.syncFailed(error.localizedDescription)
        }
    }
    
    func fetchMessages(for projectPath: String, limit: Int = 100) async throws -> [Message] {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        syncStatus = .syncing(progress: 0.5)
        
        let predicate = NSPredicate(format: "%K == %@", CKField.projectPath, projectPath)
        let query = CKQuery(recordType: CKRecordType.message, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: CKField.timestamp, ascending: true)]
        
        do {
            // Use the new iOS 16+ API
            let (matchResults, _) = try await privateDB.records(matching: query, resultsLimit: limit)
            
            let messages = matchResults.compactMap { (_, result) -> Message? in
                switch result {
                case .success(let record):
                    return Message.from(record: record)
                case .failure(let error):
                    print("Failed to fetch record: \(error)")
                    return nil
                }
            }.filter { message in
                // Filter out messages deleted on this device
                !message.deletedByDevices.contains(currentDeviceId)
            }
            
            syncStatus = .completed
            lastSyncDate = Date()
            
            print("✅ Fetched \(messages.count) messages from CloudKit for project: \(projectPath)")
            return messages
        } catch {
            print("❌ Failed to fetch messages from CloudKit: \(error)")
            syncStatus = .error("Failed to fetch messages")
            throw CloudKitError.syncFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Delete Operations
    func deleteMessage(_ messageId: UUID) async throws {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        let recordID = CKRecord.ID(recordName: messageId.uuidString)
        
        do {
            // Fetch the record first
            let record = try await privateDB.record(for: recordID)
            
            // Soft delete - add device to deleted list
            var deletedBy = (record[CKField.deletedByDevices] as? [String]) ?? []
            if !deletedBy.contains(currentDeviceId) {
                deletedBy.append(currentDeviceId)
                record[CKField.deletedByDevices] = deletedBy as CKRecordValue
                try await privateDB.save(record)
                print("✅ Marked message as deleted on device: \(messageId)")
            }
        } catch {
            print("❌ Failed to delete message: \(error)")
            throw CloudKitError.syncFailed(error.localizedDescription)
        }
    }
    
    func clearChat(for projectPath: String) async throws {
        guard iCloudAvailable else {
            throw CloudKitError.iCloudNotAvailable
        }
        
        syncStatus = .syncing(progress: 0.3)
        
        // Fetch all messages for this project
        let messages = try await fetchMessages(for: projectPath, limit: 1000)
        
        // Mark each as deleted for this device
        for message in messages {
            try await deleteMessage(message.id)
        }
        
        syncStatus = .completed
        print("✅ Cleared chat for project: \(projectPath)")
    }
    
    // MARK: - Subscriptions
    private func setupSubscriptions() async {
        // Subscribe to message changes
        let subscription = CKQuerySubscription(
            recordType: CKRecordType.message,
            predicate: NSPredicate(value: true),
            subscriptionID: "message-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await privateDB.save(subscription)
            print("✅ Subscribed to CloudKit message changes")
        } catch {
            // Check if subscription already exists
            if (error as NSError).code == CKError.serverRejectedRequest.rawValue {
                print("ℹ️ CloudKit subscription already exists")
            } else {
                print("❌ Failed to create CloudKit subscription: \(error)")
            }
        }
    }
    
    // MARK: - Initial Sync
    private func performInitialSync() async {
        // This will be called on app launch
        // For now, just log that we're ready
        print("✅ CloudKit sync manager ready for syncing")
    }
    
    // MARK: - Manual Sync
    func performFullSync() async {
        guard iCloudAvailable else { return }
        
        syncStatus = .syncing(progress: 0.0)
        
        await MainActor.run {
            self.syncStatus = .completed
            self.lastSyncDate = Date()
        }
    }
    
    // MARK: - Handle CloudKit Notifications
    func handleNotification(_ notification: CKNotification) async {
        guard let queryNotification = notification as? CKQueryNotification else { return }
        
        switch queryNotification.queryNotificationReason {
        case .recordCreated:
            print("📥 New CloudKit record created")
            // TODO: Fetch and add new message
            
        case .recordUpdated:
            print("📝 CloudKit record updated")
            // TODO: Update existing message
            
        case .recordDeleted:
            print("🗑️ CloudKit record deleted")
            // TODO: Remove message locally
            
        @unknown default:
            break
        }
    }
}

// MARK: - Error Types

enum CloudKitError: LocalizedError, Hashable {
    case iCloudNotAvailable
    case syncFailed(String)
    case recordNotFound
    
    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud is not available. Please sign in to iCloud in Settings."
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .recordNotFound:
            return "Record not found in CloudKit"
        }
    }
}
