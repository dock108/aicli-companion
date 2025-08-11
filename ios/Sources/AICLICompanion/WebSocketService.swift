import Foundation
import Combine
import Starscream
#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
class WebSocketService: ObservableObject, WebSocketDelegate {
    static let shared = WebSocketService()
    
    @Published var isConnected = false
    @Published var connectionState: WebSocketConnectionState = .disconnected

    private var webSocket: WebSocket?
    private var cancellables = Set<AnyCancellable>()
    private var pendingMessages: [WebSocketMessage] = []
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30
    private let reliabilityManager = ConnectionReliabilityManager.shared

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Message handlers
    private var messageHandlers: [WebSocketMessageType: (WebSocketMessage) -> Void] = [:]
    private var globalMessageHandlers: [WebSocketMessageType: [(WebSocketMessage) -> Void]] = [:]
    private var requestCallbacks: [String: (Result<WebSocketMessage, AICLICompanionError>) -> Void] = [:]
    
    // Track active sessions for resubscription
    private var activeSessions: Set<String> = []

    // Connection info
    private var currentURL: URL?
    private var authToken: String?
    
    // Message callback
    var onMessage: ((WebSocketMessage) -> Void)?
    
    // Session tracking
    private var activeSessionId: String?
    private var wasConnectedBeforeBackground = false
    
    // Background connection support
    private var backgroundWebSocket: WebSocket?
    private var backgroundConnectionCompletion: CheckedContinuation<Bool, Never>?
    private var backgroundMessageCompletion: CheckedContinuation<[Message], Never>?
    private var backgroundMessages: [Message] = []

    init() {
        setupDateFormatters()
        setupAppLifecycleObservers()
    }

    deinit {
        disconnect()
        #if os(iOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    // MARK: - App Lifecycle Management
    
    private func setupAppLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func appWillResignActive() {
        print("🌙 App will resign active - preserving WebSocket state")
        wasConnectedBeforeBackground = isConnected
        
        // Don't disconnect immediately - wait a few seconds to see if this is just a brief navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            
            // Only disconnect if the app is still in background after delay
            #if os(iOS)
            let shouldDisconnect = UIApplication.shared.applicationState != .active && self.isConnected
            #else
            let shouldDisconnect = self.isConnected
            #endif
            
            if shouldDisconnect {
                print("🌙 App still in background after delay - sending backgrounding message")
                
                // Send a graceful backgrounding message
                let disconnectMessage: [String: Any] = [
                    "type": "client_backgrounding",
                    "sessionId": self.activeSessionId ?? "",
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
                if let data = try? JSONSerialization.data(withJSONObject: disconnectMessage),
                   let message = String(data: data, encoding: .utf8) {
                    self.webSocket?.write(string: message)
                }
                
                // Pause heartbeat but don't disconnect the WebSocket
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = nil
            }
        }
    }
    
    @objc private func appDidBecomeActive() {
        print("☀️ App did become active - checking WebSocket state")
        
        // If we have a connection but heartbeat is stopped, restart it
        if isConnected && heartbeatTimer == nil {
            print("🔄 Restarting heartbeat for existing connection")
            startHeartbeat()
        }
        // Only create new connection if we don't have one and were connected before
        else if !isConnected && wasConnectedBeforeBackground, let url = currentURL {
            print("🔄 Restoring WebSocket connection")
            connect(to: url, authToken: authToken)
        }
    }
    
    @objc private func appWillTerminate() {
        print("💀 App will terminate - closing WebSocket connection")
        disconnect()
    }

    // MARK: - Session Management
    
    func setActiveSession(_ sessionId: String?) {
        self.activeSessionId = sessionId
    }
    
    func getActiveSession() -> String? {
        return activeSessionId
    }
    
    // MARK: - Device Token Management
    
    func sendDeviceToken(_ token: String) {
        guard isConnected else {
            print("⚠️ Cannot send device token - not connected")
            return
        }
        
        let request = RegisterDeviceRequest(
            token: token,
            platform: "ios"
        )
        
        sendMessage(request, type: .registerDevice) { result in
            switch result {
            case .success:
                print("✅ Device token sent to server")
            case .failure(let error):
                print("❌ Failed to send device token: \(error)")
            }
        }
    }

    // MARK: - Connection Management

    func connect(to url: URL, authToken: String?) {
        disconnect() // Ensure clean state

        self.currentURL = url
        self.authToken = authToken

        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        urlComponents.scheme = url.scheme == "https" ? "wss" : "ws"
        urlComponents.path = "/ws"

        if let token = authToken {
            urlComponents.queryItems = [URLQueryItem(name: "token", value: token)]
        }

        guard let wsURL = urlComponents.url else {
            updateConnectionState(.error("Invalid WebSocket URL"))
            return
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 30

        webSocket = WebSocket(request: request)
        webSocket?.delegate = self

        updateConnectionState(.connecting)
        webSocket?.connect()
    }

    func disconnect() {
        reliabilityManager.cancelReconnection()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        webSocket?.disconnect()
        webSocket = nil

        updateConnectionState(.disconnected)
    }
    
    /// Acknowledge receipt of messages
    func acknowledgeMessages(_ messageIds: [String], completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        let request = AcknowledgeMessagesRequest(messageIds: messageIds)
        
        sendMessage(request, type: .acknowledgeMessages) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Send clear chat message to server
    func sendClearChat(sessionId: String, completion: @escaping (Result<String, AICLICompanionError>) -> Void) {
        let request = ClearChatRequest(sessionId: sessionId)
        
        sendMessage(request, type: .clearChat) { result in
            switch result {
            case .success(let message):
                if case .clearChatResponse(let response) = message.data {
                    completion(.success(response.newSessionId))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func attemptReconnect() {
        guard let url = currentURL else {
            updateConnectionState(.error("No URL available for reconnection"))
            return
        }

        reliabilityManager.scheduleReconnection { [weak self] in
            self?.connect(to: url, authToken: self?.authToken)
        }
    }

    private func updateConnectionState(_ state: WebSocketConnectionState) {
        print("🔄 WebSocket: Updating connection state to \(state)")
        DispatchQueue.main.async {
            let oldState = self.connectionState
            let oldConnected = self.isConnected
            
            self.connectionState = state
            self.isConnected = (state == .connected)
            
            print("   State changed: \(oldState) → \(state)")
            print("   Connected changed: \(oldConnected) → \(self.isConnected)")
            
            // Update connection reliability manager
            if state == .connected {
                print("   Notifying reliability manager: connection established")
                self.reliabilityManager.handleConnectionEstablished()
            } else if state == .disconnected {
                print("   Notifying reliability manager: connection lost")
                self.reliabilityManager.handleConnectionLost()
            }
        }
    }

    // MARK: - Message Sending

    func sendMessage<T: Codable>(_ messageData: T, type: WebSocketMessageType, requestId: String? = nil, completion: ((Result<WebSocketMessage, AICLICompanionError>) -> Void)? = nil) {
        let requestIdToUse = requestId ?? UUID().uuidString

        do {
            let data = try encoder.encode(messageData)
            let dataDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            let message = [
                "type": type.rawValue,
                "requestId": requestIdToUse,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "data": dataDict
            ] as [String: Any]

            let messageData = try JSONSerialization.data(withJSONObject: message)
            let messageString = String(data: messageData, encoding: .utf8)!

            if let completion = completion {
                requestCallbacks[requestIdToUse] = completion
            }

            if isConnected {
                print("📨 Sending WebSocket message: \(type.rawValue)")
                print("   Message: \(messageString)")
                webSocket?.write(string: messageString)
            } else {
                print("⚠️ WebSocket not connected, queueing message: \(type.rawValue)")
                // Queue message for when connection is restored
                if let wsMessage = try? decoder.decode(WebSocketMessage.self, from: messageData) {
                    pendingMessages.append(wsMessage)
                }
            }
        } catch {
            completion?(.failure(.jsonParsingError(error)))
        }
    }

    func sendAsk(prompt: String, workingDirectory: String? = nil, completion: @escaping (Result<AICLIResponse, AICLICompanionError>) -> Void) {
        let request = AskRequest(
            prompt: prompt,
            workingDirectory: workingDirectory,
            options: AskOptions(format: "json", timeout: 60)
        )

        sendMessage(request, type: .ask) { result in
            switch result {
            case .success(let message):
                // Parse response from message data
                if case .askResponse(let responseData) = message.data {
                    if responseData.success, let aicliResponse = responseData.response {
                        completion(.success(aicliResponse))
                    } else {
                        completion(.failure(.invalidResponse))
                    }
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func startStream(prompt: String, workingDirectory: String? = nil, sessionName: String? = nil, completion: @escaping (Result<String, AICLICompanionError>) -> Void) {
        let request = StreamStartRequest(
            prompt: prompt,
            workingDirectory: workingDirectory,
            options: StreamOptions(sessionName: sessionName, preserveContext: true)
        )

        sendMessage(request, type: .streamStart) { [weak self] result in
            switch result {
            case .success(let message):
                if case .streamStarted(let response) = message.data {
                    // Track the new session
                    self?.trackSession(response.sessionId)
                    completion(.success(response.sessionId))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func sendToStream(sessionId: String, prompt: String) {
        let request = StreamSendRequest(sessionId: sessionId, prompt: prompt)
        sendMessage(request, type: .streamSend)
    }

    func respondToPermission(sessionId: String, response: String, remember: Bool = false) {
        let permissionResponse = PermissionResponse(
            sessionId: sessionId,
            response: response,
            remember: remember
        )
        sendMessage(permissionResponse, type: .permission)
    }

    func closeStream(sessionId: String, reason: String = "user_requested") {
        let request = StreamCloseRequest(sessionId: sessionId, reason: reason)
        sendMessage(request, type: .streamClose)
        
        // Untrack the session
        untrackSession(sessionId)
    }

    func setWorkingDirectory(_ workingDirectory: String, completion: @escaping (Result<Bool, AICLICompanionError>) -> Void) {
        let request = SetWorkingDirectoryRequest(workingDirectory: workingDirectory)

        sendMessage(request, type: .setWorkingDirectory) { result in
            switch result {
            case .success(let message):
                if case .workingDirectorySet(let response) = message.data {
                    completion(.success(response.success))
                } else {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Session Management
    
    func trackSession(_ sessionId: String) {
        activeSessions.insert(sessionId)
        print("📝 Tracking session: \(sessionId)")
        print("   Active sessions: \(activeSessions.count)")
    }
    
    func untrackSession(_ sessionId: String) {
        activeSessions.remove(sessionId)
        print("🗑️ Untracking session: \(sessionId)")
        print("   Active sessions: \(activeSessions.count)")
    }
    
    func subscribeToSessions(_ sessionIds: [String]? = nil) {
        guard isConnected else {
            print("⚠️ Cannot subscribe to sessions - not connected")
            return
        }
        
        let sessionsToSubscribe = sessionIds ?? Array(activeSessions)
        
        guard !sessionsToSubscribe.isEmpty else {
            print("⚠️ No sessions to subscribe to")
            return
        }
        
        print("📬 Subscribing to \(sessionsToSubscribe.count) session(s): \(sessionsToSubscribe)")
        
        let request = SubscribeRequest(
            events: ["streamData", "streamComplete", "toolUse", "toolResult", "assistantMessage"],
            sessionIds: sessionsToSubscribe
        )
        
        sendMessage(request, type: .subscribe) { result in
            switch result {
            case .success(let message):
                print("✅ Successfully subscribed to sessions")
                if case .subscribed(let response) = message.data {
                    print("   Subscribed to \(response.sessionIds.count) sessions")
                }
            case .failure(let error):
                print("❌ Failed to subscribe to sessions: \(error)")
                // Retry subscription after a delay if connection is still active
                if self.isConnected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("🔄 Retrying session subscription after failure")
                        self.subscribeToSessions(sessionsToSubscribe)
                    }
                }
            }
        }
    }

    // MARK: - Message Handling

    func setMessageHandler(for type: WebSocketMessageType, handler: @escaping (WebSocketMessage) -> Void) {
        messageHandlers[type] = handler
    }
    
    /// Set a global message handler that will be called for all messages of a type, regardless of view state
    func setGlobalMessageHandler(for type: WebSocketMessageType, handler: @escaping (WebSocketMessage) -> Void) {
        if globalMessageHandlers[type] == nil {
            globalMessageHandlers[type] = []
        }
        globalMessageHandlers[type]?.append(handler)
    }

    private func handleReceivedMessage(_ messageString: String) {
        guard let data = messageString.data(using: .utf8) else { return }

        do {
            // First try to parse as a basic message to get type and requestId
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let typeString = json?["type"] as? String,
                  let type = WebSocketMessageType(rawValue: typeString) else {
                return
            }

            let requestId = json?["requestId"] as? String
            let message = try decoder.decode(WebSocketMessage.self, from: data)

            // Validate message before processing
            guard MessageValidator.isValidWebSocketMessage(message) else {
                print("🚫 Dropping invalid message of type: \(type)")
                return
            }

            // Handle request/response correlation
            if let requestId = requestId, let callback = requestCallbacks.removeValue(forKey: requestId) {
                callback(.success(message))
                return
            }

            // Handle specific message types
            switch type {
            case .welcome:
                handleWelcomeMessage(message)
            case .streamData:
                handleStreamData(message)
            case .streamToolUse:
                handleStreamToolUse(message)
            case .permissionRequest:
                handlePermissionRequest(message)
            case .streamComplete:
                handleStreamComplete(message)
            case .error:
                handleErrorMessage(message)
            case .pong:
                handlePongMessage(message)

            // New rich message types
            case .systemInit:
                handleSystemInit(message)
            case .assistantMessage:
                handleAssistantMessage(message)
            case .toolUse:
                handleToolUse(message)
            case .toolResult:
                handleToolResult(message)
            case .conversationResult:
                handleConversationResult(message)
            case .workingDirectorySet:
                handleWorkingDirectorySet(message)
            
            // Progress and status message types
            case .progress:
                handleProgressMessage(message)
            
            // Stream chunk for sophisticated streaming
            case .streamChunk:
                handleStreamChunk(message)
            
            // Message history response
            case .getMessageHistory:
                handleGetMessageHistory(message)
                
            // Claude response
            case .claudeResponse:
                handleClaudeResponse(message)

            default:
                break
            }

            // Call global message callback
            onMessage?(message)
            
            // Call registered handler if available
            messageHandlers[type]?(message)
            
            // Call global handlers (these run regardless of view state)
            if let globalHandlers = globalMessageHandlers[type] {
                for handler in globalHandlers {
                    handler(message)
                }
            }
        } catch {
            print("Failed to parse WebSocket message: \(error)")
        }
    }

    private func handleWelcomeMessage(_ message: WebSocketMessage) {
        if case .welcome(let welcome) = message.data {
            print("🎉 WebSocket: Received welcome message from server \(welcome.serverVersion)")
            print("   Setting connection state to CONNECTED")
            updateConnectionState(.connected)
            print("   Resetting reliability manager reconnection state")
            reliabilityManager.resetReconnectionState()

            // Send any pending messages
            sendPendingMessages()

            // Start heartbeat
            startHeartbeat()
            
            // Subscribe to active sessions immediately after connection
            if !activeSessions.isEmpty {
                print("🔄 Auto-subscribing to \(activeSessions.count) active session(s) after connection")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.subscribeToSessions()
                }
            }
            
            // Send device token if we have one
            #if os(iOS)
            if let deviceToken = UserDefaults.standard.string(forKey: "devicePushToken") {
                sendDeviceToken(deviceToken)
            }
            #endif
            
            // Resubscribe to active sessions after reconnection
            if !activeSessions.isEmpty {
                print("🔄 Resubscribing to \(activeSessions.count) active session(s) after reconnection")
                // Delay slightly to ensure server is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.subscribeToSessions()
                }
            }
        }
    }

    private func handleStreamData(_ message: WebSocketMessage) {
        // This will be handled by registered handlers in the UI
    }

    private func handleStreamToolUse(_ message: WebSocketMessage) {
        // This will be handled by registered handlers in the UI
    }

    private func handlePermissionRequest(_ message: WebSocketMessage) {
        // This will be handled by registered handlers in the UI
    }

    private func handleStreamComplete(_ message: WebSocketMessage) {
        // This will be handled by registered handlers in the UI
    }

    private func handleErrorMessage(_ message: WebSocketMessage) {
        if case .error(let error) = message.data {
            print("Server error: \(error.message)")
        }
    }


    private func handlePongMessage(_ message: WebSocketMessage) {
        // Heartbeat acknowledged
    }

    // MARK: - Rich Message Handlers

    private func handleSystemInit(_ message: WebSocketMessage) {
        if case .systemInit(let systemInit) = message.data {
            print("System initialized: \(systemInit.type), Tools: \(systemInit.availableTools.joined(separator: ", "))")
        }
        // This will be handled by registered handlers in the UI
    }

    private func handleAssistantMessage(_ message: WebSocketMessage) {
        if case .assistantMessage(let assistantMsg) = message.data {
            print("Assistant message: \(assistantMsg.type), Content blocks: \(assistantMsg.content.count)")
        }
        // This will be handled by registered handlers in the UI
    }

    private func handleToolUse(_ message: WebSocketMessage) {
        if case .toolUse(let toolUse) = message.data {
            print("Tool use: \(toolUse.toolName) with ID \(toolUse.toolId)")
        }
        // This will be handled by registered handlers in the UI
    }

    private func handleToolResult(_ message: WebSocketMessage) {
        if case .toolResult(let toolResult) = message.data {
            print("Tool result: \(toolResult.toolName) - Success: \(toolResult.success)")
        }
        // This will be handled by registered handlers in the UI
    }

    private func handleConversationResult(_ message: WebSocketMessage) {
        if case .conversationResult(let result) = message.data {
            print("Conversation result: Success: \(result.success), Duration: \(result.duration ?? 0)ms")
        }
        // This will be handled by registered handlers in the UI
    }

    private func handleWorkingDirectorySet(_ message: WebSocketMessage) {
        if case .workingDirectorySet(let response) = message.data {
            print("Working directory set: \(response.workingDirectory) - Success: \(response.success)")
        }
        // This will be handled by registered handlers in the UI
    }

    // MARK: - Utility Methods

    private func sendPendingMessages() {
        for message in pendingMessages {
            do {
                let data = try encoder.encode(message)
                let messageString = String(data: data, encoding: .utf8)!
                webSocket?.write(string: messageString)
            } catch {
                print("Failed to send pending message: \(error)")
            }
        }
        pendingMessages.removeAll()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    private func sendHeartbeat() {
        sendMessage(PingRequest(), type: .ping)
    }

    private func setupDateFormatters() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = formatter.date(from: string) {
                return date
            }

            // Fallback to standard ISO8601 without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            if let date = fallbackFormatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
    }

    private func handleProgressMessage(_ message: WebSocketMessage) {
        if case .progress(let progress) = message.data {
            print("Progress update: \(progress.stage) - \(progress.message)")
            if let progressValue = progress.progress {
                print("  Progress: \(Int(progressValue * 100))%")
            }
        }
        // This will be handled by registered handlers in the UI
    }
    
    private func handleStreamChunk(_ message: WebSocketMessage) {
        if case .streamChunk(let chunkResponse) = message.data {
            print("📦 Stream chunk received: \(chunkResponse.chunk.type) - isFinal: \(chunkResponse.chunk.isFinal)")
            
            // Log chunk details for debugging
            print("   Chunk ID: \(chunkResponse.chunk.id)")
            print("   Content length: \(chunkResponse.chunk.content.count) chars")
            if let metadata = chunkResponse.chunk.metadata {
                print("   Language: \(metadata.language ?? "none")")
                print("   Level: \(metadata.level ?? 0)")
            }
        }
        // This will be handled by registered handlers in the UI
    }
    
    private func handleGetMessageHistory(_ message: WebSocketMessage) {
        if case .getMessageHistoryResponse(let historyResponse) = message.data {
            print("📜 Received message history for session \(historyResponse.sessionId)")
            print("   Total messages: \(historyResponse.totalCount)")
            print("   Messages in response: \(historyResponse.messages.count)")
            print("   Has more: \(historyResponse.hasMore)")
            
            // Log each message for debugging
            for (index, msg) in historyResponse.messages.enumerated() {
                print("   Message \(index + 1): \(msg.type) - \(msg.id)")
            }
        }
        // This will be handled by registered handlers
    }
    
    private func handleClaudeResponse(_ message: WebSocketMessage) {
        if case .claudeResponse(let claudeResponse) = message.data {
            print("📨 Claude response received")
            print("   Request ID: \(message.requestId ?? "none")")
            print("   Session ID: \(claudeResponse.sessionId ?? "none")")
            print("   Success: \(claudeResponse.success)")
            print("   Content length: \(claudeResponse.content.count) chars")
            
            // Check if this response has a requestId for routing
            if let requestId = message.requestId {
                print("   Response matched to request: \(requestId)")
                
                // The requestId allows the response to be routed to the correct chat view
                // even when multiple chats are active simultaneously without session IDs
            } else {
                print("   ⚠️ No requestId - response may route incorrectly")
            }
            
            // Log the actual session ID from Claude if present
            if let sessionId = claudeResponse.sessionId, !sessionId.isEmpty {
                print("   Claude assigned session ID: \(sessionId)")
            }
        }
        // This will be handled by registered handlers in the UI
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        // Ensure we're on main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if this is a background connection event
            if client === self.backgroundWebSocket {
                self.handleBackgroundWebSocketEvent(event)
                return
            }
            
            // Handle regular connection events
            switch event {
            case .connected(let headers):
                print("WebSocket connected: \(headers)")

            case .disconnected(let reason, let code):
                print("WebSocket disconnected: \(reason) with code: \(code)")
                self.updateConnectionState(.disconnected)
                self.reliabilityManager.recordDisconnection()

                // Attempt reconnection if not manually disconnected
                if code != CloseCode.normal.rawValue && self.currentURL != nil {
                    self.attemptReconnect()
                }

            case .text(let string):
                print("📨 WebSocket: Received text message: \(string.prefix(200))...")
                self.handleReceivedMessage(string)

            case .binary(let data):
                print("Received binary data: \(data.count) bytes")

            case .ping:
                // Starscream handles pong automatically
                break

            case .pong:
                // Pong received
                break

            case .viabilityChanged(let isViable):
                if !isViable {
                    self.updateConnectionState(.error("Connection not viable"))
                }

            case .reconnectSuggested(let shouldReconnect):
                if shouldReconnect && self.currentURL != nil {
                    self.attemptReconnect()
                }

            case .cancelled:
                self.updateConnectionState(.disconnected)

            case .error(let error):
                print("WebSocket error: \(String(describing: error))")
                
                // Handle network-specific errors more gracefully
                if let nsError = error as? NSError {
                    if nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorNotConnectedToInternet:
                            self.updateConnectionState(.error("No internet connection"))
                        case NSURLErrorNetworkConnectionLost:
                            self.updateConnectionState(.error("Network connection lost"))
                        default:
                            self.updateConnectionState(.error(error?.localizedDescription ?? "Unknown WebSocket error"))
                        }
                    } else {
                        self.updateConnectionState(.error(error?.localizedDescription ?? "Unknown WebSocket error"))
                    }
                } else {
                    self.updateConnectionState(.error(error?.localizedDescription ?? "Unknown WebSocket error"))
                }

                if self.currentURL != nil {
                    self.attemptReconnect()
                }
                
            case .peerClosed:
                print("WebSocket peer closed connection")
                self.updateConnectionState(.disconnected)
            }
        }
    }
    
    // MARK: - Background Connection Support
    
    /// Establish a temporary connection for background message sync
    func establishBackgroundConnection(to url: URL) async -> Bool {
        print("🔄 Establishing background WebSocket connection")
        
        return await withCheckedContinuation { continuation in
            self.backgroundConnectionCompletion = continuation
            
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            urlComponents.scheme = url.scheme == "https" ? "wss" : "ws"
            urlComponents.path = "/ws"
            
            if let token = authToken {
                urlComponents.queryItems = [URLQueryItem(name: "token", value: token)]
            }
            
            guard let wsURL = urlComponents.url else {
                print("❌ Invalid background WebSocket URL")
                continuation.resume(returning: false)
                return
            }
            
            var request = URLRequest(url: wsURL)
            request.timeoutInterval = 10 // Shorter timeout for background
            
            backgroundWebSocket = WebSocket(request: request)
            backgroundWebSocket?.delegate = self
            backgroundWebSocket?.connect()
            
            // Set timeout for connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.backgroundConnectionCompletion != nil {
                    print("⏰ Background connection timeout")
                    self.backgroundConnectionCompletion?.resume(returning: false)
                    self.backgroundConnectionCompletion = nil
                    self.backgroundWebSocket?.disconnect()
                    self.backgroundWebSocket = nil
                }
            }
        }
    }
    
    /// Close the background connection
    func closeBackgroundConnection() async {
        print("🔄 Closing background WebSocket connection")
        
        backgroundWebSocket?.disconnect()
        backgroundWebSocket = nil
        backgroundConnectionCompletion = nil
        backgroundMessageCompletion = nil
        backgroundMessages.removeAll()
    }
    
    /// Fetch queued messages for a specific session via background connection
    func fetchQueuedMessages(for sessionId: String) async -> [Message] {
        print("🔄 Fetching queued messages for session: \(sessionId)")
        
        guard backgroundWebSocket != nil else {
            print("❌ No background connection available")
            return []
        }
        
        return await withCheckedContinuation { continuation in
            self.backgroundMessageCompletion = continuation
            self.backgroundMessages.removeAll()
            
            // Send message history request
            let request = GetMessageHistoryRequest(
                sessionId: sessionId,
                limit: 50, // Fetch last 50 messages
                offset: 0
            )
            
            do {
                let data = try encoder.encode(request)
                let dataDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                
                let message = [
                    "type": WebSocketMessageType.getMessageHistory.rawValue,
                    "requestId": UUID().uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "data": dataDict
                ] as [String: Any]
                
                let messageData = try JSONSerialization.data(withJSONObject: message)
                let messageString = String(data: messageData, encoding: .utf8)!
                
                print("📨 Sending background message history request")
                backgroundWebSocket?.write(string: messageString)
                
                // Set timeout for message fetch
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    if self.backgroundMessageCompletion != nil {
                        print("⏰ Background message fetch timeout")
                        self.backgroundMessageCompletion?.resume(returning: [])
                        self.backgroundMessageCompletion = nil
                    }
                }
            } catch {
                print("❌ Failed to send background message history request: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    private func handleBackgroundWebSocketEvent(_ event: Starscream.WebSocketEvent) {
        switch event {
        case .connected:
            print("✅ Background WebSocket connected")
            backgroundConnectionCompletion?.resume(returning: true)
            backgroundConnectionCompletion = nil
            
        case .disconnected(let reason, let code):
            print("❌ Background WebSocket disconnected: \(reason) code: \(code)")
            if let completion = backgroundConnectionCompletion {
                completion.resume(returning: false)
                backgroundConnectionCompletion = nil
            }
            
        case .text(let string):
            handleBackgroundMessage(string)
            
        case .error(let error):
            print("❌ Background WebSocket error: \(String(describing: error))")
            backgroundConnectionCompletion?.resume(returning: false)
            backgroundConnectionCompletion = nil
            
        default:
            break
        }
    }
    
    private func handleBackgroundMessage(_ messageString: String) {
        guard let data = messageString.data(using: .utf8) else { return }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let typeString = json?["type"] as? String,
                  let type = WebSocketMessageType(rawValue: typeString) else {
                return
            }
            
            let message = try decoder.decode(WebSocketMessage.self, from: data)
            
            // Handle message history response in background
            if type == .getMessageHistory {
                if case .getMessageHistoryResponse(let historyResponse) = message.data {
                    print("📜 Received background message history: \(historyResponse.messages.count) messages")
                    
                    // Convert WebSocket messages to app Messages
                    let appMessages = convertWebSocketMessagesToAppMessages(historyResponse.messages)
                    backgroundMessages.append(contentsOf: appMessages)
                    
                    // Complete the fetch
                    backgroundMessageCompletion?.resume(returning: backgroundMessages)
                    backgroundMessageCompletion = nil
                }
            }
        } catch {
            print("❌ Failed to parse background message: \(error)")
        }
    }
    
    private func convertWebSocketMessagesToAppMessages(_ wsMessages: [HistoryMessage]) -> [Message] {
        return wsMessages.compactMap { wsMessage in
            // Convert WebSocket HistoryMessage to app Message
            // Extract text content from MessageContent array
            
            let content: String
            if let messageContents = wsMessage.content, !messageContents.isEmpty {
                // Combine all text content from the content array
                content = messageContents.compactMap { $0.text }.joined(separator: "\n")
            } else {
                content = "" // Empty content
            }
            
            let messageType: MessageType
            let messageSender: MessageSender
            
            switch wsMessage.type {
            case "user":
                messageType = .text // User messages are typically text
                messageSender = .user
            case "assistant":
                messageType = .markdown // Assistant messages are typically markdown
                messageSender = .assistant
            case "system":
                messageType = .system
                messageSender = .system
            default:
                messageType = .text // Default to text type
                messageSender = .assistant // Default to assistant
            }
            
            return Message(
                id: UUID(uuidString: wsMessage.id) ?? UUID(),
                content: content,
                sender: messageSender,
                timestamp: ISO8601DateFormatter().date(from: wsMessage.timestamp ?? "") ?? Date(),
                type: messageType,
                metadata: AICLIMessageMetadata(
                    sessionId: "", // Will be set by the sync service
                    duration: 0,
                    additionalInfo: [
                        "backgroundSynced": true,
                        "syncedAt": Date()
                    ]
                )
            )
        }
    }
}

// MARK: - Supporting Types

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
