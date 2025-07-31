import SwiftUI
import Combine

@available(iOS 16.0, macOS 13.0, *)
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var progressInfo: ProgressInfo?
    @Published var sessionError: String?
    @Published var activeSession: ProjectSession?
    
    // MARK: - Services
    private let webSocketService = WebSocketService.shared
    private let persistenceService = MessagePersistenceService.shared
    private let aicliService: AICLIService
    private let settings: SettingsManager
    
    // MARK: - Private Properties
    private var messageTimeout: Timer?
    private var autoSaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let responseStreamer = ClaudeResponseStreamer()
    
    // MARK: - Initialization
    init(aicliService: AICLIService, settings: SettingsManager) {
        self.aicliService = aicliService
        self.settings = settings
        setupAutoSave()
    }
    
    deinit {
        messageTimeout?.invalidate()
        autoSaveTimer?.invalidate()
    }
    
    // MARK: - Message Management
    func sendMessage(_ text: String, for project: Project) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Add user message
        let userMessage = Message(
            content: text,
            sender: .user,
            type: .text
        )
        messages.append(userMessage)
        
        // Send command
        isLoading = true
        sendAICLICommand(text, for: project)
    }
    
    private func sendAICLICommand(_ command: String, for project: Project) {
        // Check if we have an active session
        guard let session = activeSession else {
            isLoading = false
            let errorMessage = Message(
                content: "❌ No active AICLI session. Please wait for the session to start or try reloading the chat.",
                sender: .assistant,
                type: .text
            )
            messages.append(errorMessage)
            return
        }
        
        // Ensure WebSocket is connected
        guard webSocketService.isConnected else {
            isLoading = false
            let errorMessage = Message(
                content: "❌ Not connected to server. Please check your connection.",
                sender: .assistant,
                type: .text
            )
            messages.append(errorMessage)
            return
        }
        
        // Create the command request
        let claudeRequest = AICLICommandRequest(
            command: command,
            projectPath: project.path,
            sessionId: session.sessionId
        )
        
        print("📤 Sending command to server: \(command)")
        print("   Session ID: \(session.sessionId)")
        print("   Project path: \(project.path)")
        
        // Set timeout
        messageTimeout?.invalidate()
        messageTimeout = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            Task { @MainActor in
                self.isLoading = false
                let timeoutMessage = Message(
                    content: "⏰ Request timed out. The connection may have been lost or the server is taking too long to respond. Please try again.",
                    sender: .assistant,
                    type: .text
                )
                self.messages.append(timeoutMessage)
            }
        }
        
        // Send via WebSocket
        webSocketService.sendMessage(claudeRequest, type: .aicliCommand) { result in
            switch result {
            case .success(let message):
                self.handleCommandResponse(message)
            case .failure(let error):
                self.handleCommandError(error)
            }
        }
    }
    
    // MARK: - Session Management
    func setActiveSession(_ session: ProjectSession?) {
        activeSession = session
        if let session = session {
            webSocketService.setActiveSession(session.sessionId)
            webSocketService.trackSession(session.sessionId)
        }
    }
    
    func startSession(for project: Project, connection: ServerConnection) {
        guard !isLoading else { return }
        
        isLoading = true
        sessionError = nil
        
        aicliService.startProjectSession(project: project, connection: connection) { result in
            Task { @MainActor in
                self.isLoading = false
                
                switch result {
                case .success(let session):
                    self.activeSession = session
                    self.sessionError = nil
                    
                    // Update WebSocket service
                    self.webSocketService.setActiveSession(session.sessionId)
                    self.webSocketService.trackSession(session.sessionId)
                    self.webSocketService.subscribeToSessions([session.sessionId])
                    
                    // Add success message
                    let successMessage = Message(
                        content: "✅ AICLI ready in **\(project.name)**\n\nYou can now interact with your project. I have access to all files in this directory and can help you with coding tasks, analysis, and more.\n\nType your first message to get started!",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(successMessage)
                    
                case .failure(let error):
                    self.sessionError = error.localizedDescription
                    
                    let errorMessage = Message(
                        content: "❌ Failed to start AICLI session: \(error.localizedDescription)",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }
    
    // MARK: - Message Persistence
    func saveMessages(for project: Project) {
        guard !messages.isEmpty,
              let sessionId = activeSession?.sessionId ?? webSocketService.getActiveSession() else {
            return
        }
        
        persistenceService.saveMessages(
            for: project.path,
            messages: messages,
            sessionId: sessionId,
            project: project
        )
        
        print("💾 Saved \(messages.count) messages for project \(project.name)")
    }
    
    func loadMessages(for project: Project, sessionId: String) {
        let restoredMessages = persistenceService.loadMessages(for: project.path, sessionId: sessionId)
        if !restoredMessages.isEmpty {
            messages = restoredMessages
            print("📖 Loaded \(messages.count) messages for project \(project.name)")
        }
    }
    
    // MARK: - Private Methods
    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Note: saveMessages needs project context, which should be provided by the view
        }
    }
    
    private func handleCommandResponse(_ message: WebSocketMessage) {
        messageTimeout?.invalidate()
        
        if case .aicliResponse(let response) = message.data {
            isLoading = false
            progressInfo = nil
            
            if response.success {
                let assistantMessage = Message(
                    content: response.content,
                    sender: .assistant,
                    type: .text,
                    metadata: AICLIMessageMetadata(
                        sessionId: response.sessionId ?? "",
                        duration: 0,
                        cost: nil,
                        tools: nil
                    )
                )
                messages.append(assistantMessage)
            } else {
                let errorMessage = Message(
                    content: response.error ?? "Unknown error occurred",
                    sender: .assistant,
                    type: .text
                )
                messages.append(errorMessage)
            }
        }
    }
    
    private func handleCommandError(_ error: AICLICompanionError) {
        messageTimeout?.invalidate()
        isLoading = false
        progressInfo = nil
        
        let errorMessage = Message(
            content: "Error: \(error.localizedDescription)",
            sender: .assistant,
            type: .text
        )
        messages.append(errorMessage)
    }
    
    // MARK: - WebSocket Event Handling
    func setupWebSocketListeners() {
        // Listen for stream data
        webSocketService.setMessageHandler(for: .streamData) { [weak self] message in
            guard let self = self else { return }
            
            if case .streamData(let streamData) = message.data {
                Task { @MainActor in
                    self.handleStreamData(streamData)
                }
            }
        }
        
        // Listen for stream completion
        webSocketService.setMessageHandler(for: .streamComplete) { [weak self] message in
            guard let self = self else { return }
            
            if case .streamComplete(let complete) = message.data {
                Task { @MainActor in
                    self.handleStreamComplete(complete)
                }
            }
        }
        
        // Listen for stream chunks
        webSocketService.setMessageHandler(for: .streamChunk) { [weak self] message in
            guard let self = self else { return }
            
            if case .streamChunk(let chunk) = message.data {
                Task { @MainActor in
                    self.handleStreamChunk(chunk)
                }
            }
        }
        
        // Listen for streaming completion notifications from ClaudeResponseStreamer
        NotificationCenter.default.publisher(for: .streamingComplete)
            .sink { [weak self] notification in
                guard let self = self else { return }
                
                if let message = notification.userInfo?["message"] as? Message {
                    Task { @MainActor in
                        self.handleStreamingComplete(message)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleStreamData(_ streamData: StreamDataResponse) {
        // Handle streaming data
        if streamData.streamType == "text" {
            responseStreamer.startStreaming(sessionId: streamData.sessionId)
            isLoading = false
        }
    }
    
    private func handleStreamComplete(_ complete: StreamCompleteResponse) {
        // Complete the streaming
        if let streamedMessage = responseStreamer.currentMessage,
           streamedMessage.streamingState == .complete {
            messages.append(streamedMessage)
        }
        isLoading = false
        progressInfo = nil
    }
    
    private func handleStreamChunk(_ chunkResponse: StreamChunkResponse) {
        if responseStreamer.currentSessionId != chunkResponse.sessionId {
            responseStreamer.startStreaming(sessionId: chunkResponse.sessionId)
            isLoading = false
            progressInfo = nil
        }
        
        // Post notification for the streamer
        NotificationCenter.default.post(
            name: .streamChunkReceived,
            object: nil,
            userInfo: ["chunk": chunkResponse.chunk]
        )
    }
    
    private func handleStreamingComplete(_ message: Message) {
        // Cancel timeout since we got a response
        messageTimeout?.invalidate()
        
        // Add the completed message to the UI
        messages.append(message)
        
        // Reset loading state
        isLoading = false
        progressInfo = nil
        
        print("✅ Added streamed message to UI: \(message.content.prefix(50))...")
    }
}