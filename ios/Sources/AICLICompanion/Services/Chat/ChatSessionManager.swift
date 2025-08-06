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
            return
        }
        
        // NEW ARCHITECTURE: Check for existing persisted sessions
        // If we have a session with messages, restore it
        // If not, wait for user to start conversation
        print("🔷 SessionManager: No session from parent, checking for existing session")
        
        // Check if we have session metadata with messages
        if let metadata = persistenceService.getSessionMetadata(for: project.path),
           let sessionId = metadata.aicliSessionId,
           metadata.messageCount > 0 {
            
            print("🔷 SessionManager: Found existing session with messages: \(sessionId) (\(metadata.messageCount) messages)")
            
            // Create session using the ACTUAL Claude session ID from message persistence
            let dateFormatter = ISO8601DateFormatter()
            let restoredSession = ProjectSession(
                sessionId: sessionId, // Use the actual session ID where messages are stored
                projectName: project.name,
                projectPath: project.path,
                status: "ready",
                startedAt: dateFormatter.string(from: metadata.createdAt)
            )
            
            setActiveSession(restoredSession)
            webSocketService.subscribeToSessions([sessionId])
            
            // Update session state persistence with the correct session ID
            sessionStatePersistence.saveSessionState(
                sessionId: sessionId,
                projectId: project.path,
                projectName: project.name,
                projectPath: project.path,
                messageCount: metadata.messageCount,
                aicliSessionId: sessionId
            )
            
            completion(.success(restoredSession))
        } else {
            // No existing session or session has no messages - wait for user to start
            print("🔷 SessionManager: No session with messages found - waiting for user to start conversation")
            completion(.failure(SessionError.noExistingSession))
        }
    }
    
    // MARK: - Session Creation After Claude Response
    func createSessionFromClaudeResponse(
        sessionId: String,
        for project: Project,
        completion: @escaping (Result<ProjectSession, Error>) -> Void
    ) {
        print("🔷 SessionManager: Creating session from Claude response: \(sessionId)")
        
        let dateFormatter = ISO8601DateFormatter()
        let newSession = ProjectSession(
            sessionId: sessionId,
            projectName: project.name,
            projectPath: project.path,
            status: "ready",
            startedAt: dateFormatter.string(from: Date())
        )
        
        setActiveSession(newSession)
        webSocketService.subscribeToSessions([sessionId])
        
        // Save session state for future restoration
        sessionStatePersistence.saveSessionState(
            sessionId: sessionId,
            projectId: project.path,
            projectName: project.name,
            projectPath: project.path,
            messageCount: 1, // At least one message to create this session
            aicliSessionId: sessionId
        )
        
        completion(.success(newSession))
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
        // Session status handling removed - not needed in simplified architecture
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
