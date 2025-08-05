import Foundation
import Combine

@available(iOS 16.0, macOS 13.0, *)
class ChatSessionManager: ObservableObject {
    static let shared = ChatSessionManager()
    
    // MARK: - Published Properties
    @Published var activeSession: ProjectSession?
    @Published var isRestoring = false
    @Published var sessionError: String?
    
    // MARK: - Services
    private let webSocketService = WebSocketService.shared
    private let persistenceService = MessagePersistenceService.shared
    private let sessionStatePersistence = SessionStatePersistenceService.shared
    private let aicliService = AICLIService()
    private let sessionDeduplicationManager = SessionDeduplicationManager.shared
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupWebSocketHandlers()
    }
    
    // MARK: - Session Lifecycle
    func handleSessionAfterConnection(
        for project: Project,
        passedSession: ProjectSession?,
        completion: @escaping (Result<ProjectSession, Error>) -> Void
    ) {
        // If we already have a session from parent, use it
        if let passedSession = passedSession {
            print("🔷 SessionManager: Using session from parent: \(passedSession.sessionId)")
            setActiveSession(passedSession)
            
            // Subscribe to the session
            webSocketService.subscribeToSessions([passedSession.sessionId])
            
            completion(.success(passedSession))
        } else {
            // Try to restore existing session
            restoreSession(for: project, completion: completion)
        }
    }
    
    func createSession(
        for project: Project,
        connection: ServerConnection,
        completion: @escaping (Result<ProjectSession, Error>) -> Void
    ) {
        Task {
            do {
                // Get or reuse existing session ID for this project
                let sessionId = try await sessionDeduplicationManager.getOrCreateSession(
                    for: project.path,
                    verifySession: { sessionId in
                        // Verify with server if session is valid
                        // For now, we'll assume it's valid if we have metadata
                        return self.persistenceService.getSessionMetadata(for: project.path)?.aicliSessionId == sessionId
                    }
                )
                
                // Start the project session with the deduplicated session ID
                aicliService.startProjectSession(
                    project: project,
                    connection: connection,
                    sessionId: sessionId
                ) { result in
                    switch result {
                    case .success(let session):
                        self.setActiveSession(session)
                        self.webSocketService.subscribeToSessions([session.sessionId])
                        
                        // Update deduplication tracking
                        self.sessionDeduplicationManager.touchSession(for: project.path)
                        
                        // Save session state
                        self.sessionStatePersistence.saveSessionState(
                            sessionId: session.sessionId,
                            projectId: project.path,
                            projectName: project.name,
                            projectPath: project.path,
                            messageCount: 0,
                            aicliSessionId: session.sessionId
                        )
                        
                        completion(.success(session))
                        
                    case .failure(let error):
                        self.sessionError = error.localizedDescription
                        completion(.failure(error))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func restoreSession(
        for project: Project,
        completion: @escaping (Result<ProjectSession, Error>) -> Void
    ) {
        isRestoring = true
        
        // First check enhanced session state persistence
        if let sessionState = sessionStatePersistence.getSessionState(for: project.path) {
            print("🔷 SessionManager: Found session state for '\(project.name)': \(sessionState.id)")
            
            // Check if session is still active
            if !sessionState.isExpired {
                let dateFormatter = ISO8601DateFormatter()
                let restoredSession = ProjectSession(
                    sessionId: sessionState.id,
                    projectName: sessionState.projectName,
                    projectPath: sessionState.projectPath,
                    status: "ready",
                    startedAt: dateFormatter.string(from: sessionState.createdAt)
                )
                
                setActiveSession(restoredSession)
                webSocketService.subscribeToSessions([sessionState.id])
                
                // Touch the session to update last active time
                sessionStatePersistence.touchSession(sessionState.id)
                
                // Request message history from server
                requestMessageHistory(for: sessionState.id)
                
                isRestoring = false
                completion(.success(restoredSession))
                return
            }
        }
        
        // Fallback to legacy session metadata
        guard let metadata = persistenceService.getSessionMetadata(for: project.path) else {
            print("🔷 SessionManager: No existing session found for '\(project.name)'")
            isRestoring = false
            completion(.failure(SessionError.noExistingSession))
            return
        }
        
        guard let sessionId = metadata.aicliSessionId else {
            print("⚠️ SessionManager: Session metadata exists but no AICLI session ID")
            isRestoring = false
            completion(.failure(SessionError.invalidSessionMetadata))
            return
        }
        
        print("🔷 SessionManager: Found existing session for '\(project.name)': \(sessionId)")
        
        // Create session object from metadata
        let dateFormatter = ISO8601DateFormatter()
        let restoredSession = ProjectSession(
            sessionId: sessionId,
            projectName: project.name,
            projectPath: project.path,
            status: "ready",
            startedAt: dateFormatter.string(from: metadata.createdAt)
        )
        
        setActiveSession(restoredSession)
        webSocketService.subscribeToSessions([sessionId])
        
        // Request message history from server
        requestMessageHistory(for: sessionId)
        
        // Migrate to new session state persistence
        sessionStatePersistence.saveSessionState(
            sessionId: sessionId,
            projectId: project.path,
            projectName: project.name,
            projectPath: project.path,
            messageCount: metadata.messageCount,
            aicliSessionId: sessionId
        )
        
        isRestoring = false
        completion(.success(restoredSession))
    }
    
    func closeSession() {
        guard let session = activeSession else { return }
        
        print("🔷 SessionManager: Closing session \(session.sessionId)")
        webSocketService.closeStream(sessionId: session.sessionId)
        webSocketService.setActiveSession(nil)
        activeSession = nil
    }
    
    // MARK: - Private Methods
    private func setActiveSession(_ session: ProjectSession) {
        activeSession = session
        webSocketService.setActiveSession(session.sessionId)
        webSocketService.trackSession(session.sessionId)
        sessionError = nil
        
        // Touch session state to update last active time
        sessionStatePersistence.touchSession(session.sessionId)
    }
    
    private func setupWebSocketHandlers() {
        // Handle session status updates
        webSocketService.setMessageHandler(for: .sessionStatus) { [weak self] message in
            guard let self = self else { return }
            
            if case .sessionStatus(let status) = message.data {
                Task { @MainActor in
                    self.handleSessionStatus(status)
                }
            }
        }
    }
    
    private func handleSessionStatus(_ status: SessionStatusResponse) {
        // Update active session status if needed
        if let activeSession = activeSession,
           activeSession.sessionId == status.sessionId {
            // Update session status
            print("📊 Session status update: \(status.status)")
        }
    }
    
    private func requestMessageHistory(for sessionId: String) {
        print("🔷 SessionManager: Requesting message history for session \(sessionId)")
        
        // Create the request
        let request = GetMessageHistoryRequest(
            sessionId: sessionId,
            limit: nil,  // Get all messages
            offset: nil
        )
        
        // Send via WebSocket
        webSocketService.sendMessage(request, type: .getMessageHistory) { result in
            switch result {
            case .success:
                print("✅ Message history request sent for session \(sessionId)")
            case .failure(let error):
                print("❌ Failed to request message history: \(error)")
            }
        }
    }
    
    // MARK: - Error Types
    enum SessionError: LocalizedError {
        case noExistingSession
        case invalidSessionMetadata
        case connectionRequired
        
        var errorDescription: String? {
            switch self {
            case .noExistingSession:
                return "No existing session found"
            case .invalidSessionMetadata:
                return "Invalid session metadata"
            case .connectionRequired:
                return "WebSocket connection required"
            }
        }
    }
}