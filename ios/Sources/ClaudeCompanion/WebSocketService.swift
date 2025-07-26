import Foundation
import Combine
import Starscream

@available(iOS 13.0, macOS 10.15, *)
class WebSocketService: ObservableObject, WebSocketDelegate {
    @Published var isConnected = false
    @Published var connectionState: WebSocketConnectionState = .disconnected

    private var webSocket: WebSocket?
    private var cancellables = Set<AnyCancellable>()
    private var pendingMessages: [WebSocketMessage] = []
    private var reconnectTimer: Timer?
    private var heartbeatTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let heartbeatInterval: TimeInterval = 30

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Message handlers
    private var messageHandlers: [WebSocketMessageType: (WebSocketMessage) -> Void] = [:]
    private var requestCallbacks: [String: (Result<WebSocketMessage, ClaudeCompanionError>) -> Void] = [:]

    // Connection info
    private var currentURL: URL?
    private var authToken: String?
    
    // Message callback
    var onMessage: ((WebSocketMessage) -> Void)?

    init() {
        setupDateFormatters()
    }

    deinit {
        disconnect()
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
        request.timeoutInterval = 10

        webSocket = WebSocket(request: request)
        webSocket?.delegate = self

        updateConnectionState(.connecting)
        webSocket?.connect()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        webSocket?.disconnect()
        webSocket = nil

        updateConnectionState(.disconnected)
        reconnectAttempts = 0
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let url = currentURL else {
            updateConnectionState(.error("Max reconnection attempts reached"))
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect(to: url, authToken: self?.authToken)
        }
    }

    private func updateConnectionState(_ state: WebSocketConnectionState) {
        DispatchQueue.main.async {
            self.connectionState = state
            self.isConnected = (state == .connected)
        }
    }

    // MARK: - Message Sending

    func sendMessage<T: Codable>(_ messageData: T, type: WebSocketMessageType, requestId: String? = nil, completion: ((Result<WebSocketMessage, ClaudeCompanionError>) -> Void)? = nil) {
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
                webSocket?.write(string: messageString)
            } else {
                // Queue message for when connection is restored
                if let wsMessage = try? decoder.decode(WebSocketMessage.self, from: messageData) {
                    pendingMessages.append(wsMessage)
                }
            }
        } catch {
            completion?(.failure(.jsonParsingError(error)))
        }
    }

    func sendAsk(prompt: String, workingDirectory: String? = nil, completion: @escaping (Result<ClaudeCodeResponse, ClaudeCompanionError>) -> Void) {
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
                    if responseData.success, let claudeResponse = responseData.response {
                        completion(.success(claudeResponse))
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

    func startStream(prompt: String, workingDirectory: String? = nil, sessionName: String? = nil, completion: @escaping (Result<String, ClaudeCompanionError>) -> Void) {
        let request = StreamStartRequest(
            prompt: prompt,
            workingDirectory: workingDirectory,
            options: StreamOptions(sessionName: sessionName, preserveContext: true)
        )

        sendMessage(request, type: .streamStart) { result in
            switch result {
            case .success(let message):
                if case .streamStarted(let response) = message.data {
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
    }

    func setWorkingDirectory(_ workingDirectory: String, completion: @escaping (Result<Bool, ClaudeCompanionError>) -> Void) {
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

    // MARK: - Message Handling

    func setMessageHandler(for type: WebSocketMessageType, handler: @escaping (WebSocketMessage) -> Void) {
        messageHandlers[type] = handler
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
            case .sessionStatus:
                handleSessionStatus(message)
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

            default:
                break
            }

            // Call global message callback
            onMessage?(message)
            
            // Call registered handler if available
            messageHandlers[type]?(message)
        } catch {
            print("Failed to parse WebSocket message: \(error)")
        }
    }

    private func handleWelcomeMessage(_ message: WebSocketMessage) {
        if case .welcome(let welcome) = message.data {
            print("Connected to server \(welcome.serverVersion), Claude Code \(welcome.claudeCodeVersion ?? "unknown")")
            updateConnectionState(.connected)
            reconnectAttempts = 0

            // Send any pending messages
            sendPendingMessages()

            // Start heartbeat
            startHeartbeat()
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

    private func handleSessionStatus(_ message: WebSocketMessage) {
        // This will be handled by registered handlers in the UI
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

    // MARK: - WebSocketDelegate

    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected(let headers):
            print("WebSocket connected: \(headers)")

        case .disconnected(let reason, let code):
            print("WebSocket disconnected: \(reason) with code: \(code)")
            updateConnectionState(.disconnected)

            // Attempt reconnection if not manually disconnected
            if code != CloseCode.normal.rawValue && currentURL != nil {
                attemptReconnect()
            }

        case .text(let string):
            handleReceivedMessage(string)

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
                updateConnectionState(.error("Connection not viable"))
            }

        case .reconnectSuggested(let shouldReconnect):
            if shouldReconnect && currentURL != nil {
                attemptReconnect()
            }

        case .cancelled:
            updateConnectionState(.disconnected)

        case .error(let error):
            print("WebSocket error: \(String(describing: error))")
            updateConnectionState(.error(error?.localizedDescription ?? "Unknown WebSocket error"))

            if currentURL != nil {
                attemptReconnect()
            }
            
        case .peerClosed:
            print("WebSocket peer closed connection")
            updateConnectionState(.disconnected)
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
