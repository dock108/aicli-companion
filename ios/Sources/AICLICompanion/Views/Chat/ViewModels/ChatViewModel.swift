import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Singleton
    static let shared = ChatViewModel()
    
    // MARK: - Project State Structure
    private struct ProjectState {
        var isLoading: Bool = false
        var progressInfo: ProgressInfo?
        var isWaitingForResponse: Bool = false
        // Persistent thinking indicator state (survives app lifecycle changes)
        var persistentThinkingInfo: ProgressInfo?
        var messageTimeout: Timer?
        var loadingTimeout: Timer?
        var sessionLostTimer: Timer?
        var autoSaveTimer: Timer?
        // Message storage removed - using MessagePersistenceService directly
        var pendingUserMessages: [Message] = []
        // Queue management for message flow control
        var messageQueue: [(text: String, attachments: [AttachmentData])] = []
        var isProcessingQueue: Bool = false
        var lastStatusCheckTime: Date = Date()
        
        mutating func cancelTimers() {
            messageTimeout?.invalidate()
            messageTimeout = nil
            loadingTimeout?.invalidate()
            loadingTimeout = nil
            sessionLostTimer?.invalidate()
            sessionLostTimer = nil
            autoSaveTimer?.invalidate()
            autoSaveTimer = nil
        }
        
        mutating func cancelNonPollingTimers() {
            sessionLostTimer?.invalidate()
            sessionLostTimer = nil
        }
    }
    
    // MARK: - Services
    private let loadingStateCoordinator = LoadingStateCoordinator.shared
    private let logger = LoggingManager.shared
    
    // MARK: - Published Properties
    @Published var messages: [Message] = []
    @Published var isLoading = false  // Synced with unified loading state coordinator
    @Published var progressInfo: ProgressInfo?  // Synced with current project's state
    @Published var sessionError: String?
    @Published var activeSession: ProjectSession?
    @Published var currentSessionId: String?
    @Published var queuedMessageCount: Int = 0
    @Published var hasQueuedMessages: Bool = false
    
    // MARK: - Queue Configuration
    public var maxQueueSize: Int = 10
    
    // MARK: - Performance Optimization
    private var updateDebounceTimer: Timer?
    private let updateDebounceInterval: TimeInterval = 0.1 // 100ms debounce
    
    // MARK: - Defensive Error Handling
    private let maxLoadingDuration: TimeInterval = 300.0 // 5 minutes max loading
    private let sessionValidationInterval: TimeInterval = 60.0 // Validate session every minute
    private var lastSessionValidation: Date = Date()
    
    // MARK: - Project-Specific State
    // All project-specific state managed through ProjectState
    private var projectStates: [String: ProjectState] = [:]
    
    // Legacy: These will be fully migrated in Phase 6
    private var projectSessionIds: [String: String] = [:]
    private var pendingUserMessages: [Message] = []
    
    // MARK: - Project State Helpers
    private func getOrCreateProjectState(for project: Project) -> ProjectState {
        if projectStates[project.path] == nil {
            var newState = ProjectState()
            // No initialization needed - messages loaded from persistence on demand
            projectStates[project.path] = newState
        }
        return projectStates[project.path]!
    }
    
    private func updateProjectState(for project: Project, update: (inout ProjectState) -> Void) {
        var state = getOrCreateProjectState(for: project)
        update(&state)
        projectStates[project.path] = state
    }
    
    // MARK: - Message Management Helpers
    
    private func appendMessageToProject(_ message: Message, project: Project? = nil) {
        guard let project = project ?? currentProject else {
            print("❌ ERROR: No project context for message")
            return
        }
        
        // Message storage consolidated - no need to update ProjectState messages
        
        // Update current view if this is current project
        if project.path == currentProject?.path {
            messages.append(message)
        }
        
        // Message storage consolidated - no caching needed
        
        // Persist if we have session
        if let sessionId = getSessionId(for: project) {
            persistenceService.appendMessage(message, to: project.path, sessionId: sessionId, project: project)
        }
    }
    
    // Note: queuedMessageCount and hasQueuedMessages are @Published properties
    // They are updated when queue operations occur
    
    // MARK: - Send Blocking Logic (Simple One-Message-At-A-Time Flow)
    
    /// Check if sending should be blocked (simple blocking rules)
    /// Returns true if sending should be blocked, false if allowed
    func shouldBlockSending(for project: Project) -> Bool {
        // Get project-specific session ID instead of global currentSessionId
        let projectSessionId = getSessionId(for: project)
        let hasSession = projectSessionId != nil
        let isLoading = isLoadingForProject(project.path)
        let isWaiting = isWaitingForClaudeResponse
        let hasMessages = !messages.isEmpty
        
        // Only log debug info when blocking (to reduce console spam)
        let willBlock = isLoading || isWaiting || (hasMessages && projectSessionId == nil) ||
                       (hasMessages && messages.last?.sender == .user)
        
        if willBlock {
            print("🔵 Send blocking check for project \(project.name):")
            print("   hasSession: \(hasSession)")
            print("   isLoading: \(isLoading)")
            print("   isWaiting: \(isWaiting)")
            print("   hasMessages: \(hasMessages)")
            print("   projectSessionId: \(projectSessionId ?? "nil")")
        }
        
        // Rule 1: Currently loading/waiting for response
        if isLoading {
            print("   ❌ Blocking: Loading for project")
            return true
        }
        
        // Rule 2: Explicitly waiting for Claude response
        if isWaitingForClaudeResponse {
            print("   ❌ Blocking: Waiting for Claude response")
            return true
        }
        
        // Rule 3: Only block for session ID if we have messages but no session
        // (Fresh chats with no messages are allowed to send the first message)
        if hasMessages && projectSessionId == nil {
            print("   ❌ Blocking: Has messages but no session ID for this project")
            return true
        }
        
        // Rule 4: If we have messages, check if last message is from user (waiting for response)
        if hasMessages {
            if let lastMessage = messages.last {
                print("   Last message sender: \(lastMessage.sender)")
                print("   Last message content preview: \"\(String(lastMessage.content.prefix(50)))...\"")
                
                if lastMessage.sender == .user {
                    print("   ❌ Blocking: Last message from user, waiting for Claude")
                    return true
                }
            } else {
                print("   Warning: hasMessages=true but messages.last is nil")
            }
        }
        
        // Only log when allowing send after being blocked
        if !willBlock {
            print("   ✅ Send allowed")
        }
        return false
    }
    
    
    // Debug helper to log current queue state
    func debugQueueState() {
        guard let project = currentProject else {
            logger.debug("No current project", category: .state)
            return
        }
        
        let state = projectStates[project.path]
        let queueCount = state?.messageQueue.count ?? 0
        let isWaiting = state?.isWaitingForResponse ?? false
        let isProcessing = state?.isProcessingQueue ?? false
        let isLoading = state?.isLoading ?? false
        
        logger.debug("Queue State for \(project.name):", category: .queue)
        print("   Queue count: \(queueCount)")
        print("   Published queuedMessageCount: \(queuedMessageCount)")
        print("   Published hasQueuedMessages: \(hasQueuedMessages)")
        print("   isWaitingForResponse: \(isWaiting)")
        print("   isProcessingQueue: \(isProcessing)")
        print("   isLoading: \(isLoading)")
        
        if queueCount > 0 {
            print("   Queued messages:")
            for (index, queuedMsg) in (state?.messageQueue ?? []).enumerated() {
                print("     \(index + 1). \(String(queuedMsg.text.prefix(50)))...")
            }
        }
    }
    
    // Computed property to check if a specific project is loading
    func isLoadingForProject(_ projectPath: String) -> Bool {
        // Use unified loading state coordinator as source of truth
        return loadingStateCoordinator.isChatLoading(for: projectPath)
    }
    
    // Clear loading state for a specific project
    func clearLoadingState(for projectPath: String) {
        // Use unified loading state coordinator
        loadingStateCoordinator.stopChatLoading(for: projectPath)
        
        if var state = projectStates[projectPath] {
            state.isLoading = false
            state.isWaitingForResponse = false
            // Don't clear progressInfo if there's persistent thinking info
            if state.persistentThinkingInfo == nil {
                state.progressInfo = nil
            }
            state.cancelTimers()
            projectStates[projectPath] = state
            
            // Update global state if this is the current project
            if currentProject?.path == projectPath {
                // isLoading will be updated via setupLoadingStateSync()
                // Keep progressInfo if there's persistent thinking info
                if let persistentInfo = projectStates[projectPath]?.persistentThinkingInfo {
                    progressInfo = persistentInfo
                } else {
                    progressInfo = nil
                }
                isWaitingForClaudeResponse = false
            }
            
            print("🧹 Cleared loading state for project: \(projectPath)")
        }
    }
    
    
    // MARK: - Services
    private let persistenceService = MessagePersistenceService.shared
    private let performanceMonitor = PerformanceMonitor.shared
    private let aicliService = AICLIService.shared
    private let settings = SettingsManager.shared
    // CloudKit removed - local storage only
    
    // MARK: - Project Reference
    var currentProject: Project? {
        didSet {
            // Update the unified project state manager
            ProjectStateManager.shared.setCurrentProject(currentProject)
            
            if let oldProject = oldValue, oldProject.path != currentProject?.path {
                // Save state for the old project before switching
                updateProjectState(for: oldProject) { state in
                    // Messages are now persisted directly, no caching needed
                    state.pendingUserMessages = pendingUserMessages
                    // Timers are already in state, will be cancelled if needed
                }
                
                // Update session storage (messages now in ProjectState only)
                if let sessionId = currentSessionId {
                    projectSessionIds[oldProject.path] = sessionId
                } else if !pendingUserMessages.isEmpty {
                    projectSessionIds[oldProject.path] = "pending-\(oldProject.path)"
                }
                
                pendingUserMessages.removeAll()
            }
            
            // Load state for the new project
            if let newProject = currentProject {
                // Initialize project state if needed
                let projectState = getOrCreateProjectState(for: newProject)
                
                // Load messages from persistence instead of cached state
                let sessionId = getSessionId(for: newProject)
                currentSessionId = sessionId
                messages = MessagePersistenceService.shared.loadMessages(
                    for: newProject.path,
                    sessionId: sessionId ?? ""
                )
                pendingUserMessages = projectState.pendingUserMessages
                
                // Update published properties from project state
                isLoading = projectState.isLoading
                // Restore persistent thinking info if it exists, otherwise use regular progress info
                progressInfo = projectState.persistentThinkingInfo ?? projectState.progressInfo
                
                // Handle pending marker
                if let sessionId = projectSessionIds[newProject.path], sessionId.starts(with: "pending-") {
                    currentSessionId = nil
                }
                
                // Notify push notification service
                if let sessionId = currentSessionId {
                    PushNotificationService.shared.setActiveProject(newProject, sessionId: sessionId)
                }
            }
        }
    }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var isWaitingForClaudeResponse = false
    private var lastRequestId: String?
    private let autoResponseManager = AutoResponseManager.shared
    
    // MARK: - Initialization
    private init() {
        setupNotificationListeners()
        setupLoadingStateSync()
    }
    
    private func setupLoadingStateSync() {
        // Sync loading state with the unified coordinator
        loadingStateCoordinator.$projectLoadingStates
            .sink { [weak self] projectStates in
                guard let self = self, let currentProject = self.currentProject else { return }
                
                let newLoadingState = projectStates[currentProject.path] ?? false
                if self.isLoading != newLoadingState {
                    self.isLoading = newLoadingState
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        // Cancel all project timers
        for (_, state) in projectStates {
            var mutableState = state
            mutableState.cancelTimers()
        }
    }
    
    // MARK: - Lifecycle Management
    
    func onDisappear() {
        // Clean up timers when leaving the chat view
        if let currentProject = currentProject {
            updateProjectState(for: currentProject) { state in
                state.cancelNonPollingTimers()
            }
        }
        print("👋 Chat view disappeared - cleaned up timers")
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
        
        // FEATURE FLAG: Queue system logic (currently disabled)
        if FeatureFlags.shouldUseQueueSystem {
            // Check if we should queue the message instead of sending immediately
            let projectState = projectStates[project.path]
            let isProcessing = projectState?.isProcessingQueue ?? false
            let isWaitingForResponse = projectState?.isWaitingForResponse ?? false
            
            print("🔍 Queue check for \(project.name): waiting=\(isWaitingForResponse), processing=\(isProcessing)")
            
            if isWaitingForResponse && !isProcessing {
                print("📦 Queueing message because project is waiting for response")
                return queueMessage(text, for: project, attachments: attachments)
            }
        } else {
            FeatureFlags.logFeatureDisabled("Queue System", reason: "Using simple one-message-at-a-time flow")
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
        
        // Message added to UI state (persistence handled separately)
        
        // Save to local database immediately (local-first)
        if let sessionId = currentSessionId {
            // Existing conversation - save normally
            persistenceService.appendMessage(userMessage, to: project.path, sessionId: sessionId, project: project)
            print("💾 Saved user message with existing session ID: \(sessionId)")
        } else {
            // Fresh chat - track this message as pending until we get session ID
            pendingUserMessages.append(userMessage)
            print("💾 Fresh chat - user message shown in UI and tracked as pending")
            print("📌 Pending messages count: \(pendingUserMessages.count)")
            
            // Mark this project as having pending messages
            projectSessionIds[project.path] = "pending-\(project.path)"
        }
        
        // Messages persisted immediately to MessagePersistenceService
        
        // Send command - set loading state for THIS project
        loadingStateCoordinator.startChatLoading(for: project.path, timeout: 300.0)
        
        updateProjectState(for: project) { state in
            state.isLoading = true
        }
        // isLoading will be updated via setupLoadingStateSync()
        startLoadingTimeout(for: project)
        updateLoadingMessage()
        
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
        print("   AICLIService.shared instance: \(ObjectIdentifier(AICLIService.shared))")
        print("   AICLIService.shared.isConnected: \(AICLIService.shared.isConnected)")
        
        // Ensure HTTP service is connected
        guard aicliService.isConnected else {
            updateProjectState(for: project) { state in
                state.isLoading = false
            }
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
        
        // Use project-specific session ID if we have one, otherwise send without session ID
        // For fresh chats: project session will be nil
        // For continued chats: project session will have Claude's session ID
        let sessionIdToUse = getSessionId(for: project)
        
        print("📤 Sending HTTP message to server: \(command)")
        print("   Session ID: \(sessionIdToUse ?? "none (fresh chat)")")
        print("   Project path: \(project.path)")
        
        // Set timeout - 30 minutes to match server timeout
        updateProjectState(for: project) { state in
            state.messageTimeout?.invalidate()
            state.messageTimeout = Timer.scheduledTimer(withTimeInterval: 1800.0, repeats: false) { _ in
                Task { @MainActor in
                    // Clear loading state for this specific project
                    self.updateProjectState(for: project) { state in
                        state.isLoading = false
                        state.isWaitingForResponse = false
                        state.messageTimeout = nil
                    }
                    
                    // Update global state if this is the current project
                    if self.currentProject?.path == project.path {
                        self.isLoading = false
                        self.isWaitingForClaudeResponse = false
                    }
                    
                    // Response timeout handled
                    let timeoutMessage = Message(
                        content: "⏰ Request timed out. The connection may have been lost or the server is taking too long to respond. Please try again.",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(timeoutMessage)
                }
            }
        }
        
        // Mark that we're waiting for a direct Claude response
        updateProjectState(for: project) { state in
            state.isWaitingForResponse = true
        }
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
                    
                    // APNS will deliver responses automatically - no polling needed
                    
                    // ALWAYS keep loading state active - wait for APNS delivery
                    // All responses come through APNS for cross-device sync
                    print("⏳ Keeping loading state active until APNS delivers Claude's response")
                    
                case .failure(let error):
                    // Always clear loading state on error
                    self.updateProjectState(for: project) { state in
                        state.messageTimeout?.invalidate()
                        state.messageTimeout = nil
                        state.isLoading = false
                        state.isWaitingForResponse = false
                    }
                    self.isLoading = false
                    self.isWaitingForClaudeResponse = false
                    self.handleHTTPError(error)
                }
            }
        }
    }
    
    // MARK: - Message Queue Management
    
    private func queueMessage(_ text: String, for project: Project, attachments: [AttachmentData]) {
        // FEATURE FLAG: Queue system disabled
        guard FeatureFlags.shouldUseQueueSystem else {
            FeatureFlags.logFeatureDisabled("queueMessage", reason: "Queue system disabled by feature flag")
            return
        }
        updateProjectState(for: project) { state in
            // Check if this project's queue is full
            if state.messageQueue.count >= maxQueueSize {
                print("📦 Message queue for project \(project.name) is full (\(maxQueueSize) messages) - dropping oldest message")
                state.messageQueue.removeFirst()
            }
            
            // Add message to this project's queue
            state.messageQueue.append((text: text, attachments: attachments))
            let queueCount = state.messageQueue.count
            print("📦 Queued message for \(project.name) (\(queueCount)/\(maxQueueSize)): \(String(text.prefix(50)))...")
        }
        
        // Sync published queue properties for current project
        if project.path == currentProject?.path {
            if FeatureFlags.showQueueUI {
                let count = projectStates[project.path]?.messageQueue.count ?? 0
                logger.debug("Queue sync after add: \(project.name) has \(count) messages queued", category: .queue)
                queuedMessageCount = count
                hasQueuedMessages = !(projectStates[project.path]?.messageQueue.isEmpty ?? true)
            } else {
                // Queue UI disabled - always show 0
                queuedMessageCount = 0
                hasQueuedMessages = false
            }
        }
        
        // Show queued message in UI immediately (local-first UX)
        let queuedMessage = Message(
            content: text,
            sender: .user,
            type: .text,
            attachments: attachments
        )
        
        messages.append(queuedMessage)
        
        // Message added to UI state (persistence handled separately)
        
        // Save queued message to local database immediately (pending queue processing)
        if let sessionId = currentSessionId {
            persistenceService.appendMessage(queuedMessage, to: project.path, sessionId: sessionId, project: project)
            print("💾 Saved queued message with session ID: \(sessionId)")
        } else {
            pendingUserMessages.append(queuedMessage)
            print("💾 Added queued message to pending list (no session ID yet)")
        }
        
        print("📝 Message queued - will send when current request completes")
    }
    
    private func processMessageQueue() {
        // FEATURE FLAG: Queue processing disabled
        guard FeatureFlags.enableQueueProcessing else {
            FeatureFlags.logFeatureDisabled("processMessageQueue", reason: "Queue processing disabled by feature flag")
            return
        }
        // Process queue for the current project only
        guard let project = currentProject else { return }
        
        let projectState = projectStates[project.path]
        let isProcessing = projectState?.isProcessingQueue ?? false
        let hasMessages = !(projectState?.messageQueue.isEmpty ?? true)
        let isWaitingForResponse = projectState?.isWaitingForResponse ?? false
        
        guard !isProcessing && hasMessages && !isWaitingForResponse else { return }
        
        updateProjectState(for: project) { state in
            state.isProcessingQueue = true
        }
        
        let queueCount = projectState?.messageQueue.count ?? 0
        print("🚀 Processing message queue for \(project.name) (\(queueCount) messages)")
        
        // Get and remove the next message from queue
        var nextMessage: (text: String, attachments: [AttachmentData])?
        updateProjectState(for: project) { state in
            nextMessage = state.messageQueue.isEmpty ? nil : state.messageQueue.removeFirst()
        }
        
        // Sync published queue properties for current project after removing from queue
        if project.path == currentProject?.path {
            if FeatureFlags.showQueueUI {
                let count = projectStates[project.path]?.messageQueue.count ?? 0
                logger.debug("Queue sync after remove: \(project.name) has \(count) messages queued", category: .queue)
                queuedMessageCount = count
                hasQueuedMessages = !(projectStates[project.path]?.messageQueue.isEmpty ?? true)
            } else {
                // Queue UI disabled - always show 0
                queuedMessageCount = 0
                hasQueuedMessages = false
            }
        }
        
        if let nextMessage = nextMessage {
            print("📤 Sending queued message: \(String(nextMessage.text.prefix(50)))...")
            
            // Process the queued message
            sendMessageDirect(nextMessage.text, for: project, attachments: nextMessage.attachments)
        }
        
        updateProjectState(for: project) { state in
            state.isProcessingQueue = false
        }
        
        // Update published properties after processing
        if project.path == currentProject?.path {
            let count = projectStates[project.path]?.messageQueue.count ?? 0
            logger.debug("Final queue sync after processing: \(project.name) has \(count) messages queued", category: .queue)
            queuedMessageCount = count
            hasQueuedMessages = !(projectStates[project.path]?.messageQueue.isEmpty ?? true)
        }
        
        // Continue processing if there are more messages in this project's queue
        let remainingCount = projectStates[project.path]?.messageQueue.count ?? 0
        if remainingCount > 0 {
            print("📦 \(remainingCount) messages remaining in queue for \(project.name)")
        }
    }
    
    private func sendMessageDirect(_ text: String, for project: Project, attachments: [AttachmentData]) {
        // This is the original sendMessage logic without queueing
        print("📤 Sending queued message directly: \(String(text.prefix(50)))...")
        
        // Prepare message content with attachments
        var messageContent = text
        if !attachments.isEmpty {
            messageContent += "\n\n[Attachments: \(attachments.count) file(s)]"
            for attachment in attachments {
                messageContent += "\n- \(attachment.name) (\(attachment.type))"
            }
        }
        
        // Create the command with project context
        let command = "Working in project: \(project.path)\n\n\(messageContent)"
        
        // Set loading state for THIS project  
        loadingStateCoordinator.startChatLoading(for: project.path, timeout: 300.0)
        
        updateProjectState(for: project) { state in
            state.isLoading = true
            state.isWaitingForResponse = true
        }
        // isLoading will be updated via setupLoadingStateSync()
        isWaitingForClaudeResponse = true
        startLoadingTimeout(for: project)
        updateLoadingMessage()
        
        // Use project-specific session ID if we have one, otherwise send without session ID
        let sessionIdToUse = getSessionId(for: project)
        
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
                    
                    // APNS will deliver responses automatically - no polling needed
                    
                    // ALWAYS keep loading state active - wait for APNS delivery
                    print("⏳ Keeping loading state active until APNS delivers Claude's response (queued message)")
                    
                case .failure(let error):
                    // Clear loading state on error
                    self.updateProjectState(for: project) { state in
                        state.messageTimeout?.invalidate()
                        state.messageTimeout = nil
                        state.isLoading = false
                        state.isWaitingForResponse = false
                    }
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
                if let project = currentProject, activeSession == nil {
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
        // Messages are delivered via APNS to maintain single source of truth
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
        
        // Message added to UI state (persistence handled separately)
        
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
        // THE ONE FLOW: Messages are saved by PushNotificationService when they arrive
        // This function handles edge cases like unsent user messages or pending messages
        
        // Save pending user messages - they'll be matched with session ID when response arrives
        if !pendingUserMessages.isEmpty {
            print("📌 Keeping \(pendingUserMessages.count) pending messages for project: \(project.path)")
            // Keep messages in memory until we get a session ID from Claude
            // They're already shown in the UI, just waiting for proper persistence
        }
        
        guard !messages.isEmpty else {
            print("📝 No messages to save for project \(project.name)")
            return
        }
        
        // Use consolidated session ID method
        let sessionId = getSessionId(for: project)
        
        if let sessionId = sessionId {
            // Messages should already be saved via THE ONE FLOW
            // Just log for debugging
            print("📝 Messages already persisted for project \(project.name) with session: \(sessionId)")
        } else {
            // No session ID yet - this happens when user leaves before Claude responds
            print("⚠️ No session ID available yet for project \(project.name)")
            print("📝 Local-first pattern: Messages will be associated when session ID arrives via APNS")
            
            // Local-first pattern: Messages are already in UI and will be saved when session ID arrives
            // No need for complex pending message coordination
        }
    }
    
    // Clear session completely - used when user taps "Clear Chat"
    func clearSession() {
        // Clear all messages
        messages.removeAll()
        
        // Clear any pending messages that haven't been saved
        pendingUserMessages.removeAll()
        
        // Clear session ID
        currentSessionId = nil
        
        // Clear project session storage
        if let project = currentProject {
            projectSessionIds.removeValue(forKey: project.path)
        }
        
        // Clear any active session
        activeSession = nil
        
        // Clear loading states
        isLoading = false
        isWaitingForClaudeResponse = false
        progressInfo = nil
        
        // Clear project state timers if we have a project
        if let project = currentProject {
            updateProjectState(for: project) { state in
                state.cancelTimers()
                state.isLoading = false
                state.progressInfo = nil
                state.isWaitingForResponse = false
            }
        }
        
        print("🧹 Session cleared completely")
    }
    
    func loadMessages(for project: Project, sessionId: String) {
        // Clear any pending messages when switching projects
        if currentProject?.path != project.path && !pendingUserMessages.isEmpty {
            print("⚠️ Clearing \(pendingUserMessages.count) pending messages due to project switch")
            pendingUserMessages.removeAll()
        }
        
        // Update current project reference
        currentProject = project
        currentSessionId = sessionId
        
        // Sync published queue properties for new current project
        if FeatureFlags.showQueueUI {
            let count = projectStates[project.path]?.messageQueue.count ?? 0
            logger.debug("Queue sync on project switch: \(project.name) has \(count) messages queued", category: .queue)
            queuedMessageCount = count
            hasQueuedMessages = !(projectStates[project.path]?.messageQueue.isEmpty ?? true)
        } else {
            // Queue UI disabled - always show 0
            queuedMessageCount = 0
            hasQueuedMessages = false
        }
        
        // Store the session ID for this project
        projectSessionIds[project.path] = sessionId
        
        // Notify push notification service about the active project
        PushNotificationService.shared.setActiveProject(project, sessionId: sessionId)
        
        // WhatsApp/iMessage pattern: Load local conversation only
        print("📖 Loading conversation from local database...")
        let localMessages = persistenceService.loadMessages(for: project.path, sessionId: sessionId)
        self.messages = localMessages
        
        // Messages loaded from persistence to UI state
        
        print("✅ Loaded \(self.messages.count) messages for \(project.name) (local-only)")
        
        // Clear loading state after successful message loading (especially for pull-to-refresh)
        clearLoadingState(for: project.path)
        
        // APNS-based delivery: No polling resumption needed
        // Push notifications will automatically deliver any pending Claude responses
        
        // Messages loaded directly from MessagePersistenceService
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
        // Auto-save is now handled per project when needed
        // Each project can have its own auto-save timer if required
    }
    
    private func startLoadingTimeout(for project: Project) {
        updateProjectState(for: project) { state in
            state.loadingTimeout?.invalidate()
            // 5 minute timeout as a safety net for stuck states only
            state.loadingTimeout = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                // Check if this project is still loading
                if self.projectStates[project.path]?.isLoading == true {
                    print("⏰ Loading state timeout for project \(project.name) - forcing clear after 5 minutes (safety net)")
                    
                    // Clear state for this project
                    self.updateProjectState(for: project) { state in
                        state.isLoading = false
                        state.progressInfo = nil
                        state.isWaitingForResponse = false
                        state.loadingTimeout = nil
                        state.messageTimeout?.invalidate()
                        state.messageTimeout = nil
                    }
                    
                    // Update global state if this is the current project
                    if self.currentProject?.path == project.path {
                        self.isLoading = false
                        self.progressInfo = nil
                        self.isWaitingForClaudeResponse = false
                    }
                }
            }
        }
    }
    
    private func setupNotificationListeners() {
        // Listen for Claude responses received via APNS (includes fresh session info)
        NotificationCenter.default.publisher(for: .claudeResponseReceived)
            .sink { [weak self] notification in
                self?.handleClaudeResponseNotification(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleClaudeResponseNotification(_ notification: Notification) {
        print("🎯 === CHATVIEWMODEL: APNS NOTIFICATION RECEIVED ===")
        
        // Extract and validate notification payload
        guard let (message, sessionId, project) = extractNotificationPayload(notification) else {
            debugInvalidNotification(notification)
            return
        }
        
        // Check if this is a fresh session
        let isFreshSession = notification.userInfo?["isFreshSession"] as? Bool ?? false
        
        // Log notification details
        logNotificationDetails(message: message, sessionId: sessionId, project: project)
        print("🆕 Fresh session: \(isFreshSession)")
        
        // Clear loading state if needed
        clearLoadingStateIfNeeded(for: project)
        
        // Only process if:
        // 1. Project-specific session IDs match
        // 2. We don't have a session yet (first message) and project matches
        let projectSessionId = getSessionId(for: project)
        if projectSessionId == sessionId || (projectSessionId == nil && project.path == currentProject?.path) {
            print("🎯 === PROCESSING CLAUDE RESPONSE ===")
            
            // Simple duplicate check using message IDs only (best practices)
            let existingMessageIds = Set(messages.map { $0.id })
            
            if existingMessageIds.contains(message.id) {
                print("🔸 Duplicate message detected (ID: \(message.id)) - skipping")
                return
            }
            
            // Handle fresh session setup if needed
            if isFreshSession && projectSessionId == nil {
                print("🆕 Setting up fresh session for project \(project.name)")
                handleFirstMessage(sessionId: sessionId)
                
                // Save any pending user messages
                let userMessagesToSave = messages.filter { $0.sender == .user }
                for msg in userMessagesToSave {
                    persistenceService.appendMessage(msg, to: project.path, sessionId: sessionId, project: project)
                    print("💾 Saved pending user message: \(String(msg.content.prefix(50)))...")
                }
                
                // Update session tracking using helper method
                setSessionId(sessionId, for: project)
            } else if projectSessionId == nil {
                handleFirstMessage(sessionId: sessionId)
            }
            
            // Add message to conversation
            addMessageToConversation(message)
            
            // Message saved locally via MessagePersistenceService
            
            print("🎯 === CLAUDE RESPONSE PROCESSING COMPLETED ===")
        } else {
            print("❌ === SESSION MISMATCH - IGNORING RESPONSE ===")
            print("❌ Expected session: \(projectSessionId ?? "nil")")
            print("❌ Received session: \(sessionId)")
            print("❌ Expected project: \(currentProject?.path ?? "nil")")
            print("❌ Received project: \(project.path)")
            
            // CRITICAL: Save the session ID for this project even though we're not viewing it
            // This ensures when user switches back, they have the correct session
            if projectSessionIds[project.path] == nil || projectSessionIds[project.path]?.starts(with: "pending-") == true {
                print("💾 Saving session ID \(sessionId) for project \(project.path) for later use")
                projectSessionIds[project.path] = sessionId
                
                // Messages are now persisted immediately, no delayed saving needed
            }
        }
    }
    
    // MARK: - Connection Handling (APNS-based)
    
    private func handleLostConnection() {
        isLoading = false
        progressInfo = nil
        isWaitingForClaudeResponse = false
        
        let errorMessage = Message(
            content: "Connection lost. Please try again.",
            sender: .assistant,
            type: .text
        )
        
        // Validate message before adding to prevent blank messages
        if MessageValidator.shouldDisplayMessage(errorMessage) {
            messages.append(errorMessage)
            
            // Also update project-specific storage
            if let project = currentProject {
            }
            
            print("💔 Connection lost - added error message")
        } else {
            print("🚫 Filtered blank connection lost message")
        }
    }
    
    private func updateLoadingMessage(for project: Project? = nil) {
        let funMessages = [
            "Pondering deeply",
            "Brain storming",
            "Crafting magic",
            "Cooking response",
            "Thinking hard",
            "Processing thoughts",
            "Computing answer",
            "Brewing wisdom",
            "Assembling ideas",
            "Consulting Claude",
            "Neurons firing",
            "Synapses sparking",
            "Mind melding",
            "Deep diving",
            "Bits flowing",
            "Gears turning",
            "Wheels spinning",
            "Hamsters running",
            "Coffee brewing",
            "Ideas percolating",
            "Thoughts marinating",
            "Wisdom loading",
            "Knowledge mining",
            "Data crunching",
            "Matrix calculating"
        ]
        
        let randomMessage = funMessages.randomElement() ?? "Working hard"
        let projectState = project.flatMap { projectStates[$0.path] }
        let elapsed = projectState.map { Date().timeIntervalSince($0.lastStatusCheckTime) } ?? 0
        
        let newProgressInfo = ProgressInfo(
            stage: randomMessage,
            progress: nil,
            message: randomMessage,
            startTime: Date(),
            duration: elapsed,
            tokenCount: 0,
            activity: randomMessage,
            canInterrupt: elapsed > 10
        )
        
        // Update project state if project provided
        if let project = project {
            updateProjectState(for: project) { state in
                state.progressInfo = newProgressInfo
                // Set persistent thinking info to survive app lifecycle changes
                state.persistentThinkingInfo = newProgressInfo
            }
        }
        
        // Update global state for UI
        progressInfo = newProgressInfo
    }
    
    // Removed handleCommandResponse - not needed without WebSocket
    
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
        guard let project = currentProject, activeSession == nil else { return }
        
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
        guard let project = currentProject else { return }
        
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
        
        // Message saved locally via MessagePersistenceService
        
        // Save conversation
        if let project = currentProject {
            saveMessages(for: project)
        }
    }
    
    // MARK: - Defensive Recovery Methods
    
    /// Automatically recover from stuck loading states
    private func recoverFromStuckLoadingState(for project: Project) {
        guard let state = projectStates[project.path] else { return }
        
        let loadingDuration = Date().timeIntervalSince(state.lastStatusCheckTime)
        if state.isLoading && loadingDuration > maxLoadingDuration {
            logger.warning("Auto-recovering from stuck loading state for project: \(project.name) (stuck for \(Int(loadingDuration))s)", category: .error)
            
            // Force clear all loading states
            updateProjectState(for: project) { state in
                state.isLoading = false
                state.isWaitingForResponse = false
                state.progressInfo = nil
                state.persistentThinkingInfo = nil
                state.cancelTimers()
            }
            
            // Clear global state if this is current project
            if project.path == currentProject?.path {
                isLoading = false
                progressInfo = nil
                isWaitingForClaudeResponse = false
            }
            
            // Clear from loading coordinator
            loadingStateCoordinator.stopProjectLoading(project.path)
            
            // Add error message to inform user
            let errorMessage = Message(
                content: "⚠️ The request timed out after 5 minutes. Please try again.",
                sender: .system,
                type: .error
            )
            messages.append(errorMessage)
        }
    }
    
    private func triggerAutoResponse(_ autoResponse: String) {
        logger.debug("Auto-response triggered: \(autoResponse)", category: .message)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + autoResponseManager.config.delayBetweenResponses) { [weak self] in
            guard let self = self, let project = self.currentProject else { return }
            self.sendMessage(autoResponse, for: project)
        }
    }
    
    private func handleErrorResponse(_ error: String?) {
        let errorMessage = Message(
            content: error ?? "Unknown error occurred",
            sender: .assistant,
            type: .text
        )
        
        // Validate message before adding to prevent blank messages
        if MessageValidator.shouldDisplayMessage(errorMessage) {
            messages.append(errorMessage)
            print("❌ ChatViewModel: Added error message to chat: \(error ?? "Unknown error")")
        } else {
            print("🚫 Filtered blank error message: \(error ?? "nil")")
        }
    }
    
    private func handleCommandError(_ error: AICLICompanionError) {
        // Clear state for current project
        if let project = currentProject {
            updateProjectState(for: project) { state in
                state.isLoading = false
                state.isWaitingForResponse = false
                state.progressInfo = nil
                state.messageTimeout?.invalidate()
                state.messageTimeout = nil
            }
        }
        
        // Clear timers for current project
        if let project = currentProject {
            updateProjectState(for: project) { state in
                state.messageTimeout?.invalidate()
                state.messageTimeout = nil
                state.isLoading = false
                state.isWaitingForResponse = false
                state.progressInfo = nil
            }
        }
        
        isLoading = false
        isWaitingForClaudeResponse = false
        progressInfo = nil
        
        let errorMessage = Message(
            content: "Error: \(error.localizedDescription)",
            sender: .assistant,
            type: .text
        )
        
        // Validate message before adding to prevent blank messages
        if MessageValidator.shouldDisplayMessage(errorMessage) {
            messages.append(errorMessage)
        } else {
            print("🚫 Filtered blank command error message: \(error.localizedDescription)")
        }
    }
    
    // MARK: - HTTP Event Handling (Simplified)
    // HTTP responses are handled directly in sendMessage completion handlers
    // No separate event listeners needed since HTTP is request-response based
    
    // WebSocket streaming handlers removed - HTTP responses are complete and immediate
    
    
    private func handleStreamingComplete(_ message: Message) {
        // Cancel timeout since we got a response
        if let project = currentProject {
            updateProjectState(for: project) { state in
                state.messageTimeout?.invalidate()
                state.messageTimeout = nil
            }
        }
        
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
        if let project = currentProject {
            updateProjectState(for: project) { state in
                state.messageTimeout?.invalidate()
                state.messageTimeout = nil
            }
        }
        
        // Extract and store Claude's session ID if different from current
        if let claudeSessionId = result.claudeSessionId ?? result.sessionId {
            if claudeSessionId != currentSessionId {
                print("🔄 ChatViewModel: Updating session ID from Claude: \(claudeSessionId) (was: \(currentSessionId ?? "nil"))")
                currentSessionId = claudeSessionId
                print("🔄 ChatViewModel: Session ID successfully set to: \(currentSessionId ?? "nil")")
                
                // Create session object for the UI if we have a current project and no active session
                if let project = currentProject, activeSession == nil {
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
                if let project = currentProject {
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
            if let project = currentProject {
                saveMessages(for: project)
            }
        }
        
        isLoading = false
        progressInfo = nil
    }
    
    private func handleAssistantMessage(_ assistantMsg: AssistantMessageResponse, messageId: String?) {
        // Cancel timeout since we got a response  
        if let project = currentProject {
            updateProjectState(for: project) { state in
                state.messageTimeout?.invalidate()
                state.messageTimeout = nil
            }
        }
        
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
            if let project = currentProject {
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
            
            // Also update project-specific storage
            if let project = currentProject {
            }
            
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
        
        // Message added to UI state (persistence handled separately)
        
        // Messages are already saved via append operations - no bulk save needed
    }
    
    // Removed activity helpers - no longer needed without streaming
    
    
    // MARK: - WhatsApp/iMessage Pattern: Simple Local Operations
    // No complex merging needed - messages are appended via APNS or user actions
    
    // MARK: - Message Persistence - Single Source of Truth
    
    // MARK: - Helper Methods for Claude Response Notification
    
    private func extractNotificationPayload(_ notification: Notification) -> (Message, String, Project)? {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? Message,
              let sessionId = userInfo["sessionId"] as? String,
              let project = userInfo["project"] as? Project else {
            return nil
        }
        return (message, sessionId, project)
    }
    
    private func debugInvalidNotification(_ notification: Notification) {
        print("⚠️ ChatViewModel: Invalid Claude response notification payload")
        if let keys = notification.userInfo?.keys {
            print("⚠️ userInfo keys: \(Array(keys))")
            // Debug - check what types the values are
            if let messageValue = notification.userInfo?["message"] {
                print("⚠️ message type: \(type(of: messageValue))")
            }
            if let sessionValue = notification.userInfo?["sessionId"] {
                print("⚠️ sessionId type: \(type(of: sessionValue))")
            }
            if let projectValue = notification.userInfo?["project"] {
                print("⚠️ project type: \(type(of: projectValue))")
            }
        } else {
            print("⚠️ userInfo is nil")
        }
    }
    
    private func logNotificationDetails(message: Message, sessionId: String, project: Project) {
        print("🎯 ChatViewModel: Claude response notification validated")
        print("🎯 Session ID: \(sessionId)")
        print("🎯 Current Session ID: \(currentSessionId ?? "nil")")
        print("🎯 Project: \(project.name) (\(project.path))")
        print("🎯 Current Project: \(currentProject?.name ?? "nil") (\(currentProject?.path ?? "nil"))")
        print("🎯 Message ID: \(message.id)")
        print("🎯 Message content preview: \(message.content.prefix(100))...")
        print("🎯 Current loading state: isLoading=\(isLoading), isWaiting=\(isWaitingForClaudeResponse)")
        print("🎯 Current message count: \(messages.count)")
    }
    
    private func clearLoadingStateIfNeeded(for project: Project) {
        // Clear loading state immediately when APNS delivers response for current project
        if project.path == currentProject?.path && projectStates[project.path]?.isLoading == true {
            print("📨 APNS delivered response for current project - clearing loading state")
            
            updateProjectState(for: project) { state in
                state.isLoading = false
                state.isWaitingForResponse = false
                state.progressInfo = nil
                // Clear persistent thinking info when Claude actually responds
                state.persistentThinkingInfo = nil
                state.cancelTimers()
            }
            
            isLoading = false
            isWaitingForClaudeResponse = false
            progressInfo = nil
            
            // Debug current queue state
            debugQueueState()
            
            // Process any queued messages for the current project
            if let project = currentProject,
               let queueCount = projectStates[project.path]?.messageQueue.count,
               queueCount > 0 {
                print("📦 Processing queued messages for \(project.name) (\(queueCount) in queue)")
                // Process queue immediately instead of with delay
                processMessageQueue()
            }
        }
    }
    
    private func handleFirstMessage(sessionId: String) {
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentSessionId = sessionId
            print("🔄 ChatViewModel: First message - setting session ID from Claude via APNS: \(sessionId)")
            
            // Save any pending user messages now that we have a session ID
            self.savePendingUserMessages(sessionId: sessionId)
            
            // Session management for new conversations
            if let project = self.currentProject {
                let session = ProjectSession(
                    sessionId: sessionId,
                    projectName: project.name,
                    projectPath: project.path,
                    status: "active",
                    startedAt: Date().ISO8601Format()
                )
                self.setActiveSession(session)
            }
        }
    }
    
    private func savePendingUserMessages(sessionId: String) {
        if !pendingUserMessages.isEmpty {
            print("💾 Saving \(pendingUserMessages.count) pending user messages with new session ID")
            for pendingMessage in pendingUserMessages {
                if let project = currentProject {
                    persistenceService.appendMessage(pendingMessage, to: project.path, sessionId: sessionId, project: project)
                    print("✅ Saved pending user message: \(String(pendingMessage.content.prefix(50)))...")
                }
            }
            // Clear pending messages after saving
            pendingUserMessages.removeAll()
        }
    }
    
    private func addMessageToConversation(_ message: Message) {
        // WhatsApp/iMessage pattern: Add message to conversation
        print("📝 Adding Claude response to conversation...")
        print("📝 Message content length: \(message.content.count) characters")
        print("📝 Message content preview: \(String(message.content.prefix(100)))...")
        
        // Validate message before adding to prevent blank messages
        guard MessageValidator.shouldDisplayMessage(message) else {
            print("🚫 Filtered blank message from conversation")
            return
        }
        
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("📝 Before append - messages count: \(self.messages.count)")
            self.messages.append(message)
            print("📝 After append - messages count: \(self.messages.count)")
            
            // Also update project-specific storage
            if let project = self.currentProject {
                print("📝 Updated project messages for \(project.name)")
            }
            
            print("✅ Added Claude response to chat (\(self.messages.count) total messages)")
            
            // DO NOT SAVE HERE - PushNotificationService already saved to persistence
            // This is THE ONE FLOW - message saved once by PushNotificationService
            print("📌 Message already saved by PushNotificationService - not duplicating")
            
            // Clear badge count
            #if os(iOS)
            UIApplication.shared.applicationIconBadgeNumber = 0
            #endif
        }
    }
    
    // MARK: - Session Management Helpers
    
    /// Get session ID for a specific project (single source of truth)
    private func getSessionId(for project: Project) -> String? {
        // Priority order:
        // 1. If this is the current project, use currentSessionId
        // 2. Otherwise, use project-specific session ID from projectSessionIds
        if currentProject?.path == project.path {
            return currentSessionId
        } else {
            let projectSessionId = projectSessionIds[project.path]
            // Filter out pending session IDs
            if let sessionId = projectSessionId, !sessionId.starts(with: "pending-") {
                return sessionId
            }
            return nil
        }
    }
    
    /// Set session ID for a specific project
    private func setSessionId(_ sessionId: String?, for project: Project) {
        // Update both global currentSessionId (if current project) and project-specific storage
        if currentProject?.path == project.path {
            currentSessionId = sessionId
        }
        
        if let sessionId = sessionId {
            projectSessionIds[project.path] = sessionId
        } else {
            projectSessionIds.removeValue(forKey: project.path)
        }
    }
    
    // MARK: - WhatsApp/iMessage Pattern: No Server Polling Needed
    // Push notifications deliver new messages automatically
    // Local database is the source of truth for conversations
}
