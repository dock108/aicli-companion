import Foundation
import Combine
import Network

/// Manages WebSocket connection for real-time status updates
@MainActor
@available(iOS 16.0, macOS 13.0, *)
final class WebSocketManager: ObservableObject {
    // MARK: - Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared
    private var pingTimer: Timer?
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private let logger = Logger(subsystem: "com.aiclicompanion", category: "WebSocket")
    
    // MARK: - Connection Management
    
    func connect(to serverURL: String, token: String?) {
        disconnect() // Ensure clean state
        
        // Convert HTTP/HTTPS URL to WS/WSS
        var wsURL = serverURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        
        // Append /ws path
        if !wsURL.hasSuffix("/ws") {
            wsURL = wsURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/ws"
        }
        
        // Add token as query parameter if provided
        if let token = token {
            wsURL += "?token=\(token)"
        }
        
        guard let url = URL(string: wsURL) else {
            connectionError = "Invalid WebSocket URL"
            logger.error("Invalid WebSocket URL: \(wsURL)")
            return
        }
        
        logger.info("Connecting to WebSocket: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 45 // Allow more time for initial connection
        
        // For development with ngrok, create a session that allows self-signed certificates
        let config = URLSessionConfiguration.default
        let sessionWithoutCertValidation = URLSession(configuration: config, delegate: WebSocketDelegate(), delegateQueue: nil)
        
        webSocketTask = sessionWithoutCertValidation.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        connectionError = nil
        
        // Start receiving messages
        receiveMessage()
        
        // Start ping timer to keep connection alive
        startPingTimer()
    }
    
    func disconnect() {
        logger.info("Disconnecting WebSocket")
        
        stopPingTimer()
        
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
        
        isConnected = false
    }
    
    // MARK: - Message Handling
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // Continue receiving messages
                    self.receiveMessage()
                    
                case .failure(let error):
                    self.handleError(error)
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseAndProcessMessage(text)
            
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseAndProcessMessage(text)
            }
            
        @unknown default:
            logger.warning("Received unknown WebSocket message type")
        }
    }
    
    private func parseAndProcessMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                
                logger.debug("Received WebSocket message type: \(type)")
                
                switch type {
                case "heartbeat":
                    handleHeartbeat(json)
                    
                case "welcome":
                    logger.info("WebSocket connected successfully")
                    
                case "error":
                    if let message = json["message"] as? String {
                        logger.error("Server error: \(message)")
                        connectionError = message
                    }
                    
                default:
                    logger.debug("Unhandled message type: \(type)")
                }
            }
        } catch {
            logger.error("Failed to parse WebSocket message: \(error)")
        }
    }
    
    private func handleHeartbeat(_ data: [String: Any]) {
        // Enhanced logging for debugging heartbeat data
        print("📡 WebSocket: Received heartbeat data: \(data)")
        
        // Post notification with heartbeat data for other components to handle
        NotificationCenter.default.post(
            name: .claudeHeartbeatReceived,
            object: nil,
            userInfo: data
        )
        
        // Log heartbeat details
        if let sessionId = data["sessionId"] as? String,
           let activity = data["activity"] as? String,
           let elapsed = data["elapsedSeconds"] as? Int,
           let isProcessing = data["isProcessing"] as? Bool,
           let projectPath = data["projectPath"] as? String {
            print("📡 Heartbeat details:")
            print("   Session: \(sessionId)")
            print("   Project: \(projectPath)")
            print("   Activity: \(activity)")
            print("   Elapsed: \(elapsed)s")
            print("   Processing: \(isProcessing)")
            logger.debug("Heartbeat: session=\(sessionId), activity=\(activity), elapsed=\(elapsed)s, processing=\(isProcessing)")
        } else {
            print("⚠️ Heartbeat data missing expected fields")
            print("   sessionId: \(data["sessionId"] ?? "missing")")
            print("   activity: \(data["activity"] ?? "missing")")
            print("   elapsedSeconds: \(data["elapsedSeconds"] ?? "missing")")
            print("   isProcessing: \(data["isProcessing"] ?? "missing")")
            print("   projectPath: \(data["projectPath"] ?? "missing")")
        }
    }
    
    private func handleError(_ error: Error) {
        logger.error("WebSocket error: \(error)")
        
        isConnected = false
        
        // Determine if we should try to reconnect
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                // User initiated disconnect, don't reconnect
                connectionError = nil
                
            case .timedOut, .networkConnectionLost:
                // Network issue, try to reconnect
                connectionError = "Connection lost. Retrying..."
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    // Reconnect logic would go here
                }
                
            default:
                connectionError = urlError.localizedDescription
            }
        } else {
            connectionError = error.localizedDescription
        }
    }
    
    // MARK: - Keep Alive
    
    private func startPingTimer() {
        stopPingTimer()
        
        // Send ping every 20 seconds (server checks every 30s, gives us buffer)
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.logger.error("Ping failed: \(error)")
                Task { @MainActor [weak self] in
                    self?.handleError(error)
                }
            }
        }
    }
    
    // MARK: - Sending Messages
    
    func send(_ message: [String: Any]) {
        guard isConnected else {
            logger.warning("Cannot send message - WebSocket not connected")
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            let message = URLSessionWebSocketTask.Message.data(data)
            
            webSocketTask?.send(message) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to send message: \(error)")
                }
            }
        } catch {
            logger.error("Failed to serialize message: \(error)")
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Clean up WebSocket task without calling MainActor methods
        pingTimer?.invalidate()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - WebSocket SSL Delegate

@available(iOS 16.0, macOS 13.0, *)
class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolName: String?) {
        print("🔌 WebSocket connected with protocol: \(protocolName ?? "none")")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket closed with code: \(closeCode)")
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // For development with ngrok, allow self-signed certificates
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            print("🔒 Accepting server trust for development (ngrok)")
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        
        // Default handling for other authentication methods
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let claudeHeartbeatReceived = Notification.Name("claudeHeartbeatReceived")
}

// MARK: - Logger

import os.log

private struct Logger {
    private let log: OSLog
    
    init(subsystem: String, category: String) {
        self.log = OSLog(subsystem: subsystem, category: category)
    }
    
    func debug(_ message: String) {
        os_log(.debug, log: log, "%{public}@", message)
    }
    
    func info(_ message: String) {
        os_log(.info, log: log, "%{public}@", message)
    }
    
    func warning(_ message: String) {
        os_log(.default, log: log, "⚠️ %{public}@", message)
    }
    
    func error(_ message: String) {
        os_log(.error, log: log, "❌ %{public}@", message)
    }
}