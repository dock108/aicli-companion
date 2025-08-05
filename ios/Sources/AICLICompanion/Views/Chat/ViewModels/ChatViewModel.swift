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
    private let queueManager = MessageQueueManager.shared
    private let reliabilityManager = ConnectionReliabilityManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    private let aicliService: AICLIService
    private let settings: SettingsManager
    
    // MARK: - Private Properties
    private var messageTimeout: Timer?
    private var autoSaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let responseStreamer = ClaudeResponseStreamer()
    private var isWaitingForClaudeResponse = false
    
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
        reliabilityManager.cacheMessage(userMessage)
        
        // Send command
        isLoading = true
        
        // Start performance tracking
        let messageStartTime = performanceMonitor.startMessageTracking(
            messageId: userMessage.id.uuidString,
            type: "user_command"
        )
        
        sendAICLICommand(text, for: project, messageStartTime: messageStartTime)
    }
    
    private func sendAICLICommand(_ command: String, for project: Project, messageStartTime: Date) {
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
        let claudeRequest = ClaudeCommandRequest(
            command: command,
            projectPath: project.path,
            sessionId: session.sessionId
        )
        
        print("📤 Sending command to server: \(command)")
        print("   Session ID: \(session.sessionId)")
        print("   Project path: \(project.path)")
        
        // Set timeout - 30 minutes to match server timeout
        messageTimeout?.invalidate()
        messageTimeout = Timer.scheduledTimer(withTimeInterval: 1800.0, repeats: false) { _ in
            Task { @MainActor in
                self.isLoading = false
                self.isWaitingForClaudeResponse = false
                let timeoutMessage = Message(
                    content: "⏰ Request timed out. The connection may have been lost or the server is taking too long to respond. Please try again.",
                    sender: .assistant,
                    type: .text
                )
                self.messages.append(timeoutMessage)
            }
        }
        
        // Mark that we're waiting for a direct Claude response
        isWaitingForClaudeResponse = true
        
        // Store the message start time for performance tracking
        objc_setAssociatedObject(claudeRequest, "messageStartTime", messageStartTime, .OBJC_ASSOCIATION_RETAIN)
        
        // Send via WebSocket
        webSocketService.sendMessage(claudeRequest, type: .claudeCommand) { result in
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
    
    func startSession(for project: Project, connection: ServerConnection, completion: (() -> Void)? = nil) {
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
                    
                    // Session is ready - no welcome message needed
                    // User can start typing immediately
                    
                    // Call completion callback if provided
                    completion?()
                    
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
        } else {
            // No persisted messages found - this could mean:
            // 1. A brand new session (no messages yet)
            // 2. Session exists on server but no conversation history was saved locally
            print("📝 No persisted messages found for session \(sessionId)")
            
            // Don't automatically add welcome message - let the natural flow handle it
            // The session will either:
            // - Show empty state if truly new
            // - Receive messages from server if conversation exists
            messages = []
        }
    }
    
    private func addWelcomeMessage(for project: Project) {
        let welcomeMessage = Message(
            content: "✅ Connected to **\(project.name)**\n\nSession restored. You can continue working on your project. I have access to all files in this directory.\n\nWhat can I help you with today?",
            sender: .assistant,
            type: .text
        )
        messages.append(welcomeMessage)
    }
    
    // MARK: - Private Methods
    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Note: saveMessages needs project context, which should be provided by the view
        }
    }
    
    private func handleCommandResponse(_ message: WebSocketMessage) {
        messageTimeout?.invalidate()
        isWaitingForClaudeResponse = false
        
        if case .claudeResponse(let response) = message.data {
            isLoading = false
            progressInfo = nil
            
            // Complete performance tracking
            if let requestId = message.requestId {
                performanceMonitor.completeMessageTracking(
                    messageId: requestId,
                    startTime: Date(), // This should be retrieved from the request
                    type: "claude_response",
                    success: response.success
                )
            }
            
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
        isWaitingForClaudeResponse = false
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
        // Listen for message history
        webSocketService.setMessageHandler(for: .getMessageHistory) { [weak self] message in
            guard let self = self else { return }
            
            if case .getMessageHistoryResponse(let historyResponse) = message.data {
                Task { @MainActor in
                    self.handleMessageHistory(historyResponse)
                }
            }
        }
        
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
        
        // Listen for queued message notifications
        webSocketService.setMessageHandler(for: .progress) { [weak self] message in
            guard let self = self else { return }
            
            if case .progress(let progress) = message.data {
                if progress.stage.contains("queue") {
                    Task { @MainActor in
                        self.handleQueueProgress(progress)
                    }
                }
            }
        }
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
        // Note: The message will be added by handleStreamingComplete notification
        isLoading = false
        progressInfo = nil
    }
    
    private func handleStreamChunk(_ chunkResponse: StreamChunkResponse) {
        // Cancel timeout since we're receiving data
        messageTimeout?.invalidate()
        
        // Don't start streaming for claudeCommand responses
        // These are complete responses that don't need streaming
        if isWaitingForClaudeResponse {
            // Just update progress info if there's tool activity
            if let toolName = extractToolName(from: chunkResponse.chunk) {
                let progressResponse = ProgressResponse(
                    sessionId: chunkResponse.sessionId,
                    stage: "Working",
                    progress: nil,
                    message: getActivityMessage(for: toolName),
                    timestamp: Date()
                )
                progressInfo = ProgressInfo(from: progressResponse)
            }
            return
        }
        
        // For actual streaming responses, start the streamer
        if responseStreamer.currentSessionId != chunkResponse.sessionId {
            responseStreamer.startStreaming(sessionId: chunkResponse.sessionId)
            isLoading = false
            progressInfo = nil
        }
        
        // Update activity based on chunk type
        if let toolName = extractToolName(from: chunkResponse.chunk) {
            let progressResponse = ProgressResponse(
                sessionId: chunkResponse.sessionId,
                stage: "Working",
                progress: nil,
                message: getActivityMessage(for: toolName),
                timestamp: Date()
            )
            progressInfo = ProgressInfo(from: progressResponse)
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
        
        // Check if this message was already received (deduplication after reconnect)
        if reliabilityManager.wasMessageReceived(message) {
            print("🔄 Duplicate message detected after reconnection, skipping")
            return
        }
        
        // Check if this message was queued
        var finalMessage = message
        if let sessionId = activeSession?.sessionId {
            let queueInfo = queueManager.getQueueInfo(for: sessionId)
            if queueInfo.count > 0 {
                // Mark message as delivered from queue
                finalMessage.markDeliveredFromQueue()
                queueManager.markMessageDelivered(messageId: message.id.uuidString)
            }
        }
        
        // Cache the message for reconnection deduplication
        reliabilityManager.cacheMessage(finalMessage)
        
        // Add the completed message to the UI with proper ordering
        let orderedMessages = MessageQueueOrganizer.sortMessages(messages + [finalMessage])
        messages = orderedMessages
        
        // Reset loading state
        isLoading = false
        progressInfo = nil
        
        print("✅ Added streamed message to UI: \(message.content.prefix(50))...")
    }
    
    private func handleQueueProgress(_ progress: ProgressResponse) {
        // Update progress info with queue status
        progressInfo = ProgressInfo(from: progress)
    }
    
    private func handleMessageHistory(_ historyResponse: GetMessageHistoryResponse) {
        print("📜 Processing message history for session \(historyResponse.sessionId)")
        
        // Only process if this is for our active session
        guard let activeSession = activeSession,
              activeSession.sessionId == historyResponse.sessionId else {
            print("⚠️ Received history for different session, ignoring")
            return
        }
        
        // Convert server messages to our Message format
        var serverMessages: [Message] = []
        
        for historyMessage in historyResponse.messages {
            let sender: MessageSender = historyMessage.type == "user" ? .user : .assistant
            
            // Extract text content from message content array
            var combinedContent = ""
            if let contents = historyMessage.content {
                for content in contents {
                    if let text = content.text {
                        combinedContent += text + "\n"
                    }
                }
            } else {
                // Fallback for user messages that might not have content array
                combinedContent = historyMessage.id.replacingOccurrences(of: "user-", with: "User prompt ")
            }
            
            let message = Message(
                content: combinedContent.trimmingCharacters(in: .whitespacesAndNewlines),
                sender: sender,
                type: .text,
                metadata: historyMessage.model != nil ? AICLIMessageMetadata(
                    sessionId: historyResponse.sessionId,
                    duration: 0,
                    cost: nil,
                    tools: nil
                ) : nil
            )
            
            serverMessages.append(message)
        }
        
        print("📜 Converted \(serverMessages.count) server messages")
        
        // Merge with existing messages
        mergeServerMessages(serverMessages, for: activeSession)
    }
    
    private func mergeServerMessages(_ serverMessages: [Message], for session: ProjectSession) {
        print("🔄 Merging \(serverMessages.count) server messages with \(messages.count) local messages")
        
        // If we have no local messages, just use server messages
        if messages.isEmpty {
            messages = serverMessages
            print("✅ Using all server messages (no local messages)")
            return
        }
        
        // Create a set of existing message content for deduplication
        let existingContent = Set(messages.map { $0.content })
        
        // Add server messages that don't already exist locally
        var addedCount = 0
        for serverMessage in serverMessages {
            if !existingContent.contains(serverMessage.content) {
                messages.append(serverMessage)
                addedCount += 1
            }
        }
        
        // Sort messages by timestamp to maintain chronological order
        messages.sort { $0.timestamp < $1.timestamp }
        
        print("✅ Added \(addedCount) new messages from server")
        print("📊 Total messages now: \(messages.count)")
        
        // Save the merged messages
        if let project = getCurrentProject() {
            saveMessages(for: project)
        }
    }
    
    private func getCurrentProject() -> Project? {
        // TODO: [QUESTION] How to get current project from ChatViewModel?
        // May need to pass project to view model or store it
        return nil
    }
    
    // MARK: - Activity Helpers
    private func extractToolName(from chunk: StreamChunk) -> String? {
        // Check if this is a tool_use type chunk
        if chunk.type == "tool_use", let metadata = chunk.metadata {
            return metadata.toolName
        }
        
        // Try to parse from content if it contains tool information
        if chunk.content.contains("tool_name") {
            // Simple extraction - could be improved with proper JSON parsing
            if let range = chunk.content.range(of: "\"tool_name\":\\s*\"([^\"]+)\"", options: .regularExpression) {
                let toolName = String(chunk.content[range])
                    .replacingOccurrences(of: "\"tool_name\":", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return toolName
            }
        }
        
        return nil
    }
    
    private func getActivityMessage(for toolName: String) -> String {
        switch toolName.lowercased() {
        case "read":
            return "Reading files..."
        case "edit", "multiedit":
            return "Making changes..."
        case "write":
            return "Writing files..."
        case "bash":
            return "Running commands..."
        case "grep":
            return "Searching code..."
        case "glob":
            return "Finding files..."
        case "ls":
            return "Listing directories..."
        case "task":
            return "Analyzing task..."
        case "webfetch":
            return "Fetching web content..."
        case "websearch":
            return "Searching the web..."
        default:
            return "Working on it..."
        }
    }
}