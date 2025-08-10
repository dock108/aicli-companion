import Foundation
import Combine
@testable import AICLICompanion

/// Mock implementation of HTTPAICLIService for testing
@available(iOS 16.0, macOS 13.0, *)
class MockHTTPAICLIService: ObservableObject {
    
    // MARK: - Published Properties (mirroring real service)
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var currentSession: String?
    
    // MARK: - Mock Control Properties
    var shouldFailConnection = false
    var shouldFailChatRequest = false
    var mockResponse: AICLIResponse?
    var mockError: AICLICompanionError?
    var connectionDelay: TimeInterval = 0.1
    var responseDelay: TimeInterval = 0.5
    var lastConnectedAddress: String?
    var lastConnectedPort: Int?
    var lastAuthToken: String?
    var recordedChatRequests: [String] = []
    
    // MARK: - Connection Management
    
    func connect(
        to address: String,
        port: Int,
        authToken: String?,
        completion: @escaping (Result<Void, AICLICompanionError>) -> Void
    ) {
        lastConnectedAddress = address
        lastConnectedPort = port
        lastAuthToken = authToken
        
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionDelay) {
            if self.shouldFailConnection {
                self.isConnected = false
                self.connectionStatus = .error(self.mockError ?? .connectionFailed("Mock connection failure"))
                completion(.failure(self.mockError ?? .connectionFailed("Mock connection failure")))
            } else {
                self.isConnected = true
                self.connectionStatus = .connected
                completion(.success(()))
            }
        }
    }
    
    func disconnect() {
        isConnected = false
        connectionStatus = .disconnected
        currentSession = nil
    }
    
    func testConnection(completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.shouldFailConnection {
                completion(.failure(self.mockError ?? .connectionFailed("Mock test connection failure")))
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Chat Functionality
    
    func sendChatMessage(
        _ prompt: String,
        projectPath: String,
        sessionId: String?,
        completion: @escaping (Result<AICLIResponse, AICLICompanionError>) -> Void
    ) {
        recordedChatRequests.append(prompt)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) {
            if self.shouldFailChatRequest {
                completion(.failure(self.mockError ?? .networkError(URLError(.notConnectedToInternet))))
            } else {
                let response = self.mockResponse ?? TestDataFactory.createAICLIResponse(
                    result: "Mock response to: \(prompt)",
                    sessionId: sessionId ?? UUID().uuidString
                )
                self.currentSession = response.sessionId
                completion(.success(response))
            }
        }
    }
    
    // MARK: - Device Registration
    
    func registerDeviceForPushNotifications(
        deviceToken: String,
        completion: @escaping (Result<Void, AICLICompanionError>) -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion(.success(()))
        }
    }
    
    // MARK: - Mock Helpers
    
    func reset() {
        isConnected = false
        connectionStatus = .disconnected
        currentSession = nil
        shouldFailConnection = false
        shouldFailChatRequest = false
        mockResponse = nil
        mockError = nil
        connectionDelay = 0.1
        responseDelay = 0.5
        lastConnectedAddress = nil
        lastConnectedPort = nil
        lastAuthToken = nil
        recordedChatRequests.removeAll()
    }
    
    func simulateConnectionLoss() {
        isConnected = false
        connectionStatus = .error(.connectionFailed("Connection lost"))
    }
    
    func simulateAuthenticationFailure() {
        shouldFailConnection = true
        mockError = .authenticationFailed
    }
    
    func setMockResponse(_ response: AICLIResponse) {
        mockResponse = response
    }
    
    func setMockError(_ error: AICLICompanionError) {
        mockError = error
        shouldFailChatRequest = true
    }
    
    func simulateConnectionError(_ error: AICLICompanionError) {
        shouldFailConnection = true
        mockError = error
    }
}

// MARK: - ConnectionStatus Mock Support

extension ConnectionStatus: Equatable {
    public static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
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