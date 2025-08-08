import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// Service to handle background message synchronization when push notifications arrive
@available(iOS 16.0, macOS 13.0, *)
class BackgroundMessageSyncService: ObservableObject {
    static let shared = BackgroundMessageSyncService()
    
    // MARK: - Published Properties
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncTimestamp: Date?
    @Published var syncedMessageCount: Int = 0
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let syncTimeout: TimeInterval = 30 // 30 seconds max for background sync
    
    // MARK: - Initialization
    
    private init() {
        print("🔄 BackgroundMessageSyncService initialized")
    }
    
    // MARK: - Public Methods
    
    /// Sync messages for a specific session in background mode
    /// This is called when a push notification arrives
    /// @param sessionId: The session ID to sync messages for
    /// @param projectId: The project ID for context
    /// @param projectName: The project name for logging
    /// @returns: Bool indicating if sync was successful
    func syncMessagesForSession(
        _ sessionId: String,
        projectId: String? = nil,
        projectName: String? = nil
    ) async -> Bool {
        print("🔄 Starting background message sync for session: \(sessionId)")
        
        // Prevent multiple simultaneous syncs
        guard !isSyncing else {
            print("⚠️ Background sync already in progress, skipping")
            return false
        }
        
        await updateSyncStatus(true)
        
        do {
            // Create timeout task
            let syncTask = Task {
                return await performMessageSync(
                    sessionId: sessionId,
                    projectId: projectId,
                    projectName: projectName
                )
            }
            
            // Race between sync and timeout
            let result = try await withThrowingTaskGroup(of: Bool.self) { group in
                // Add sync task
                group.addTask {
                    return await syncTask.value
                }
                
                // Add timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.syncTimeout * 1_000_000_000))
                    syncTask.cancel()
                    return false
                }
                
                // Return first completed result
                return try await group.next() ?? false
            }
            
            await updateSyncStatus(false)
            
            if result {
                await MainActor.run {
                    self.lastSyncTimestamp = Date()
                }
                print("✅ Background message sync completed successfully")
            } else {
                print("❌ Background message sync failed or timed out")
            }
            
            return result
        } catch {
            await updateSyncStatus(false)
            print("❌ Background message sync error: \(error)")
            return false
        }
    }
    
    /// Quick sync for all active sessions
    /// Used when app returns to foreground
    func syncAllActiveSessions() async -> Int {
        print("🔄 Starting sync for all active sessions")
        
        let activeSessions = SessionStatePersistenceService.shared.getActiveSessions()
        var syncedCount = 0
        
        // Sync sessions concurrently with limit
        let semaphore = AsyncSemaphore(value: 3) // Max 3 concurrent syncs
        
        await withTaskGroup(of: Bool.self) { group in
            for session in activeSessions {
                group.addTask {
                    await semaphore.wait()
                    defer {
                        Task { await semaphore.signal() }
                    }
                    
                    return await self.syncMessagesForSession(
                        session.id,
                        projectId: session.projectId,
                        projectName: session.projectName
                    )
                }
            }
            
            for await success in group where success {
                syncedCount += 1
            }
        }
        
        print("✅ Synced \(syncedCount) of \(activeSessions.count) active sessions")
        return syncedCount
    }
    
    // MARK: - Private Methods
    
    private func performMessageSync(
        sessionId: String,
        projectId: String?,
        projectName: String?
    ) async -> Bool {
        // Step 1: Establish temporary background WebSocket connection
        let connectionSuccess = await establishBackgroundConnection()
        guard connectionSuccess else {
            print("❌ Failed to establish background WebSocket connection")
            return false
        }
        
        defer {
            // Always close background connection when done
            Task {
                await closeBackgroundConnection()
            }
        }
        
        // Step 2: Request message history for the session
        let messages = await fetchQueuedMessages(for: sessionId)
        guard !messages.isEmpty else {
            print("ℹ️ No new messages to sync for session: \(sessionId)")
            return true // No messages is still success
        }
        
        // Step 3: Save messages to local persistence
        let saveSuccess = await saveMessagesToLocalStorage(messages, sessionId: sessionId)
        guard saveSuccess else {
            print("❌ Failed to save synced messages to local storage")
            return false
        }
        
        // Step 4: Update message count
        await MainActor.run {
            self.syncedMessageCount += messages.count
        }
        
        // Step 5: Notify other services about new messages
        await notifyMessageUpdate(sessionId: sessionId, messageCount: messages.count)
        
        print("✅ Successfully synced \(messages.count) messages for session: \(sessionId)")
        return true
    }
    
    private func establishBackgroundConnection() async -> Bool {
        // Use WebSocketService to create a temporary background connection
        // This is different from the main connection - focused only on message fetch
        
        guard let serverUrl = UserDefaults.standard.url(forKey: "ServerURL") else {
            print("❌ No server URL configured for background sync")
            return false
        }
        
        // Create temporary WebSocket connection with shorter timeout
        return await WebSocketService.shared.establishBackgroundConnection(to: serverUrl)
    }
    
    private func closeBackgroundConnection() async {
        await WebSocketService.shared.closeBackgroundConnection()
    }
    
    private func fetchQueuedMessages(for sessionId: String) async -> [Message] {
        // Request message history via WebSocket
        return await WebSocketService.shared.fetchQueuedMessages(for: sessionId)
    }
    
    private func saveMessagesToLocalStorage(_ messages: [Message], sessionId: String) async -> Bool {
        // Save messages with background sync flag
        return await MessagePersistenceService.shared.saveBackgroundSyncedMessages(
            messages,
            for: sessionId
        )
    }
    
    private func notifyMessageUpdate(sessionId: String, messageCount: Int) async {
        // Notify UI about new messages (for when app returns to foreground)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .backgroundMessagesReceived,
                object: nil,
                userInfo: [
                    "sessionId": sessionId,
                    "messageCount": messageCount,
                    "timestamp": Date()
                ]
            )
        }
    }
    
    @MainActor
    private func updateSyncStatus(_ syncing: Bool) {
        self.isSyncing = syncing
    }
}

// MARK: - Supporting Types

/// Simple async semaphore for controlling concurrency
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int) {
        self.count = value
    }
    
    func wait() async {
        if !isEmpty {
            count -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
    
    func signal() {
        if let waiter = waiters.popLast() {
            waiter.resume()
        } else {
            count += 1
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let backgroundMessagesReceived = Notification.Name("com.aiclicompanion.backgroundMessagesReceived")
    static let backgroundSyncStarted = Notification.Name("com.aiclicompanion.backgroundSyncStarted")
    static let backgroundSyncCompleted = Notification.Name("com.aiclicompanion.backgroundSyncCompleted")
}

// MARK: - Message Persistence Extension

extension MessagePersistenceService {
    /// Save messages that were synced in background
    func saveBackgroundSyncedMessages(_ messages: [Message], for sessionId: String) async -> Bool {
        // Add background sync metadata to messages
        let messagesWithMetadata = messages.map { message in
            var updatedMessage = message
            if updatedMessage.metadata == nil {
                updatedMessage.metadata = AICLIMessageMetadata(
                    sessionId: sessionId,
                    duration: 0,
                    additionalInfo: [
                        "backgroundSynced": true,
                        "syncedAt": Date()
                    ]
                )
            } else {
                // Update existing metadata with background sync info
                var existingInfo = updatedMessage.metadata?.additionalInfo ?? [:]
                existingInfo["backgroundSynced"] = true
                existingInfo["syncedAt"] = Date()
                
                updatedMessage.metadata = AICLIMessageMetadata(
                    sessionId: updatedMessage.metadata?.sessionId ?? sessionId,
                    duration: updatedMessage.metadata?.duration ?? 0,
                    cost: updatedMessage.metadata?.cost,
                    tools: updatedMessage.metadata?.tools,
                    queuedAt: updatedMessage.metadata?.queuedAt,
                    deliveredAt: updatedMessage.metadata?.deliveredAt,
                    queuePriority: updatedMessage.metadata?.queuePriority,
                    additionalInfo: existingInfo
                )
            }
            return updatedMessage
        }
        
        // For background sync, we need to append messages to existing session
        // This is a simplified approach that adds messages to any existing persisted messages
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                do {
                    // Get session metadata to understand which project this belongs to
                    guard let sessionState = SessionStatePersistenceService.shared.getSessionStateById(sessionId) else {
                        print("❌ No session state found for sessionId: \(sessionId)")
                        continuation.resume(returning: false)
                        return
                    }
                    
                    // Load existing messages for this project/session
                    let existingMessages = MessagePersistenceService.shared.loadMessages(
                        for: sessionState.projectId,
                        sessionId: sessionId
                    )
                    
                    // Combine existing + new messages, deduplicating by ID
                    var allMessages = existingMessages
                    let existingIds = Set(existingMessages.map { $0.id })
                    
                    for message in messagesWithMetadata where !existingIds.contains(message.id) {
                        allMessages.append(message)
                    }
                    
                    // Sort by timestamp to maintain chronological order
                    allMessages.sort { $0.timestamp < $1.timestamp }
                    
                    // Create minimal project object for persistence
                    let project = Project(
                        name: sessionState.projectName ?? "Unknown Project",
                        path: sessionState.projectPath ?? "",
                        type: "unknown"
                    )
                    
                    // Save combined messages
                    MessagePersistenceService.shared.saveMessages(
                        for: sessionState.projectId,
                        messages: allMessages,
                        sessionId: sessionId,
                        project: project
                    )
                    
                    continuation.resume(returning: true)
                } catch {
                    print("❌ Failed to save background synced messages: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - WebSocketService Extension
// Note: Background connection methods are implemented directly in WebSocketService.swift

// MARK: - Metadata Extension

extension AICLIMessageMetadata {
    /// Indicates if this message was synced in background
    var backgroundSynced: Bool {
        get { return (additionalInfo?["backgroundSynced"] as? Bool) ?? false }
        set {
            if additionalInfo == nil { additionalInfo = [:] }
            additionalInfo?["backgroundSynced"] = newValue
        }
    }
    
    /// Timestamp when message was synced in background
    var syncedAt: Date? {
        get { return additionalInfo?["syncedAt"] as? Date }
        set {
            if additionalInfo == nil { additionalInfo = [:] }
            additionalInfo?["syncedAt"] = newValue
        }
    }
}
