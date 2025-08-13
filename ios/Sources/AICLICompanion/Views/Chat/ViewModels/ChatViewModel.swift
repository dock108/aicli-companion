import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

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
    private let cloudKitManager = CloudKitSyncManager.shared
    
    // MARK: - Project Reference
    var currentProject: Project?
    
    // MARK: - Private Properties
    private var messageTimeout: Timer?
    private var autoSaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let responseStreamer = ClaudeResponseStreamer()
    private var isWaitingForClaudeResponse = false
    private var lastRequestId: String?
    private let autoResponseManager = AutoResponseManager.shared
    
    // MARK: - Initialization
    init(aicliService: HTTPAICLIService, settings: SettingsManager) {
        self.aicliService = aicliService
        self.settings = settings
        setupAutoSave()
        setupNotificationListeners()
    }
    
    deinit {
        messageTimeout?.invalidate()
        autoSaveTimer?.invalidate()
    }
    
    // MARK: - Message Management
    func sendMessage(_ text: String, for project: Project, attachments: [AttachmentData] = []) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        
        // Update current project reference if needed
        if currentProject?.path != project.path {
            currentProject = project
            // Notify push notification service about the active project
            PushNotificationService.shared.setActiveProject(project, sessionId: currentSessionId)
        }
        
        // Prepare message content with attachments
        var messageContent = text
        
        // If there are attachments, format them for display
        if !attachments.isEmpty {
            let attachmentList = attachments.map { "📎 \($0.name)" }.joined(separator: ", ")
            messageContent = text.isEmpty ? attachmentList : "\(text)\n\n\(attachmentList)"
        }
        
        // Add user message with attachments indicator
        let userMessage = Message(
            content: messageContent,
            sender: .user,
            type: .text,
            attachments: attachments
        )
        
        // WhatsApp/iMessage pattern: Add to conversation immediately
        messages.append(userMessage)
        
        // Save to local database immediately (local-first)
        if let sessionId = currentSessionId {
            // Existing conversation - save normally
            persistenceService.appendMessage(userMessage, to: project.path, sessionId: sessionId, project: project)
            print("💾 Saved user message with existing session ID: \(sessionId)")
        } else {
            // Fresh chat - just show in UI, don't save until Claude responds with session ID
            // Message already added to messages array above for immediate UI display
            print("💾 Fresh chat - user message shown in UI, will save when session ID arrives via APNS")
        }
        
        // Sync to CloudKit in background (optional)
        Task {
            do {
                try await cloudKitManager.saveMessage(userMessage, projectPath: project.path)
                print("✅ Message synced to CloudKit")
            } catch {
                print("⚠️ Failed to sync message to CloudKit: \(error)")
                // Continue anyway - local first approach
            }
        }
        
        // Send command
        isLoading = true
        
        // Start performance tracking
        let messageStartTime = performanceMonitor.startMessageTracking(
            messageId: userMessage.id.uuidString,
            type: "user_command"
        )
        
        sendAICLICommand(text, for: project, attachments: attachments, messageStartTime: messageStartTime)
    }
    
    private func sendAICLICommand(_ command: String, for project: Project, attachments: [AttachmentData] = [], messageStartTime: Date) {
        // Debug logging for connection state
        print("📤 ChatViewModel: Preparing to send message")
        print("   aicliService instance: \(ObjectIdentifier(aicliService))")
        print("   aicliService.isConnected: \(aicliService.isConnected)")
        print("   HTTPAICLIService.shared instance: \(ObjectIdentifier(HTTPAICLIService.shared))")
        print("   HTTPAICLIService.shared.isConnected: \(HTTPAICLIService.shared.isConnected)")
        
        // Ensure HTTP service is connected
        guard aicliService.isConnected else {
            isLoading = false
            print("❌ ChatViewModel: Service not connected, showing error message")
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
            sessionId: sessionIdToUse,
            attachments: attachments
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    // Handle response (session management only)
                    self.handleHTTPResponse(response)
                    
                    // ALWAYS keep loading state active - wait for APNS delivery
                    // All responses come through APNS for cross-device sync
                    print("⏳ Keeping loading state active until APNS delivers Claude's response")
                    
                case .failure(let error):
                    // Always clear loading state on error
                    self.messageTimeout?.invalidate()
                    self.messageTimeout = nil
                    self.isLoading = false
                    self.isWaitingForClaudeResponse = false
                    self.handleHTTPError(error)
                }
            }
        }
    }
    
    // MARK: - HTTP Response Handlers
    
    private func handleHTTPResponse(_ response: ClaudeChatResponse) {
        // Update session ID if provided (won't be for first message)
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
                
                // Session ID established - no additional processing needed
                // Local-first pattern: All messages already stored locally
            }
        }
        
        // ALL responses go through APNS - no direct response path
        // This ensures all messages sync across devices via CloudKit
        print("📋 ChatViewModel: Acknowledgment received - waiting for APNS delivery")
        
        if response.sessionId == nil {
            print("   📝 New conversation - waiting for Claude to generate session ID")
        }
        
        if let message = response.message {
            print("   Server acknowledgment: \(message)")
        }
        
        // Keep loading state active - APNS will deliver the actual response
        // DO NOT append any messages here - let APNS handler do it
        // DO NOT clear loading state here - wait for APNS delivery
    }
    
    private func handleHTTPError(_ error: AICLICompanionError) {
        // Check if it's a network timeout error
        var errorContent = "❌ Error: "
        if case .networkError(let nsError) = error {
            let nsErrorCode = (nsError as NSError).code
            if nsErrorCode == NSURLErrorTimedOut {
                errorContent = "❌ Error: Network error: The request timed out.\n\nPlease check your connection and try again."
            } else {
                errorContent = "❌ Error: \(error.localizedDescription)\n\nPlease check your connection and try again."
            }
        } else {
            errorContent = "❌ Error: \(error.localizedDescription)\n\nPlease check your connection and try again."
        }
        
        let errorMessage = Message(
            content: errorContent,
            sender: .assistant,
            type: .text
        )
        messages.append(errorMessage)
        print("❌ ChatViewModel: Added HTTP error message: \(error)")
        
        // If we have a project but no session ID yet, save messages as pending
        if let project = currentProject, currentSessionId == nil {
            print("⚠️ Saving messages as pending due to error before session creation")
            saveMessages(for: project)
        }
    }
    
    // MARK: - Session Management
    func setActiveSession(_ session: ProjectSession?) {
        activeSession = session
        if let session = session {
            currentSessionId = session.sessionId
        }
        
        // Notify push notification service about the active project/session change
        PushNotificationService.shared.setActiveProject(currentProject, sessionId: currentSessionId)
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
            print("⚠️ No session ID available yet for project \(project.name)")
            print("📝 Local-first pattern: Messages will be associated when session ID arrives via APNS")
            
            // Local-first pattern: Messages are already in UI and will be saved when session ID arrives
            // No need for complex pending message coordination
        }
    }
    
    func loadMessages(for project: Project, sessionId: String) {
        // Update current project reference
        currentProject = project
        currentSessionId = sessionId
        
        // Notify push notification service about the active project
        PushNotificationService.shared.setActiveProject(project, sessionId: sessionId)
        
        // WhatsApp/iMessage pattern: Load local conversation only
        print("📖 Loading conversation from local database...")
        let localMessages = persistenceService.loadMessages(for: project.path, sessionId: sessionId)
        self.messages = localMessages
        print("✅ Loaded \(self.messages.count) messages for \(project.name) (local-only)")
        
        // No server sync needed - push notifications handle new messages
        // Local database is the source of truth for the conversation
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
    
    private func setupNotificationListeners() {
        // Listen for Claude responses received via APNS
        NotificationCenter.default.publisher(for: .claudeResponseReceived)
            .sink { [weak self] notification in
                self?.handleClaudeResponseNotification(notification)
            }
            .store(in: &cancellables)
        
        // Listen for fresh chat session establishment
        NotificationCenter.default.publisher(for: .freshChatSessionEstablished)
            .sink { [weak self] notification in
                self?.handleFreshSessionEstablished(notification)
            }
            .store(in: &cancellables)
        
        // WhatsApp/iMessage pattern: No server polling needed
        // Push notifications deliver new messages automatically
        // App lifecycle events don't need to trigger server requests
    }
    
    private func handleClaudeResponseNotification(_ notification: Notification) {
        print("🎯 === CHATVIEWMODEL: APNS NOTIFICATION RECEIVED ===")
        
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? Message,
              let sessionId = userInfo["sessionId"] as? String,
              let project = userInfo["project"] as? Project else {
            print("⚠️ ChatViewModel: Invalid Claude response notification payload")
            if let keys = notification.userInfo?.keys {
                print("⚠️ userInfo keys: \(Array(keys))")
            } else {
                print("⚠️ userInfo is nil")
            }
            return
        }
        
        print("🎯 ChatViewModel: Claude response notification validated")
        print("🎯 Session ID: \(sessionId)")
        print("🎯 Current Session ID: \(currentSessionId ?? "nil")")
        print("🎯 Project: \(project.name) (\(project.path))")
        print("🎯 Current Project: \(currentProject?.name ?? "nil") (\(currentProject?.path ?? "nil"))")
        print("🎯 Message ID: \(message.id)")
        print("🎯 Message content preview: \(message.content.prefix(100))...")
        print("🎯 Current loading state: isLoading=\(isLoading), isWaiting=\(isWaitingForClaudeResponse)")
        print("🎯 Current message count: \(messages.count)")
        
        // Only process if:
        // 1. Session IDs match
        // 2. We don't have a session yet (first message) and project matches
        if currentSessionId == sessionId || (currentSessionId == nil && project.path == currentProject?.path) {
            print("🎯 === PROCESSING CLAUDE RESPONSE ===")
            
            // Simple duplicate check using message IDs only (best practices)
            let existingMessageIds = Set(messages.map { $0.id })
            
            if existingMessageIds.contains(message.id) {
                print("🔸 Duplicate message detected (ID: \(message.id)) - skipping")
                return
            }
            
            // Update session ID if we didn't have one (first message case)
            if currentSessionId == nil {
                currentSessionId = sessionId
                print("🔄 ChatViewModel: First message - setting session ID from Claude via APNS: \(sessionId)")
                
                // Session management for new conversations
                if let project = currentProject {
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
            
            // WhatsApp/iMessage pattern: Add message to conversation
            print("📝 Adding Claude response to conversation...")
            messages.append(message)
            print("✅ Added Claude response to chat (\(messages.count) total messages)")
            
            // Save to local database immediately
            if let project = currentProject, let sessionId = currentSessionId {
                persistenceService.appendMessage(message, to: project.path, sessionId: sessionId, project: project)
            }
            
            // Clear loading state - response received
            isWaitingForClaudeResponse = false
            isLoading = false
            messageTimeout?.invalidate()
            messageTimeout = nil
            
            // Clear badge count
            #if os(iOS)
            UIApplication.shared.applicationIconBadgeNumber = 0
            #endif
            
            // Sync to CloudKit in background (optional)
            if let project = currentProject {
                Task {
                    do {
                        try await cloudKitManager.saveMessage(message, projectPath: project.path)
                        print("✅ Claude message synced to CloudKit")
                    } catch {
                        print("⚠️ Failed to sync Claude message to CloudKit: \(error)")
                    }
                }
            }
            
            print("🎯 === CLAUDE RESPONSE PROCESSING COMPLETED ===")
        } else {
            print("❌ === SESSION MISMATCH - IGNORING RESPONSE ===")
            print("❌ Expected session: \(currentSessionId ?? "nil")")
            print("❌ Received session: \(sessionId)")
            print("❌ Expected project: \(currentProject?.path ?? "nil")")
            print("❌ Received project: \(project.path)")
        }
    }
    
    private func handleFreshSessionEstablished(_ notification: Notification) {
        print("🆕 === FRESH SESSION ESTABLISHED ===")
        
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? String,
              let projectPath = userInfo["projectPath"] as? String,
              let project = userInfo["project"] as? Project else {
            print("⚠️ ChatViewModel: Invalid fresh session notification payload")
            return
        }
        
        // Only handle if this is for the current project
        guard projectPath == currentProject?.path else {
            print("🔍 Fresh session for different project - ignoring")
            return
        }
        
        print("🆕 Fresh session established for current project: \(project.name)")
        print("🆕 Session ID: \(sessionId)")
        
        // Save any pending user messages that were shown in UI but not persisted
        let userMessagesToSave = messages.filter { $0.sender == .user }
        
        for message in userMessagesToSave {
            persistenceService.appendMessage(message, to: projectPath, sessionId: sessionId, project: project)
            print("💾 Saved pending user message: \(String(message.content.prefix(50)))...")
        }
        
        // Update current session ID
        currentSessionId = sessionId
        
        print("✅ Fresh chat session setup complete - \(userMessagesToSave.count) user messages saved")
    }
    
    private func handleCommandResponse(_ message: WebSocketMessage) {
        messageTimeout?.invalidate()
        isWaitingForClaudeResponse = false
        
        guard case .claudeResponse(let response) = message.data else { return }
        
        print("🔄 ChatViewModel: Received Claude response via callback - Success: \(response.success)")
        
        // Verify requestId matches
        if !verifyRequestId(message.requestId) { return }
        
        isLoading = false
        progressInfo = nil
        
        // Handle session ID
        handleSessionIdFromResponse(response.sessionId)
        
        // Track performance
        trackResponsePerformance(message.requestId, success: response.success)
        
        // Handle response content
        if response.success {
            handleSuccessfulResponse(response)
        } else {
            handleErrorResponse(response.error)
        }
    }
    
    private func verifyRequestId(_ messageRequestId: String?) -> Bool {
        guard let messageRequestId = messageRequestId, let expectedRequestId = lastRequestId else {
            return true // No requestId to verify
        }
        
        if messageRequestId != expectedRequestId {
            print("⚠️ ChatViewModel: Received response with mismatched requestId")
            print("   Expected: \(expectedRequestId)")
            print("   Received: \(messageRequestId)")
            return false
        }
        
        print("✅ ChatViewModel: Response requestId matches expected: \(messageRequestId)")
        return true
    }
    
    private func handleSessionIdFromResponse(_ sessionId: String?) {
        guard let sessionId = sessionId, !sessionId.isEmpty else {
            print("⚠️ ChatViewModel: No session ID received from server - messages may not persist")
            let warningMessage = Message(
                content: "⚠️ Server response missing session data - this conversation may not be saved",
                sender: .system,
                type: .text
            )
            messages.append(warningMessage)
            return
        }
        
        guard sessionId != currentSessionId else { return }
        
        print("🔄 ChatViewModel: Updating session ID from Claude response: \(sessionId) (was: \(currentSessionId ?? "nil"))")
        currentSessionId = sessionId
        print("🔄 ChatViewModel: Session ID successfully set to: \(currentSessionId ?? "nil")")
        
        createSessionIfNeeded(sessionId: sessionId)
        updateSessionPersistence(sessionId: sessionId)
    }
    
    private func createSessionIfNeeded(sessionId: String) {
        guard let project = getProjectFromSession(), activeSession == nil else { return }
        
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
    
    private func updateSessionPersistence(sessionId: String) {
        guard let project = getProjectFromSession() else { return }
        
        // Local-first pattern: Check if we have existing session metadata
        if persistenceService.getSessionMetadata(for: project.path) != nil {
            persistenceService.updateSessionMetadata(for: project.path, aicliSessionId: sessionId)
        } else {
            saveMessages(for: project)
        }
    }
    
    private func trackResponsePerformance(_ requestId: String?, success: Bool) {
        guard let requestId = requestId else { return }
        
        performanceMonitor.completeMessageTracking(
            messageId: requestId,
            startTime: Date(),
            type: "claude_response",
            success: success
        )
    }
    
    private func handleSuccessfulResponse(_ response: ClaudeCommandResponse) {
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
        
        // Check for auto-response
        if let autoResponse = autoResponseManager.processMessage(assistantMessage) {
            triggerAutoResponse(autoResponse)
        }
        
        // Sync to CloudKit
        syncMessageToCloudKit(assistantMessage)
        
        // Save conversation
        if let project = getProjectFromSession() {
            saveMessages(for: project)
        }
    }
    
    private func triggerAutoResponse(_ autoResponse: String) {
        print("🤖 Auto-response triggered: \(autoResponse)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + autoResponseManager.config.delayBetweenResponses) { [weak self] in
            guard let self = self, let project = self.currentProject else { return }
            self.sendMessage(autoResponse, for: project)
        }
    }
    
    private func syncMessageToCloudKit(_ message: Message) {
        guard let project = currentProject else { return }
        
        Task {
            do {
                try await cloudKitManager.saveMessage(message, projectPath: project.path)
                print("✅ Assistant message synced to CloudKit")
            } catch {
                print("⚠️ Failed to sync assistant message to CloudKit: \(error)")
            }
        }
    }
    
    private func handleErrorResponse(_ error: String?) {
        let errorMessage = Message(
            content: error ?? "Unknown error occurred",
            sender: .assistant,
            type: .text
        )
        messages.append(errorMessage)
        print("❌ ChatViewModel: Added error message to chat: \(error ?? "Unknown error")")
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
        
        // If we have no local messages, use incremental insertion instead of replacement
        if messages.isEmpty {
            // Insert server messages in chronological order
            let sortedServerMessages = serverMessages.sorted { $0.timestamp < $1.timestamp }
            messages.append(contentsOf: sortedServerMessages)
            print("✅ Added all \(serverMessages.count) server messages (no local messages)")
            return
        }
        
        // Create a set of existing message content for deduplication
        let existingContent = Set(messages.map { $0.content })
        
        // Add server messages that don't already exist locally
        var addedCount = 0
        var messageIdsToAcknowledge: [String] = []
        
        // Collect new messages that don't already exist
        var newServerMessages: [Message] = []
        for serverMessage in serverMessages where !existingContent.contains(serverMessage.content) {
            newServerMessages.append(serverMessage)
            addedCount += 1
            
            // Track message IDs that need acknowledgment (assistant messages)
            if serverMessage.sender == .assistant {
                messageIdsToAcknowledge.append(serverMessage.id.uuidString)
            }
        }
        
        // Insert new messages in chronological order without full array sort
        let sortedNewMessages = newServerMessages.sorted { $0.timestamp < $1.timestamp }
        for newMessage in sortedNewMessages {
            // Find correct insertion point to maintain chronological order
            if let insertIndex = messages.firstIndex(where: { $0.timestamp > newMessage.timestamp }) {
                messages.insert(newMessage, at: insertIndex)
            } else {
                // Message is newest, append to end
                messages.append(newMessage)
            }
        }
        
        print("✅ Added \(addedCount) new messages from server")
        print("📊 Total messages now: \(messages.count)")
        
        // Messages are already saved via append operations - no bulk save needed
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
    
    
    // MARK: - WhatsApp/iMessage Pattern: Simple Local Operations
    // No complex merging needed - messages are appended via APNS or user actions
    
    // MARK: - CloudKit Sync Methods
    
    func syncMessages(for project: Project) async {
        guard cloudKitManager.iCloudAvailable else {
            print("⚠️ iCloud not available, skipping sync")
            return
        }
        
        do {
            print("🔄 Starting CloudKit sync for project: \(project.path)")
            let cloudMessages = try await cloudKitManager.fetchMessages(for: project.path)
            
            await MainActor.run {
                self.mergeCloudMessages(cloudMessages)
            }
            
            print("✅ CloudKit sync completed for project: \(project.path)")
        } catch {
            print("❌ Failed to sync messages from CloudKit: \(error)")
        }
    }
    
    private func mergeCloudMessages(_ cloudMessages: [Message]) {
        var newMessagesCount = 0
        var foundSessionId: String?
        
        for cloudMessage in cloudMessages {
            // Extract sessionId from CloudKit messages if we don't have one
            if currentSessionId == nil,
               let sessionId = cloudMessage.metadata?.sessionId,
               !sessionId.isEmpty {
                foundSessionId = sessionId
            }
            
            // Check if message already exists locally
            if !messages.contains(where: { $0.id == cloudMessage.id }) {
                // Find correct insertion point to maintain chronological order
                if let insertIndex = messages.firstIndex(where: { $0.timestamp > cloudMessage.timestamp }) {
                    messages.insert(cloudMessage, at: insertIndex)
                } else {
                    // Message is newest, append to end
                    messages.append(cloudMessage)
                }
                newMessagesCount += 1
            }
        }
        
        // Adopt the sessionId from CloudKit messages for project continuity
        if let sessionId = foundSessionId, currentSessionId == nil {
            currentSessionId = sessionId
            print("📱 Adopted sessionId from CloudKit: \(sessionId)")
            print("🔄 This device will now continue the same conversation")
        }
        
        if newMessagesCount > 0 {
            print("✅ Merged \(newMessagesCount) new messages from CloudKit")
            print("📊 Total messages now: \(messages.count)")
        } else {
            print("📝 No new messages from CloudKit (all already local)")
        }
    }
    
    func performManualSync(for project: Project) async {
        guard cloudKitManager.iCloudAvailable else { return }
        
        // First, sync messages from CloudKit
        await syncMessages(for: project)
        
        // Then, upload any local messages that need syncing
        for message in messages where message.needsSync {
            do {
                try await cloudKitManager.saveMessage(message, projectPath: project.path)
                print("✅ Uploaded message to CloudKit: \(message.id)")
            } catch {
                print("⚠️ Failed to upload message \(message.id): \(error)")
            }
        }
    }
    
    // MARK: - WhatsApp/iMessage Pattern: No Server Polling Needed
    // Push notifications deliver new messages automatically
    // Local database is the source of truth for conversations
}
