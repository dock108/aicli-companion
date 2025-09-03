import Foundation
import Combine
import OSLog

// MARK: - WebSocketManager Device Coordination Extension

@available(iOS 16.0, macOS 13.0, *)
extension WebSocketManager {
    
    // MARK: - Device Message Publisher
    
    /// Publisher for device coordination messages
    public var messagePublisher: AnyPublisher<[String: Any], Never> {
        NotificationCenter.default.publisher(for: .deviceCoordinationMessageReceived)
            .compactMap { notification in
                notification.userInfo as? [String: Any]
            }
            .eraseToAnyPublisher()
    }
    
    /// Connection status enum for device coordination
    public enum ConnectionStatus: String, CaseIterable {
        case disconnected = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
        case error = "error"
    }
    
    /// Current connection status
    public var connectionStatus: ConnectionStatus {
        if isConnected {
            return .connected
        } else if connectionError != nil {
            return .error
        } else {
            return .disconnected
        }
    }
    
    // MARK: - Device Message Sending
    
    /// Send device coordination message
    public func send(_ message: [String: Any]) async throws {
        guard isConnected, let webSocketTask = webSocketTask else {
            throw WebSocketError.notConnected
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
            
            return try await withCheckedThrowingContinuation { continuation in
                webSocketTask.send(wsMessage) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            logger.error("Failed to send device message: \(error)")
            throw error
        }
    }
    
    // MARK: - Enhanced Message Handling
    
    /// Enhanced message parsing to handle device coordination messages
    private func parseAndProcessDeviceMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                logger.debug("Received WebSocket message type: \(type)")
                
                // Handle device coordination messages
                if isDeviceCoordinationMessage(type) {
                    handleDeviceCoordinationMessage(type: type, data: json)
                } else {
                    // Handle existing message types
                    handleStandardMessage(type: type, data: json)
                }
            }
        } catch {
            logger.error("Failed to parse WebSocket message: \(error)")
        }
    }
    
    /// Check if message type is device coordination related
    private func isDeviceCoordinationMessage(_ type: String) -> Bool {
        return [
            "device-registered",
            "device-unregistered", 
            "session-joined",
            "session-left",
            "primary-elected",
            "primary-transferred",
            "primary-election-result",
            "primary-transfer-result",
            "primary-device-offline",
            "primary-device-timeout",
            "heartbeat-ack",
            "duplicate-message-detected"
        ].contains(type)
    }
    
    /// Handle device coordination messages
    private func handleDeviceCoordinationMessage(type: String, data: [String: Any]) {
        logger.info("Handling device coordination message: \(type)")
        
        // Post notification for DeviceCoordinator to handle
        NotificationCenter.default.post(
            name: .deviceCoordinationMessageReceived,
            object: nil,
            userInfo: data
        )
        
        // Log specific message details
        switch type {
        case "device-registered":
            if let deviceId = data["deviceId"] as? String {
                logger.info("Device registered: \(deviceId)")
            }
            
        case "primary-elected":
            if let sessionId = data["sessionId"] as? String,
               let deviceId = data["deviceId"] as? String {
                logger.info("Primary elected for session \(sessionId): \(deviceId)")
            }
            
        case "primary-transferred":
            if let sessionId = data["sessionId"] as? String,
               let fromDevice = data["fromDeviceId"] as? String,
               let toDevice = data["toDeviceId"] as? String {
                logger.info("Primary transferred in session \(sessionId): \(fromDevice) -> \(toDevice)")
            }
            
        case "duplicate-message-detected":
            if let sessionId = data["sessionId"] as? String,
               let deviceId = data["deviceId"] as? String,
               let messageHash = data["messageHash"] as? String {
                logger.warning("Duplicate message detected in session \(sessionId) from device \(deviceId): \(messageHash)")
            }
            
        default:
            logger.debug("Unhandled device coordination message: \(type)")
        }
    }
    
    /// Handle standard (non-device) messages
    private func handleStandardMessage(type: String, data: [String: Any]) {
        switch type {
        case "heartbeat":
            handleHeartbeat(data)
            
        case "welcome":
            logger.info("WebSocket connected successfully")
            
        case "error":
            if let message = data["message"] as? String {
                logger.error("Server error: \(message)")
                connectionError = message
            }
            
        default:
            logger.debug("Unhandled standard message type: \(type)")
        }
    }
    
    // MARK: - Device-Specific Connection Management
    
    /// Connect with device identification
    public func connectWithDeviceId(_ deviceId: String, to serverURL: String, token: String?) {
        // Store device ID for connection
        UserDefaults.standard.set(deviceId, forKey: "device_id")
        
        // Connect normally
        connect(to: serverURL, token: token)
    }
    
    /// Send device announcement after connection
    public func announceDevice(deviceId: String, userId: String, deviceInfo: [String: Any]) async throws {
        let message: [String: Any] = [
            "type": "device-announce",
            "deviceId": deviceId,
            "userId": userId,
            "deviceInfo": deviceInfo
        ]
        
        try await send(message)
        logger.info("Device announced: \(deviceId)")
    }
    
    /// Send heartbeat with device ID
    public func sendDeviceHeartbeat(deviceId: String) async throws {
        let message: [String: Any] = [
            "type": "device-heartbeat",
            "deviceId": deviceId,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        try await send(message)
        logger.debug("Device heartbeat sent: \(deviceId)")
    }
    
    // MARK: - Connection Status Updates
    
    public enum DeviceConnectionStatus: String, CaseIterable {
        case disconnected = "disconnected"
        case connecting = "connecting" 
        case connected = "connected"
        case deviceRegistered = "deviceRegistered"
        case sessionJoined = "sessionJoined"
        case error = "error"
    }
    
    /// Update device connection status
    private func updateDeviceConnectionStatus(_ status: DeviceConnectionStatus) {
        // Post notification instead of setting property
        NotificationCenter.default.post(name: .deviceConnectionStatusChanged, object: status)
    }
}

// MARK: - WebSocket Error Types

extension WebSocketManager {
    public enum WebSocketError: Error, LocalizedError {
        case notConnected
        case invalidMessage
        case encodingFailed
        case sendTimeout
        
        public var errorDescription: String? {
            switch self {
            case .notConnected:
                return "WebSocket is not connected"
            case .invalidMessage:
                return "Invalid message format"
            case .encodingFailed:
                return "Failed to encode message"
            case .sendTimeout:
                return "Message send timeout"
            }
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let deviceCoordinationMessageReceived = Notification.Name("deviceCoordinationMessageReceived")
    static let deviceConnectionStatusChanged = Notification.Name("deviceConnectionStatusChanged")
    static let deviceHeartbeatSent = Notification.Name("deviceHeartbeatSent")
}

// MARK: - Logger Extension for Device Coordination

private extension os.Logger {
    init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "AICLICompanion", category: category)
    }
}

// MARK: - WebSocket Delegate Enhancement

@available(iOS 16.0, macOS 13.0, *)
extension WebSocketManager {
    
    /// Enhanced WebSocket delegate for device coordination
    class DeviceAwareWebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
        weak var webSocketManager: WebSocketManager?
        
        init(webSocketManager: WebSocketManager) {
            self.webSocketManager = webSocketManager
        }
        
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolName: String?) {
            print("🔌 WebSocket connection established with protocol: \(protocolName ?? "none")")
            
            Task { @MainActor in
                webSocketManager?.isConnected = true
                webSocketManager?.connectionError = nil
                webSocketManager?.updateDeviceConnectionStatus(.connected)
            }
        }
        
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            print("🔌 WebSocket connection closed with code: \(closeCode)")
            
            Task { @MainActor in
                webSocketManager?.isConnected = false
                webSocketManager?.updateDeviceConnectionStatus(.disconnected)
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                print("🔌 WebSocket task completed with error: \(error)")
                
                Task { @MainActor in
                    webSocketManager?.isConnected = false
                    webSocketManager?.connectionError = error.localizedDescription
                    webSocketManager?.updateDeviceConnectionStatus(.error)
                }
            }
        }
    }
}

// MARK: - Device Coordination Helper Methods

@available(iOS 16.0, macOS 13.0, *)
extension WebSocketManager {
    
    /// Get current device ID
    public var currentDeviceId: String? {
        return UserDefaults.standard.string(forKey: "device_id")
    }
    
    /// Check if device is registered
    public var isDeviceRegistered: Bool {
        // Check if device is registered through DeviceCoordinator
        return DeviceCoordinator.shared.registrationStatus == .registered
    }
    
    /// Check if device is in a session
    public var isInSession: Bool {
        // Check if in session through DeviceCoordinator
        return DeviceCoordinator.shared.currentSessionId != nil
    }
    
    /// Send session join message
    public func joinSession(deviceId: String, sessionId: String) async throws {
        let message: [String: Any] = [
            "type": "session-join",
            "deviceId": deviceId,
            "sessionId": sessionId
        ]
        
        try await send(message)
        logger.info("Joining session: \(sessionId)")
    }
    
    /// Send session leave message
    public func leaveSession(deviceId: String, sessionId: String) async throws {
        let message: [String: Any] = [
            "type": "session-leave",
            "deviceId": deviceId,
            "sessionId": sessionId
        ]
        
        try await send(message)
        logger.info("Leaving session: \(sessionId)")
    }
    
    /// Request primary device status
    public func requestPrimary(deviceId: String, sessionId: String) async throws {
        let message: [String: Any] = [
            "type": "primary-election-request",
            "deviceId": deviceId,
            "sessionId": sessionId
        ]
        
        try await send(message)
        logger.info("Requesting primary status for session: \(sessionId)")
    }
    
    /// Transfer primary device status
    public func transferPrimary(fromDeviceId: String, toDeviceId: String, sessionId: String) async throws {
        let message: [String: Any] = [
            "type": "primary-transfer-request",
            "fromDeviceId": fromDeviceId,
            "toDeviceId": toDeviceId,
            "sessionId": sessionId
        ]
        
        try await send(message)
        logger.info("Transferring primary status from \(fromDeviceId) to \(toDeviceId)")
    }
}