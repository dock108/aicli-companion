import Foundation
import Combine
import OSLog
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Coordinates device registration and primary device election with server
@MainActor
public class DeviceCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var isPrimary: Bool = false
    @Published public var activeDevices: [ActiveDevice] = []
    @Published public var currentDeviceId: String
    @Published public var registrationStatus: RegistrationStatus = .unregistered
    @Published public var primaryElectionStatus: PrimaryElectionStatus = .none
    @Published public var connectionStatus: DeviceConnectionStatus = .disconnected
    
    // MARK: - Private Properties
    
    private var webSocketManager: WebSocketManager?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AICLICompanion", category: "DeviceCoordinator")
    
    // Device info
    private let deviceInfo: DeviceInfo
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30.0
    
    // Session tracking
    internal var currentSessionId: String?
    private var sessionDevices: Set<String> = []
    
    // MARK: - Initialization
    
    public init(webSocketManager: WebSocketManager? = nil) {
        // Initialize device identifier
        #if canImport(UIKit)
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceId = UUID().uuidString
        #endif
        
        self.currentDeviceId = deviceId
        
        // Initialize device info
        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #else
        let platform = "Unknown"
        #endif
        
        #if canImport(UIKit)
        let systemVersion = UIDevice.current.systemVersion
        let deviceName = UIDevice.current.name
        #else
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
        
        self.webSocketManager = webSocketManager
        
        setupNotificationObservers()
        
        logger.info("DeviceCoordinator initialized with device ID: \(self.currentDeviceId)")
    }
    
    // MARK: - Public Methods
    
    /// Set the WebSocket manager for server communication
    public func setWebSocketManager(_ manager: WebSocketManager) {
        self.webSocketManager = manager
        setupWebSocketSubscriptions()
    }
    
    /// Register this device with the server
    public func registerWithServer(userId: String) async throws {
        guard let webSocketManager = webSocketManager else {
            throw DeviceCoordinationError.webSocketNotAvailable
        }
        
        logger.info("Registering device with server for user: \(userId)")
        registrationStatus = .registering
        
        let message = DeviceMessage.announce(
            deviceId: currentDeviceId,
            userId: userId,
            deviceInfo: deviceInfo
        )
        
        try await webSocketManager.send(message.toWebSocketMessage())
        
        // Registration status will be updated via WebSocket response
    }
    
    /// Join a session for coordination
    public func joinSession(_ sessionId: String) async throws {
        guard let webSocketManager = webSocketManager else {
            throw DeviceCoordinationError.webSocketNotAvailable
        }
        
        logger.info("Joining session: \(sessionId)")
        currentSessionId = sessionId
        
        let message = DeviceMessage.sessionJoin(
            deviceId: currentDeviceId,
            sessionId: sessionId
        )
        
        try await webSocketManager.send(message.toWebSocketMessage())
    }
    
    /// Leave the current session
    public func leaveSession() async throws {
        guard let webSocketManager = webSocketManager,
              let sessionId = currentSessionId else {
            return
        }
        
        logger.info("Leaving session: \(sessionId)")
        
        let message = DeviceMessage.sessionLeave(
            deviceId: currentDeviceId,
            sessionId: sessionId
        )
        
        try await webSocketManager.send(message.toWebSocketMessage())
        
        currentSessionId = nil
        sessionDevices.removeAll()
    }
    
    /// Request to become primary device for current session
    public func requestPrimary() async throws {
        guard let webSocketManager = webSocketManager,
              let sessionId = currentSessionId else {
            throw DeviceCoordinationError.noActiveSession
        }
        
        logger.info("Requesting primary status for session: \(sessionId)")
        primaryElectionStatus = .requesting
        
        let message = DeviceMessage.primaryElectionRequest(
            deviceId: currentDeviceId,
            sessionId: sessionId
        )
        
        try await webSocketManager.send(message.toWebSocketMessage())
    }
    
    /// Transfer primary status to another device
    public func transferPrimary(to deviceId: String) async throws {
        guard let webSocketManager = webSocketManager,
              let sessionId = currentSessionId,
              isPrimary else {
            throw DeviceCoordinationError.notPrimaryDevice
        }
        
        logger.info("Transferring primary status to device: \(deviceId)")
        primaryElectionStatus = .transferring
        
        let message = DeviceMessage.primaryTransferRequest(
            fromDeviceId: currentDeviceId,
            toDeviceId: deviceId,
            sessionId: sessionId
        )
        
        try await webSocketManager.send(message.toWebSocketMessage())
    }
    
    /// Release primary status
    public func releasePrimary() async throws {
        guard isPrimary else { return }
        
        logger.info("Releasing primary status")
        
        await MainActor.run {
            isPrimary = false
            primaryElectionStatus = .none
        }
    }
    
    /// Send heartbeat to maintain device presence
    public func sendHeartbeat() async {
        guard let webSocketManager = webSocketManager,
              registrationStatus == .registered else {
            return
        }
        
        let message = DeviceMessage.heartbeat(deviceId: currentDeviceId)
        
        do {
            try await webSocketManager.send(message.toWebSocketMessage())
            logger.debug("Heartbeat sent")
        } catch {
            logger.error("Failed to send heartbeat: \(error.localizedDescription)")
        }
    }
    
    /// Start automatic heartbeat
    public func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.sendHeartbeat()
            }
        }
        
        logger.info("Heartbeat started with interval: \(self.heartbeatInterval)s")
    }
    
    /// Stop automatic heartbeat
    public func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        logger.info("Heartbeat stopped")
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // Monitor app lifecycle
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.stopHeartbeat()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.startHeartbeat()
                Task { [weak self] in
                    await self?.sendHeartbeat()
                }
            }
            .store(in: &cancellables)
        #else
        // macOS equivalents
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.stopHeartbeat()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.startHeartbeat()
                Task { [weak self] in
                    await self?.sendHeartbeat()
                }
            }
            .store(in: &cancellables)
        #endif
    }
    
    private func setupWebSocketSubscriptions() {
        guard let webSocketManager = webSocketManager else { return }
        
        // Listen for WebSocket connection status
        webSocketManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                Task { [weak self] in
                    await self?.handleConnectionStatusChange(isConnected)
                }
            }
            .store(in: &cancellables)
        
        // Listen for incoming WebSocket messages
        webSocketManager.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                Task { [weak self] in
                    await self?.handleWebSocketMessage(message)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleConnectionStatusChange(_ isConnected: Bool) async {
        logger.info("WebSocket connection status changed: \(isConnected)")
        
        if isConnected {
            connectionStatus = .connected
            // Re-register device when reconnecting
            if registrationStatus == .registered {
                // Device was previously registered, re-announce
                // This would need userId from somewhere (dependency injection)
            }
        } else {
            connectionStatus = .disconnected
            registrationStatus = .unregistered
            isPrimary = false
            primaryElectionStatus = .none
            stopHeartbeat()
        }
    }
    
    private func handleWebSocketMessage(_ message: [String: Any]) async {
        guard let messageType = message["type"] as? String else {
            return
        }
        
        logger.debug("Received WebSocket message: \(messageType)")
        
        switch messageType {
        case "device-registered":
            await handleDeviceRegistered(message)
        case "device-unregistered":
            await handleDeviceUnregistered(message)
        case "session-joined":
            await handleSessionJoined(message)
        case "session-left":
            await handleSessionLeft(message)
        case "primary-elected":
            await handlePrimaryElected(message)
        case "primary-transferred":
            await handlePrimaryTransferred(message)
        case "primary-election-result":
            await handlePrimaryElectionResult(message)
        case "primary-transfer-result":
            await handlePrimaryTransferResult(message)
        case "heartbeat-ack":
            await handleHeartbeatAck(message)
        case "error":
            await handleErrorMessage(message)
        default:
            logger.debug("Unhandled message type: \(messageType)")
        }
    }
    
    private func handleDeviceRegistered(_ message: [String: Any]) async {
        logger.info("Device registered successfully")
        registrationStatus = .registered
        startHeartbeat()
    }
    
    private func handleDeviceUnregistered(_ message: [String: Any]) async {
        guard let deviceId = message["deviceId"] as? String else { return }
        
        logger.info("Device unregistered: \(deviceId)")
        
        if deviceId == currentDeviceId {
            registrationStatus = .unregistered
            isPrimary = false
            stopHeartbeat()
        } else {
            // Remove from active devices
            activeDevices.removeAll { $0.deviceId == deviceId }
        }
    }
    
    private func handleSessionJoined(_ message: [String: Any]) async {
        guard let sessionId = message["sessionId"] as? String,
              let devices = message["activeDevices"] as? [[String: Any]],
              let primaryDeviceId = message["primaryDeviceId"] as? String?,
              let isPrimaryBool = message["isPrimary"] as? Bool else {
            return
        }
        
        logger.info("Joined session: \(sessionId)")
        currentSessionId = sessionId
        isPrimary = isPrimaryBool
        
        // Update active devices
        activeDevices = devices.compactMap { deviceData in
            guard let deviceId = deviceData["deviceId"] as? String,
                  let platform = deviceData["platform"] as? String,
                  let lastSeen = deviceData["lastSeen"] as? TimeInterval,
                  let isPrimary = deviceData["isPrimary"] as? Bool else {
                return nil
            }
            
            return ActiveDevice(
                deviceId: deviceId,
                platform: platform,
                lastSeen: Date(timeIntervalSince1970: lastSeen / 1000),
                isPrimary: isPrimary
            )
        }
        
        if isPrimary {
            primaryElectionStatus = .primary
        } else if primaryDeviceId != nil {
            primaryElectionStatus = .secondary
        } else {
            primaryElectionStatus = .none
        }
    }
    
    private func handleSessionLeft(_ message: [String: Any]) async {
        logger.info("Left session")
        currentSessionId = nil
        sessionDevices.removeAll()
        isPrimary = false
        primaryElectionStatus = .none
    }
    
    private func handlePrimaryElected(_ message: [String: Any]) async {
        guard let sessionId = message["sessionId"] as? String,
              let deviceId = message["deviceId"] as? String else {
            return
        }
        
        logger.info("Primary elected for session \(sessionId): \(deviceId)")
        
        if sessionId == currentSessionId {
            isPrimary = (deviceId == currentDeviceId)
            primaryElectionStatus = isPrimary ? .primary : .secondary
            
            // Update active devices primary status
            for i in activeDevices.indices {
                activeDevices[i].isPrimary = (activeDevices[i].deviceId == deviceId)
            }
        }
    }
    
    private func handlePrimaryTransferred(_ message: [String: Any]) async {
        guard let sessionId = message["sessionId"] as? String,
              let fromDeviceId = message["fromDeviceId"] as? String,
              let toDeviceId = message["toDeviceId"] as? String else {
            return
        }
        
        logger.info("Primary transferred in session \(sessionId): \(fromDeviceId) -> \(toDeviceId)")
        
        if sessionId == currentSessionId {
            isPrimary = (toDeviceId == currentDeviceId)
            primaryElectionStatus = isPrimary ? .primary : .secondary
            
            // Update active devices
            for i in activeDevices.indices {
                activeDevices[i].isPrimary = (activeDevices[i].deviceId == toDeviceId)
            }
        }
    }
    
    private func handlePrimaryElectionResult(_ message: [String: Any]) async {
        guard let success = message["success"] as? Bool,
              let isPrimaryBool = message["isPrimary"] as? Bool else {
            return
        }
        
        if success {
            isPrimary = isPrimaryBool
            primaryElectionStatus = isPrimary ? .primary : .secondary
            logger.info("Primary election successful: \(self.isPrimary)")
        } else {
            primaryElectionStatus = .failed
            if let reason = message["reason"] as? String {
                logger.info("Primary election failed: \(reason)")
            }
        }
    }
    
    private func handlePrimaryTransferResult(_ message: [String: Any]) async {
        guard let success = message["success"] as? Bool else {
            return
        }
        
        if success {
            isPrimary = false
            primaryElectionStatus = .secondary
            logger.info("Primary transfer successful")
        } else {
            primaryElectionStatus = .failed
            if let reason = message["reason"] as? String {
                logger.info("Primary transfer failed: \(reason)")
            }
        }
    }
    
    private func handleHeartbeatAck(_ message: [String: Any]) async {
        // Heartbeat acknowledged, device is active
        logger.debug("Heartbeat acknowledged")
    }
    
    private func handleErrorMessage(_ message: [String: Any]) async {
        if let error = message["error"] as? String {
            logger.error("Server error: \(error)")
        }
    }
}

// MARK: - Supporting Types

public struct ActiveDevice: Identifiable, Codable {
    public let id = UUID()
    public let deviceId: String
    public let platform: String
    public let lastSeen: Date
    public var isPrimary: Bool
    
    public init(deviceId: String, platform: String, lastSeen: Date, isPrimary: Bool) {
        self.deviceId = deviceId
        self.platform = platform
        self.lastSeen = lastSeen
        self.isPrimary = isPrimary
    }
}

public enum RegistrationStatus: String, CaseIterable {
    case unregistered = "unregistered"
    case registering = "registering"
    case registered = "registered"
    case failed = "failed"
}

public enum PrimaryElectionStatus: String, CaseIterable {
    case none = "none"
    case requesting = "requesting"
    case primary = "primary"
    case secondary = "secondary"
    case transferring = "transferring"
    case failed = "failed"
}

public enum DeviceConnectionStatus: String, CaseIterable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case error = "error"
}

public enum DeviceCoordinationError: Error, LocalizedError {
    case webSocketNotAvailable
    case noActiveSession
    case notPrimaryDevice
    case registrationFailed
    case primaryElectionFailed
    
    public var errorDescription: String? {
        switch self {
        case .webSocketNotAvailable:
            return "WebSocket connection is not available"
        case .noActiveSession:
            return "No active session for device coordination"
        case .notPrimaryDevice:
            return "Device is not the primary device for this session"
        case .registrationFailed:
            return "Device registration failed"
        case .primaryElectionFailed:
            return "Primary device election failed"
        }
    }
}

// MARK: - Device Message Types

private enum DeviceMessage {
    case announce(deviceId: String, userId: String, deviceInfo: DeviceInfo)
    case heartbeat(deviceId: String)
    case sessionJoin(deviceId: String, sessionId: String)
    case sessionLeave(deviceId: String, sessionId: String)
    case primaryElectionRequest(deviceId: String, sessionId: String)
    case primaryTransferRequest(fromDeviceId: String, toDeviceId: String, sessionId: String)
    
    func toWebSocketMessage() -> [String: Any] {
        switch self {
        case .announce(let deviceId, let userId, let deviceInfo):
            return [
                "type": "device-announce",
                "deviceId": deviceId,
                "userId": userId,
                "deviceInfo": [
                    "platform": deviceInfo.platform,
                    "appVersion": deviceInfo.appVersion,
                    "systemVersion": deviceInfo.systemVersion,
                    "deviceName": deviceInfo.deviceName
                ]
            ]
            
        case .heartbeat(let deviceId):
            return [
                "type": "device-heartbeat",
                "deviceId": deviceId,
                "timestamp": Date().timeIntervalSince1970 * 1000
            ]
            
        case .sessionJoin(let deviceId, let sessionId):
            return [
                "type": "session-join",
                "deviceId": deviceId,
                "sessionId": sessionId
            ]
            
        case .sessionLeave(let deviceId, let sessionId):
            return [
                "type": "session-leave",
                "deviceId": deviceId,
                "sessionId": sessionId
            ]
            
        case .primaryElectionRequest(let deviceId, let sessionId):
            return [
                "type": "primary-election-request",
                "deviceId": deviceId,
                "sessionId": sessionId
            ]
            
        case .primaryTransferRequest(let fromDeviceId, let toDeviceId, let sessionId):
            return [
                "type": "primary-transfer-request",
                "fromDeviceId": fromDeviceId,
                "toDeviceId": toDeviceId,
                "sessionId": sessionId
            ]
        }
    }
}