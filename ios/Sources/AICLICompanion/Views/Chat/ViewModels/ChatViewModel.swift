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
    @Published var currentSessionId: String?
    
    // MARK: - Services
    private let persistenceService = MessagePersistenceService.shared
    private let performanceMonitor = PerformanceMonitor.shared
    private let aicliService: HTTPAICLIService
    private let settings: SettingsManager
    
    // MARK: - Project Reference
    var currentProject: Project?
    
    // MARK: - Private Properties
    private var messageTimeout: Timer?
    private var autoSaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let responseStreamer = ClaudeResponseStreamer()
    private var isWaitingForClaudeResponse = false
    private var lastRequestId: String?
    
    // MARK: - Initialization
    init(aicliService: HTTPAICLIService, settings: SettingsManager) {
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
        
        // Start performance tracking
        let messageStartTime = performanceMonitor.startMessageTracking(
            messageId: userMessage.id.uuidString,
            type: "user_command"
        )
        
        sendAICLICommand(text, for: project, messageStartTime: messageStartTime)
    }
    
    private func sendAICLICommand(_ command: String, for project: Project, messageStartTime: Date) {
        // Ensure HTTP service is connected
        guard aicliService.isConnected else {
            isLoading = false
            let errorMessage = Message(
                content: "❌ Not connected to server. Please check your connection.",
                sender: .assistant,
                type: .text
            )
            messages.append(errorMessage)
            return
        }
        
        // Use Claude's session ID if we have one, otherwise send without session ID
        // For fresh chats: currentSessionId will be nil
        // For continued chats: currentSessionId will have Claude's session ID
        let sessionIdToUse = currentSessionId ?? activeSession?.sessionId
        
        print("📤 Sending HTTP message to server: \(command)")
        print("   Session ID: \(sessionIdToUse ?? "none (fresh chat)")")
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
        
        // Send via HTTP
        aicliService.sendMessage(
            message: command,
            projectPath: project.path,
            sessionId: sessionIdToUse
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                // Cancel timeout
                self.messageTimeout?.invalidate()
                self.messageTimeout = nil
                self.isLoading = false
                self.isWaitingForClaudeResponse = false
                
                switch result {
                case .success(let response):
                    self.handleHTTPResponse(response)
                case .failure(let error):
                    self.handleHTTPError(error)
                }
            }
        }
    }
    
    // MARK: - HTTP Response Handlers
    
    private func handleHTTPResponse(_ response: ClaudeChatResponse) {
        // Update session ID if provided
        if let sessionId = response.sessionId, !sessionId.isEmpty {
            if sessionId != currentSessionId {
                print("🔄 ChatViewModel: Updating session ID from HTTP response: \(sessionId)")
                currentSessionId = sessionId
                
                // Create session object for the UI if we have a current project
                if let project = getProjectFromSession(), activeSession == nil {
                    let session = ProjectSession(
                        sessionId: sessionId,
                        projectName: project.name,
                        projectPath: project.path,
                        status: "active",
                        startedAt: Date().ISO8601Format()
                    )
                    setActiveSession(session)
                }
            }
        }
        
        // Add assistant's response to messages
        let assistantMessage = Message(
            content: response.content,
            sender: .assistant,
            type: .markdown, // HTTP responses are typically markdown
            metadata: AICLIMessageMetadata(
                sessionId: response.sessionId ?? "",
                duration: 0,
                additionalInfo: [
                    "httpResponse": true,
                    "timestamp": response.timestamp
                ]
            )
        )
        messages.append(assistantMessage)
        print("✅ ChatViewModel: Added HTTP response message to chat")
        
        // Save conversation
        if let project = getProjectFromSession() {
            saveMessages(for: project)
        }
    }
    
    private func handleHTTPError(_ error: AICLICompanionError) {
        let errorMessage = Message(
            content: "❌ Error: \(error.localizedDescription)\n\nPlease check your connection and try again.",
            sender: .assistant,
            type: .text
        )
        messages.append(errorMessage)
        print("❌ ChatViewModel: Added HTTP error message: \(error)")
    }
    
    // MARK: - Session Management
    func setActiveSession(_ session: ProjectSession?) {
        activeSession = session
        if let session = session {
            currentSessionId = session.sessionId
        }
    }
    
    
    // MARK: - Message Persistence
    func saveMessages(for project: Project) {
        guard !messages.isEmpty else {
            print("📝 No messages to save for project \(project.name)")
            return
        }
        
        // Use Claude's session ID if available, fallback to other sources
        let sessionId = currentSessionId ?? activeSession?.sessionId
        
        if let sessionId = sessionId {
            // We have a session ID, save normally
            persistenceService.saveMessages(
                for: project.path,
                messages: messages,
                sessionId: sessionId,
                project: project
            )
            
            print("💾 Saved \(messages.count) messages for project \(project.name) with session ID: \(sessionId)")
        } else {
            // No session ID yet - this happens when user leaves before Claude responds
            print("⚠️ No session ID available yet for project \(project.name) - storing messages as pending")
            
            // Store messages in background coordinator to be saved when session ID arrives
            BackgroundSessionCoordinator.shared.storePendingMessages(
                for: project,
                messages: messages,
                requestId: lastRequestId  // Track which request will bring the session ID
            )
        }
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
            print("🔄 ChatViewModel: Received Claude response via callback - Success: \(response.success)")
            
            // Verify requestId matches to ensure response is for this chat
            if let messageRequestId = message.requestId, let expectedRequestId = lastRequestId {
                if messageRequestId != expectedRequestId {
                    print("⚠️ ChatViewModel: Received response with mismatched requestId")
                    print("   Expected: \(expectedRequestId)")
                    print("   Received: \(messageRequestId)")
                    // This response is not for our request, ignore it
                    return
                }
                print("✅ ChatViewModel: Response requestId matches expected: \(messageRequestId)")
            }
            
            isLoading = false
            progressInfo = nil
            
            // Extract and store Claude's session ID
            if let sessionId = response.sessionId, !sessionId.isEmpty {
                if sessionId != currentSessionId {
                    print("🔄 ChatViewModel: Updating session ID from Claude response: \(sessionId) (was: \(currentSessionId ?? "nil"))")
                    currentSessionId = sessionId
                    print("🔄 ChatViewModel: Session ID successfully set to: \(currentSessionId ?? "nil")")
                    
                    // Create session object for the UI if we have a current project and no active session
                    if let project = getProjectFromSession(), activeSession == nil {
                        ChatSessionManager.shared.createSessionFromClaudeResponse(
                            sessionId: sessionId,
                            for: project
                        ) { result in
                            switch result {
                            case .success(let session):
                                Task { @MainActor in
                                    self.setActiveSession(session)
                                }
                            case .failure(let error):
                                print("❌ Failed to create session from Claude response: \(error)")
                            }
                        }
                    }
                    
                    // Update persistence with Claude's session ID
                    if let project = getProjectFromSession() {
                        // First check if we need to save pending messages
                        if BackgroundSessionCoordinator.shared.hasPendingMessages(for: project.path) {
                            // Don't update metadata here - BackgroundSessionCoordinator will handle it
                            print("📋 Session ID received, pending messages will be processed by BackgroundSessionCoordinator")
                        } else if persistenceService.getSessionMetadata(for: project.path) != nil {
                            // Only update if metadata already exists
                            persistenceService.updateSessionMetadata(for: project.path, aicliSessionId: sessionId)
                        } else {
                            // No metadata yet - save current messages to create it
                            saveMessages(for: project)
                        }
                    }
                }
            } else {
                // No session ID available - add warning message
                print("⚠️ ChatViewModel: No session ID received from server - messages may not persist")
                let warningMessage = Message(
                    content: "⚠️ Server response missing session data - this conversation may not be saved",
                    sender: .system,
                    type: .text
                )
                messages.append(warningMessage)
            }
            
            // Complete performance tracking
            if let requestId = message.requestId {
                performanceMonitor.completeMessageTracking(
                    messageId: requestId,
                    startTime: Date(), // This should be retrieved from the request
                    type: "claude_response",
                    success: response.success
                )
            }
            
            // Handle the response content
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
                print("✅ ChatViewModel: Added Claude response message to chat")
                
                // Also save the complete conversation now that we have a session ID
                if let project = getProjectFromSession() {
                    saveMessages(for: project)
                }
            } else {
                let errorMessage = Message(
                    content: response.error ?? "Unknown error occurred",
                    sender: .assistant,
                    type: .text
                )
                messages.append(errorMessage)
                print("❌ ChatViewModel: Added error message to chat: \(response.error ?? "Unknown error")")
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
    
    // MARK: - HTTP Event Handling (Simplified)
    // HTTP responses are handled directly in sendMessage completion handlers
    // No separate event listeners needed since HTTP is request-response based
    
    // WebSocket streaming handlers removed - HTTP responses are complete and immediate
    
    private func getProjectFromSession() -> Project? {
        return currentProject
    }
    
    private func handleStreamingComplete(_ message: Message) {
        // Cancel timeout since we got a response
        messageTimeout?.invalidate()
        
        // HTTP responses are direct - no deduplication or queuing needed
        // Add the message directly to the UI
        messages.append(message)
        
        // Reset loading state
        isLoading = false
        progressInfo = nil
        
        print("✅ Added streamed message to UI: \(message.content.prefix(50))...")
    }
    
    private func handleQueueProgress(_ progress: ProgressResponse) {
        // Update progress info with queue status
        progressInfo = ProgressInfo(from: progress)
    }
    
    private func handleConversationResult(_ result: ConversationResultResponse, messageId: String?) {
        // Cancel timeout since we got a response
        messageTimeout?.invalidate()
        
        // Extract and store Claude's session ID if different from current
        if let claudeSessionId = result.claudeSessionId ?? result.sessionId {
            if claudeSessionId != currentSessionId {
                print("🔄 ChatViewModel: Updating session ID from Claude: \(claudeSessionId) (was: \(currentSessionId ?? "nil"))")
                currentSessionId = claudeSessionId
                print("🔄 ChatViewModel: Session ID successfully set to: \(currentSessionId ?? "nil")")
                
                // Create session object for the UI if we have a current project and no active session
                if let project = getProjectFromSession(), activeSession == nil {
                    ChatSessionManager.shared.createSessionFromClaudeResponse(
                        sessionId: claudeSessionId,
                        for: project
                    ) { result in
                        switch result {
                        case .success(let session):
                            Task { @MainActor in
                                self.setActiveSession(session)
                            }
                        case .failure(let error):
                            print("❌ Failed to create session from Claude response: \(error)")
                        }
                    }
                }
                
                // Update persistence with Claude's session ID
                if let project = getProjectFromSession() {
                    persistenceService.updateSessionMetadata(for: project.path, aicliSessionId: claudeSessionId)
                }
            }
        }
        
        // Create message from conversation result
        if let content = result.result, !content.isEmpty {
            let message = Message(
                content: content,
                sender: .assistant,
                type: .text,
                metadata: AICLIMessageMetadata(
                    sessionId: result.claudeSessionId ?? result.sessionId ?? currentSessionId ?? "",
                    duration: TimeInterval(result.duration ?? 0),
                    additionalInfo: [
                        "conversationResult": true,
                        "success": result.success
                    ]
                )
            )
            
            // HTTP responses are direct - add message to UI
            messages.append(message)
            
            // Save the complete conversation now that we have messages and a session ID
            if let project = getProjectFromSession() {
                saveMessages(for: project)
            }
        }
        
        isLoading = false
        progressInfo = nil
    }
    
    private func handleAssistantMessage(_ assistantMsg: AssistantMessageResponse, messageId: String?) {
        // Cancel timeout since we got a response  
        messageTimeout?.invalidate()
        
        // Extract text content from content blocks
        let textContent = assistantMsg.content
            .compactMap { content -> String? in
                if content.type == "text" {
                    return content.text
                }
                return nil
            }
            .joined(separator: "\n\n")
        
        if !textContent.isEmpty {
            let message = Message(
                id: UUID(uuidString: assistantMsg.messageId ?? "") ?? UUID(),
                content: textContent,
                sender: .assistant,
                type: .markdown,
                metadata: AICLIMessageMetadata(
                    sessionId: currentSessionId ?? "",
                    duration: 0,
                    additionalInfo: [
                        "model": assistantMsg.model ?? "unknown",
                        "messageType": assistantMsg.type
                    ]
                )
            )
            
            // HTTP responses are direct - add message to UI
            messages.append(message)
            
            // Save the complete conversation now that we have messages
            if let project = getProjectFromSession() {
                saveMessages(for: project)
            }
        }
        
        isLoading = false
        progressInfo = nil
    }
    
    // HTTP doesn't need message acknowledgment - removed
    
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
        var messageIdsToAcknowledge: [String] = []
        
        for serverMessage in serverMessages {
            if !existingContent.contains(serverMessage.content) {
                messages.append(serverMessage)
                addedCount += 1
                
                // Track message IDs that need acknowledgment (assistant messages)
                if serverMessage.sender == .assistant {
                    messageIdsToAcknowledge.append(serverMessage.id.uuidString)
                }
            }
        }
        
        // HTTP doesn't need message acknowledgment - messages are delivered directly
        
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
