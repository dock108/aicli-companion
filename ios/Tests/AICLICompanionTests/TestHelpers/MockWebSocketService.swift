import Foundation
import Combine
@testable import AICLICompanion

/// Mock implementation of WebSocketService for testing
@available(iOS 16.0, macOS 13.0, *)
class MockWebSocketService: ObservableObject {
    
    // MARK: - Published Properties (mirroring real service)
    @Published var connectionState: WebSocketConnectionState = .disconnected
    @Published var lastError: AICLICompanionError?
    @Published var isConnected: Bool = false
    
    // MARK: - Publishers (mirroring real service)
    private let messageSubject = PassthroughSubject<WebSocketMessage, Never>()
    var messagePublisher: AnyPublisher<WebSocketMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Mock Control Properties
    var shouldFailConnection = false
    var shouldFailMessageSending = false
    var connectionDelay: TimeInterval = 0.1
    var messageDelay: TimeInterval = 0.1
    var mockError: AICLICompanionError?
    var recordedMessages: [WebSocketMessage] = []
    var recordedConnectionAttempts: [(url: URL, authToken: String?)] = []
    var autoRespondToMessages = true
    var mockResponses: [WebSocketMessage] = []
    private var responseIndex = 0
    
    // MARK: - Connection Management
    
    func connect(to url: URL, authToken: String?) {
        recordedConnectionAttempts.append((url, authToken))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionDelay) {
            if self.shouldFailConnection {
                let error = self.mockError ?? .connectionFailed("Mock connection failure")
                self.connectionState = .error(error)
                self.lastError = error
                self.isConnected = false
            } else {
                self.connectionState = .connected
                self.isConnected = true
                self.lastError = nil
                
                // Send mock welcome message
                self.sendMockWelcomeMessage()
            }
        }
    }
    
    func disconnect() {
        connectionState = .disconnected
        isConnected = false
        lastError = nil
    }
    
    func reconnect() {
        if let lastAttempt = recordedConnectionAttempts.last {
            connect(to: lastAttempt.url, authToken: lastAttempt.authToken)
        }
    }
    
    // MARK: - Message Sending
    
    func sendMessage(_ message: WebSocketMessage) {
        recordedMessages.append(message)
        
        if shouldFailMessageSending {
            let error = mockError ?? .webSocketError("Mock send failure")
            lastError = error
            return
        }
        
        if autoRespondToMessages {
            DispatchQueue.main.asyncAfter(deadline: .now() + messageDelay) {
                self.sendMockResponse(to: message)
            }
        }
    }
    
    // MARK: - Mock Message Generation
    
    private func sendMockWelcomeMessage() {
        let welcomeResponse = WelcomeResponse(
            clientId: "mock-client-123",
            serverVersion: "1.0.0",
            claudeCodeVersion: "0.9.0",
            capabilities: ["chat", "stream", "tools"],
            maxSessions: 10
        )
        
        let welcomeMessage = WebSocketMessage(
            type: .welcome,
            requestId: nil,
            timestamp: Date(),
            data: .welcome(welcomeResponse)
        )
        
        messageSubject.send(welcomeMessage)
    }
    
    private func sendMockResponse(to message: WebSocketMessage) {
        let response: WebSocketMessage
        
        if !mockResponses.isEmpty && responseIndex < mockResponses.count {
            response = mockResponses[responseIndex]
            responseIndex += 1
        } else {
            response = createDefaultMockResponse(to: message)
        }
        
        messageSubject.send(response)
    }
    
    private func createDefaultMockResponse(to message: WebSocketMessage) -> WebSocketMessage {
        switch message.data {
        case .ask(let request):
            let response = AskResponseData(
                success: true,
                response: TestDataFactory.createAICLIResponse(result: "Mock response to: \(request.prompt)"),
                error: nil
            )
            return WebSocketMessage(
                type: .askResponse,
                requestId: message.requestId,
                timestamp: Date(),
                data: .askResponse(response)
            )
            
        case .streamStart(let request):
            let response = StreamStartedResponse(
                sessionId: "mock-session-123",
                sessionName: nil,
                workingDirectory: request.workingDirectory ?? "/mock/path"
            )
            return WebSocketMessage(
                type: .streamStarted,
                requestId: message.requestId,
                timestamp: Date(),
                data: .streamStarted(response)
            )
            
        case .streamSend(let request):
            let chunk = TestDataFactory.createStreamChunk(
                content: "Mock response to: \(request.prompt)",
                type: "content",
                isFinal: true,
                sessionId: request.sessionId
            )
            let response = StreamChunkResponse(sessionId: request.sessionId, chunk: chunk)
            return WebSocketMessage(
                type: .streamChunk,
                requestId: message.requestId,
                timestamp: Date(),
                data: .streamChunk(response)
            )
            
        case .ping:
            let response = PongResponse(serverTime: Date())
            return WebSocketMessage(
                type: .pong,
                requestId: message.requestId,
                timestamp: Date(),
                data: .pong(response)
            )
            
        default:
            // Generic success response
            let response = ErrorResponse(
                code: "mock_response",
                message: "Mock response generated",
                details: nil
            )
            return WebSocketMessage(
                type: .error,
                requestId: message.requestId,
                timestamp: Date(),
                data: .error(response)
            )
        }
    }
    
    // MARK: - Mock Helpers
    
    func reset() {
        connectionState = .disconnected
        isConnected = false
        lastError = nil
        shouldFailConnection = false
        shouldFailMessageSending = false
        connectionDelay = 0.1
        messageDelay = 0.1
        mockError = nil
        recordedMessages.removeAll()
        recordedConnectionAttempts.removeAll()
        autoRespondToMessages = true
        mockResponses.removeAll()
        responseIndex = 0
    }
    
    func simulateConnectionError(_ error: AICLICompanionError) {
        shouldFailConnection = true
        mockError = error
    }
    
    func simulateMessageSendError(_ error: AICLICompanionError) {
        shouldFailMessageSending = true
        mockError = error
    }
    
    func setMockResponses(_ responses: [WebSocketMessage]) {
        mockResponses = responses
        responseIndex = 0
    }
    
    func addMockResponse(_ response: WebSocketMessage) {
        mockResponses.append(response)
    }
    
    func simulateIncomingMessage(_ message: WebSocketMessage) {
        messageSubject.send(message)
    }
    
    func simulateStreamChunk(content: String, sessionId: String, isFinal: Bool = false) {
        let chunk = TestDataFactory.createStreamChunk(
            content: content,
            type: "content",
            isFinal: isFinal,
            sessionId: sessionId
        )
        
        let response = StreamChunkResponse(sessionId: sessionId, chunk: chunk)
        let message = WebSocketMessage(
            type: .streamChunk,
            requestId: nil,
            timestamp: Date(),
            data: .streamChunk(response)
        )
        
        messageSubject.send(message)
    }
    
    func simulateConnectionLoss() {
        connectionState = .error(.connectionFailed("Connection lost"))
        isConnected = false
        lastError = .connectionFailed("Connection lost")
    }
    
    func getRecordedMessages() -> [WebSocketMessage] {
        return recordedMessages
    }
    
    func getRecordedConnectionAttempts() -> [(url: URL, authToken: String?)] {
        return recordedConnectionAttempts
    }
    
    func clearRecordedData() {
        recordedMessages.removeAll()
        recordedConnectionAttempts.removeAll()
    }
}

// MARK: - WebSocket Connection State Support

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(AICLICompanionError)
    
    static func == (lhs: WebSocketConnectionState, rhs: WebSocketConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}