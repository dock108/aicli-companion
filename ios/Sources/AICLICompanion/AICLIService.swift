import Foundation
import Combine
import UserNotifications
#if os(iOS)
import UIKit
#endif

// MARK: - Main AICLI Service
// Uses composition pattern with specialized service components

@available(iOS 16.0, macOS 13.0, *)
public class AICLIService: ObservableObject {
    public static let shared = AICLIService()
    
    // MARK: - Published Properties (forwarded from components)
    @Published public var isConnected = false
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    @Published public var currentSession: String?

    // MARK: - Composed Services
    private let connectionManager: AICLIConnectionManager
    private let pushNotificationManager: AICLIPushNotificationManager
    private let messageOperations: AICLIMessageOperations
    private let sessionManager: AICLISessionManager
    private let projectManager: AICLIProjectManager
    
    private let urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()

    public init() {
        // Setup URL session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120 // Longer timeout for Claude processing
        config.waitsForConnectivity = true // Wait for network connectivity
        config.allowsCellularAccess = true
        config.sessionSendsLaunchEvents = true
        self.urlSession = URLSession(configuration: config)
        
        // Initialize composed services
        self.connectionManager = AICLIConnectionManager(urlSession: urlSession)
        self.pushNotificationManager = AICLIPushNotificationManager(urlSession: urlSession, connectionManager: connectionManager)
        self.messageOperations = AICLIMessageOperations(urlSession: urlSession, connectionManager: connectionManager)
        self.sessionManager = AICLISessionManager(urlSession: urlSession, connectionManager: connectionManager)
        self.projectManager = AICLIProjectManager(urlSession: urlSession, connectionManager: connectionManager)
        
        // Setup property forwarding
        setupPropertyForwarding()
    }

    deinit {
        // Cancel any pending tasks
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        cancellables.removeAll()
    }
    
    // MARK: - Property Forwarding Setup
    
    private func setupPropertyForwarding() {
        // Forward connection state
        connectionManager.$isConnected
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
            
        connectionManager.$connectionStatus
            .assign(to: \.connectionStatus, on: self)
            .store(in: &cancellables)
            
        // Forward session state
        sessionManager.$currentSession
            .assign(to: \.currentSession, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Connection Management (delegated)
    
    public func connect(to address: String, port: Int, authToken: String?, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        connectionManager.connect(to: address, port: port, authToken: authToken, completion: completion)
    }
    
    public func disconnect() {
        connectionManager.disconnect()
        sessionManager.clearCurrentSession()
    }

    // MARK: - Push Notifications (delegated)
    
    public func setDeviceToken(_ token: String) {
        pushNotificationManager.setDeviceToken(token)
    }

    // MARK: - Message Operations (delegated)
    
    public func sendMessage(
        _ text: String,
        projectPath: String? = nil,
        attachments: [AttachmentData]? = nil,
        completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void
    ) {
        messageOperations.sendMessage(text, projectPath: projectPath, attachments: attachments, completion: completion)
    }
    
    public func fetchMessage(messageId: String) async throws -> Message {
        return try await messageOperations.fetchMessage(messageId: messageId)
    }
    
    public func fetchMessages(sessionId: String, completion: @escaping (Result<[Message], AICLICompanionError>) -> Void) {
        messageOperations.fetchMessages(sessionId: sessionId, completion: completion)
    }

    // MARK: - Session Management (delegated)
    
    public func checkSessionStatus(sessionId: String, completion: @escaping (Result<Bool, AICLICompanionError>) -> Void) {
        sessionManager.checkSessionStatus(sessionId: sessionId, completion: completion)
    }
    
    public func checkSessionStatus(sessionId: String) async throws -> SessionStatus {
        return try await sessionManager.checkSessionStatus(sessionId: sessionId)
    }
    
    public func setCurrentSession(_ sessionId: String?) {
        sessionManager.setCurrentSession(sessionId)
    }

    // MARK: - Project Management (delegated)
    
    public func getProjects(completion: @escaping (Result<[Project], AICLICompanionError>) -> Void) {
        projectManager.getProjects(completion: completion)
    }
    
    public func validateProjectPath(_ path: String, completion: @escaping (Result<Bool, AICLICompanionError>) -> Void) {
        projectManager.validateProjectPath(path, completion: completion)
    }
    
    public func createFolder(in projectName: String, folderName: String, completion: @escaping (Result<FolderCreationResponse, AICLICompanionError>) -> Void) {
        projectManager.createFolder(in: projectName, folderName: folderName, completion: completion)
    }
    
    // MARK: - Service State
    
    public var hasValidConnection: Bool {
        return connectionManager.hasValidConnection
    }
    
    public var hasActiveSession: Bool {
        return sessionManager.hasActiveSession
    }
    
    public var isRegisteredForPushNotifications: Bool {
        return pushNotificationManager.isRegisteredForPushNotifications
    }
    
    // MARK: - Session Management
    
    public func clearSessionId(for projectPath: String) {
        messageOperations.clearSessionId(for: projectPath)
    }
    
    public func getSessionId(for projectPath: String) -> String? {
        return sessionManager.getSessionId(for: projectPath)
    }
    
    // MARK: - Kill Session
    
    public func killSession(_ sessionId: String, projectPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        messageOperations.killSession(sessionId, projectPath: projectPath, completion: completion)
    }
}
