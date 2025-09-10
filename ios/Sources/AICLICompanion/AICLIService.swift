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

    // MARK: - Composed Services (Lazy for performance)
    private lazy var connectionManager: AICLIConnectionManager = {
        AICLIConnectionManager(urlSession: urlSession)
    }()
    
    // Public accessor for FileContentService
    public var activeConnectionManager: AICLIConnectionManager {
        return connectionManager
    }
    
    private lazy var pushNotificationManager: AICLIPushNotificationManager = {
        AICLIPushNotificationManager(urlSession: urlSession, connectionManager: connectionManager)
    }()
    
    private lazy var messageOperations: AICLIMessageOperations = {
        AICLIMessageOperations(urlSession: urlSession, connectionManager: connectionManager)
    }()
    
    private lazy var sessionManager: AICLISessionManager = {
        AICLISessionManager(urlSession: urlSession, connectionManager: connectionManager)
    }()
    
    private lazy var projectManager: AICLIProjectManager = {
        AICLIProjectManager(urlSession: urlSession, connectionManager: connectionManager)
    }()
    
    private let urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()
    private var isPropertyForwardingSetup = false

    public init() {
        // Minimal init - just store a basic URL session
        // Even URLSession configuration is deferred to avoid any overhead
        self.urlSession = URLSession.shared
        
        // Everything else is lazy - created only when needed
        // This ensures the absolute fastest possible init
    }

    deinit {
        // Cancel any pending tasks
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        cancellables.removeAll()
    }
    
    // MARK: - Property Forwarding Setup
    
    private func setupPropertyForwardingIfNeeded() {
        guard !isPropertyForwardingSetup else { return }
        isPropertyForwardingSetup = true
        
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
        setupPropertyForwardingIfNeeded()
        connectionManager.connect(to: address, port: port, authToken: authToken) { [weak self] result in
            // Update FileContentService with connection manager when connection succeeds
            if case .success = result {
                DispatchQueue.main.async {
                    FileContentService.shared.updateConnection(self?.connectionManager ?? AICLIConnectionManager(urlSession: URLSession.shared))
                }
            }
            completion(result)
        }
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
        mode: ChatMode = .normal,
        completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void
    ) {
        messageOperations.sendMessage(text, projectPath: projectPath, attachments: attachments, mode: mode, completion: completion)
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
    
    public func storeSessionId(_ sessionId: String, for projectPath: String) {
        messageOperations.storeSessionId(sessionId, for: projectPath)
    }
    
    public func getSessionId(for projectPath: String) -> String? {
        return sessionManager.getSessionId(for: projectPath)
    }
    
    // MARK: - Large Message Fetching
    
    public func fetchLargeMessage(messageId: String) async throws -> (content: String, metadata: [String: Any]?) {
        // Use messageOperations to fetch large message from server
        return try await messageOperations.fetchLargeMessage(messageId: messageId)
    }
    
    // MARK: - Kill Session
    
    public func killSession(_ sessionId: String, projectPath: String, sendNotification: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
        messageOperations.killSession(sessionId, projectPath: projectPath, sendNotification: sendNotification, completion: completion)
    }
    
    // MARK: - Planning Validation
    
    public func validatePlanningDocument(
        content: String,
        projectType: String? = nil,
        projectPath: String? = nil,
        completion: @escaping (Result<PlanningValidationResponse, AICLICompanionError>) -> Void
    ) {
        messageOperations.validatePlanningDocument(content: content, projectType: projectType, projectPath: projectPath, completion: completion)
    }
    
    public func analyzeDirectory(
        path: String,
        completion: @escaping (Result<DirectoryAnalysisResponse, AICLICompanionError>) -> Void
    ) {
        messageOperations.analyzeDirectory(path: path, completion: completion)
    }
    
    public func saveAndValidatePlan(
        projectPath: String,
        content: String,
        completion: @escaping (Result<PlanSaveResponse, AICLICompanionError>) -> Void
    ) {
        messageOperations.saveAndValidatePlan(projectPath: projectPath, content: content, completion: completion)
    }
}
