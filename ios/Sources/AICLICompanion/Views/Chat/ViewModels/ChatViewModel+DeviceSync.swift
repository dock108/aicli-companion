import SwiftUI
import Combine
import CloudKit

// MARK: - ChatViewModel Device Coordination & CloudKit Sync Extension

@available(iOS 16.0, macOS 13.0, *)
extension ChatViewModel {
    
    // MARK: - Device Coordination Properties
    
    /// Device coordinator for multi-device synchronization
    private var deviceCoordinator: DeviceCoordinator {
        return DeviceCoordinator.shared
    }
    
    /// CloudKit sync manager for cross-device message sync
    private var cloudKitSyncManager: CloudKitSyncManager {
        return CloudKitSyncManager.shared
    }
    
    // MARK: - Device Coordination Setup
    
    /// Initialize device coordination services
    public func setupDeviceCoordination() {
        Task {
            await initializeDeviceServices()
            await setupDeviceCoordinationBindings()
        }
    }
    
    /// Initialize device coordination and CloudKit services
    private func initializeDeviceServices() async {
        do {
            // Initialize CloudKit sync manager
            await cloudKitSyncManager.initializeCloudKit()
            
            // Set up device coordinator with WebSocket manager
            if let webSocketManager = getWebSocketManager() {
                deviceCoordinator.setWebSocketManager(webSocketManager)
            }
            
            // Register device with server if we have a user ID
            if let userId = getCurrentUserId() {
                try await deviceCoordinator.registerWithServer(userId: userId)
            }
            
            print("✅ Device coordination services initialized")
            
        } catch {
            print("❌ Failed to initialize device coordination: \(error)")
        }
    }
    
    /// Set up bindings for device coordination events
    private func setupDeviceCoordinationBindings() async {
        // Listen for primary device status changes
        deviceCoordinator.$isPrimary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPrimary in
                Task { [weak self] in
                    await self?.handlePrimaryDeviceChange(isPrimary: isPrimary)
                }
            }
            .store(in: &cancellables)
        
        // Listen for CloudKit sync status changes
        cloudKitSyncManager.$syncStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] syncStatus in
                Task { [weak self] in
                    await self?.handleSyncStatusChange(syncStatus)
                }
            }
            .store(in: &cancellables)
        
        // Listen for new active devices
        deviceCoordinator.$activeDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                Task { [weak self] in
                    await self?.handleActiveDevicesChange(devices)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Session Management with Device Coordination
    
    /// Join a session with device coordination
    public func joinSession(for project: Project) async throws {
        guard let sessionId = currentSessionId else {
            throw DeviceCoordinationError.noActiveSession
        }
        
        // Join session for device coordination
        try await deviceCoordinator.joinSession(sessionId)
        
        // Start CloudKit sync for this session
        try await cloudKitSyncManager.syncMessages(for: sessionId, projectPath: project.path)
    }
    
    /// Leave current session with cleanup
    public func leaveSession() async throws {
        // Leave session in device coordinator
        try await deviceCoordinator.leaveSession()
        
        // Stop device heartbeat
        deviceCoordinator.stopHeartbeat()
    }
    
    // MARK: - Message Sending with Device Coordination
    
    /// Enhanced message sending with device coordination and duplicate prevention
    func sendMessageWithCoordination(_ text: String, for project: Project, attachments: [AttachmentData] = []) async {
        // Only primary device should send messages to prevent duplicates
        guard deviceCoordinator.isPrimary else {
            print("⚠️ Not primary device - message sending blocked")
            await showNotPrimaryDeviceAlert()
            return
        }
        
        // Generate message hash for duplicate detection
        let messageContent = "\(text)|\(project.path)|\(Date().timeIntervalSince1970)"
        let messageHash = messageContent.sha256
        
        // Create user message with hash for tracking
        let requestId = UUID().uuidString
        var userMessage = Message(
            content: text,
            sender: .user,
            type: .text,
            requestId: requestId,
            attachments: attachments
        )
        
        // Set CloudKit properties
        userMessage.messageHash = messageHash
        userMessage.markAsNeedingSync()
        
        // Add to UI immediately (local-first pattern)
        messageManager.appendMessage(userMessage, for: project)
        
        // Save to CloudKit
        do {
            try await cloudKitSyncManager.saveMessage(userMessage)
        } catch {
            print("⚠️ Failed to save message to CloudKit: \(error)")
            // Continue with regular sending - CloudKit sync will retry later
        }
        
        // Send via regular API
        sendMessage(text, for: project, attachments: attachments)
    }
    
    // MARK: - Primary Device Management
    
    /// Request to become primary device for current session
    public func requestPrimary() async throws {
        try await deviceCoordinator.requestPrimary()
    }
    
    /// Transfer primary status to another device
    public func transferPrimary(to deviceId: String) async throws {
        try await deviceCoordinator.transferPrimary(to: deviceId)
    }
    
    /// Release primary status
    public func releasePrimary() async throws {
        try await deviceCoordinator.releasePrimary()
    }
    
    // MARK: - CloudKit Sync Operations
    
    /// Perform full CloudKit sync for current project
    public func performFullSync() async throws {
        guard cloudKitSyncManager.iCloudAvailable else {
            throw CloudKitSchema.SyncError.iCloudUnavailable
        }
        
        try await cloudKitSyncManager.performFullSync()
        
        // Reload messages from CloudKit
        if let project = currentProject {
            await reloadMessagesFromSync(for: project)
        }
    }
    
    /// Refresh data from CloudKit
    public func refreshFromCloudKit() async throws {
        try await cloudKitSyncManager.refreshFromCloudKit()
        
        if let project = currentProject {
            await reloadMessagesFromSync(for: project)
        }
    }
    
    /// Sync messages for specific project
    public func syncProject(_ project: Project) async throws {
        guard let sessionId = getSessionId(for: project) else { return }
        
        try await cloudKitSyncManager.syncMessages(for: sessionId, projectPath: project.path)
        await reloadMessagesFromSync(for: project)
    }
    
    // MARK: - Event Handlers
    
    private func handlePrimaryDeviceChange(isPrimary: Bool) async {
        print("📱 Primary device status changed: \(isPrimary)")
        
        if isPrimary {
            // Started as primary - begin heartbeat and enable message sending
            deviceCoordinator.startHeartbeat()
            await showPrimaryDeviceNotification()
        } else {
            // No longer primary - stop heartbeat
            deviceCoordinator.stopHeartbeat()
            await showSecondaryDeviceNotification()
        }
    }
    
    private func handleSyncStatusChange(_ syncStatus: SyncStatus) async {
        print("☁️ CloudKit sync status changed: \(syncStatus)")
        
        switch syncStatus {
        case .synced:
            await showSyncCompletedNotification()
        case .failed:
            await showSyncFailedNotification()
        case .syncing:
            break // Show progress in UI
        default:
            break
        }
    }
    
    private func handleActiveDevicesChange(_ devices: [ActiveDevice]) async {
        print("📱 Active devices changed: \(devices.count) devices")
        
        // Update UI to show active devices
        // This could trigger device list refresh in settings
    }
    
    private func reloadMessagesFromSync(for project: Project) async {
        // Reload messages from local storage (updated by CloudKit sync)
        await MainActor.run {
            loadMessages(for: project, isRefresh: true)
        }
    }
    
    // MARK: - User Notifications
    
    private func showNotPrimaryDeviceAlert() async {
        // Show alert that this device cannot send messages
        // Implementation would show UI alert
        print("⚠️ This device is not the primary device for this session")
    }
    
    private func showPrimaryDeviceNotification() async {
        hapticManager.mediumImpact()
        // Show notification that this device is now primary
        print("👑 This device is now the primary device")
    }
    
    private func showSecondaryDeviceNotification() async {
        // Show notification that another device is primary
        print("📱 Another device is now primary")
    }
    
    private func showSyncCompletedNotification() async {
        // Show sync completed notification
        print("☁️ CloudKit sync completed")
    }
    
    private func showSyncFailedNotification() async {
        hapticManager.error()
        print("❌ CloudKit sync failed")
    }
    
    // MARK: - Helper Methods
    
    private func getWebSocketManager() -> WebSocketManager? {
        // Get WebSocket manager from AICLI service or dependency injection
        return aicliService.webSocketManager
    }
    
    private func getCurrentUserId() -> String? {
        // Get current user ID from authentication service
        // This would need to be implemented based on your auth system
        return "current_user_id" // Placeholder
    }
    
    private func getSessionId(for project: Project) -> String? {
        // Get session ID for project from messages or project state
        return currentSessionId
    }
    
    // MARK: - Computed Properties
    
    /// Whether this device is the primary device for message sending
    public var isPrimaryDevice: Bool {
        return deviceCoordinator.isPrimary
    }
    
    /// Current device coordination status
    public var deviceStatus: String {
        if deviceCoordinator.isPrimary {
            return "Primary Device"
        } else if !deviceCoordinator.activeDevices.isEmpty {
            return "Secondary Device"
        } else {
            return "Only Device"
        }
    }
    
    /// CloudKit sync availability
    public var isCloudKitAvailable: Bool {
        return cloudKitSyncManager.iCloudAvailable
    }
    
    /// Current sync status
    public var syncStatus: SyncStatus {
        return cloudKitSyncManager.syncStatus
    }
    
    /// Last sync date
    public var lastSyncDate: Date? {
        return cloudKitSyncManager.lastSyncDate
    }
    
    /// Active devices count
    public var activeDevicesCount: Int {
        return deviceCoordinator.activeDevices.count
    }
    
    /// Active devices list
    public var activeDevices: [ActiveDevice] {
        return deviceCoordinator.activeDevices
    }
}

// MARK: - Singleton Extensions

@available(iOS 16.0, macOS 13.0, *)
extension DeviceCoordinator {
    static let shared = DeviceCoordinator()
}

@available(iOS 16.0, macOS 13.0, *)
extension CloudKitSyncManager {
    static let shared = CloudKitSyncManager()
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

// MARK: - AICLIService Extension

extension AICLIService {
    var webSocketManager: WebSocketManager? {
        // Return the WebSocket manager from AICLIService
        // This would need to be implemented based on your service structure
        return nil // Placeholder
    }
}