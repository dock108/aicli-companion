import SwiftUI
import Combine

/// Main chat view model using composition pattern
/// Coordinates between specialized managers for better maintainability
@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Singleton
    static let shared = ChatViewModel()
    
    // MARK: - Managers (Composition Pattern)
    internal let messageManager = ChatMessageManager()
    private let projectStateManager = ChatProjectStateManager()
    private let loadingStateManager = ChatLoadingStateManager()
    private let queueManager = ChatMessageQueueManager()
    private var notificationHandler: ChatNotificationHandler!
    
    // MARK: - Dependencies
    private let persistenceService: MessagePersistenceService
    internal let aicliService: AICLIService
    internal let hapticManager: HapticManager
    private let performanceMonitor: PerformanceMonitor
    
    // MARK: - Combine
    internal var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published Properties (Delegated to Managers)
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var progressInfo: ProgressInfo?
    @Published var currentProject: Project?
    
    // MARK: - Computed Properties
    var hasQueuedMessages: Bool { queueManager.hasQueuedMessages }
    var queuedMessageCount: Int { queueManager.queuedMessageCount }
    var maxQueueSize: Int { queueManager.maxQueueSize }
    
    /// Get the current session ID from the latest message
    var currentSessionId: String? {
        // Find the most recent message with a session ID
        for message in messages.reversed() {
            if let sessionId = message.metadata?.sessionId, !sessionId.isEmpty {
                return sessionId
            }
        }
        return nil
    }
    
    // MARK: - Initialization
    private init() {
        self.persistenceService = MessagePersistenceService.shared
        self.aicliService = AICLIService.shared
        self.hapticManager = HapticManager.shared
        self.performanceMonitor = PerformanceMonitor.shared
        
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Initialize notification handler
        notificationHandler = ChatNotificationHandler(
            messageManager: messageManager,
            loadingStateManager: loadingStateManager,
            projectStateManager: projectStateManager
        )
        
        // Bind manager properties to published properties
        messageManager.$messages
            .assign(to: &$messages)
        
        loadingStateManager.$isLoading
            .assign(to: &$isLoading)
        
        loadingStateManager.$progressInfo
            .assign(to: &$progressInfo)
        
        projectStateManager.$currentProject
            .assign(to: &$currentProject)
    }
    
    // MARK: - Public API (Delegates to Managers)
    
    // MARK: Message Operations
    func loadMessages(for project: Project, isRefresh: Bool = false) {
        messageManager.loadMessages(for: project, isRefresh: isRefresh)
    }
    
    func saveMessages(for project: Project) {
        messageManager.saveMessages(for: project)
    }
    
    func syncNewMessagesIfNeeded(for project: Project) {
        messageManager.syncNewMessagesIfNeeded(for: project)
    }
    
    func clearSession() {
        messageManager.clearMessages()
    }
    
    // MARK: Project Operations
    func setCurrentProject(_ project: Project?) {
        projectStateManager.setCurrentProject(project)
    }
    
    func isLoadingForProject(_ projectPath: String) -> Bool {
        return projectStateManager.projectStates[projectPath]?.isLoading ?? false
    }
    
    func shouldBlockSending(for project: Project) -> Bool {
        return projectStateManager.shouldBlockSending(for: project)
    }
    
    // MARK: Loading State Operations
    func clearLoadingState(for projectPath: String) {
        loadingStateManager.clearLoadingState(for: projectPath)
        
        // Also clear waiting state in project state
        projectStateManager.updateProjectState(for: projectPath) { state in
            state.isWaitingForResponse = false
        }
    }
    
    // MARK: Message Sending
    func sendMessage(_ text: String, for project: Project, attachments: [AttachmentData] = []) {
        print("📤 ChatViewModel: Sending message for project: \(project.name)")
        
        // Set loading state and waiting for response
        loadingStateManager.setLoading(true, for: project.path)
        loadingStateManager.setWaitingForResponse(true)
        
        // Also update project state to block sending
        projectStateManager.updateProjectState(for: project.path) { state in
            state.isWaitingForResponse = true
        }
        
        // Set processing state for stop button visibility
        print("🔴 Setting processing state for project: \(project.path)")
        ProjectStatusManager.shared.statusFor(project).isProcessing = true
        print("✅ Processing state set. isProcessing = \(ProjectStatusManager.shared.statusFor(project).isProcessing)")
        
        // Create user message with request ID for tracking
        let requestId = UUID().uuidString
        let userMessage = Message(
            content: text,
            sender: .user,
            type: .text,
            requestId: requestId,
            attachments: attachments  // Include attachments in the local message
        )
        
        // Add to UI immediately (local-first pattern)
        messageManager.appendMessage(userMessage, for: project)
        
        // Send to server
        aicliService.sendMessage(
            text,
            projectPath: project.path,
            attachments: attachments
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch result {
                case .success:
                    print("✅ ChatViewModel: Message accepted by server")
                    // Message was accepted and will be delivered via APNS
                    // Keep loading state active to show Claude is working
                    // The APNS handler will clear it when the response arrives
                    
                case .failure(let error):
                    print("❌ ChatViewModel: Failed to send message: \(error)")
                    self.loadingStateManager.setLoading(false, for: project.path)
                    self.loadingStateManager.setWaitingForResponse(false)
                    
                    // Clear waiting state in project state
                    self.projectStateManager.updateProjectState(for: project.path) { state in
                        state.isWaitingForResponse = false
                    }
                    
                    // Clear processing state for stop button
                    ProjectStatusManager.shared.statusFor(project).isProcessing = false
                    
                    // Add error message to UI
                    let errorMessage = Message(
                        content: "Failed to send message: \(error.localizedDescription)",
                        sender: .system,
                        type: .error
                    )
                    self.messageManager.appendMessage(errorMessage, for: project)
                }
            }
        }
    }
    
    // MARK: Kill Session
    func killSession(_ sessionId: String, for project: Project, sendNotification: Bool = true, completion: @escaping (Bool) -> Void) {
        print("⏹️ ChatViewModel: Killing session \(sessionId) for project: \(project.name)")
        
        // Call the kill endpoint via AICLIService
        aicliService.killSession(sessionId, projectPath: project.path, sendNotification: sendNotification) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    print("✅ ChatViewModel: Session killed successfully")
                    
                    // Clear loading states
                    self?.loadingStateManager.setLoading(false, for: project.path)
                    self?.loadingStateManager.setWaitingForResponse(false)
                    
                    // Update project state
                    self?.projectStateManager.updateProjectState(for: project.path) { state in
                        state.isWaitingForResponse = false
                        state.isLoading = false
                    }
                    
                    // Clear processing state for stop button
                    ProjectStatusManager.shared.statusFor(project).isProcessing = false
                    
                    completion(true)
                    
                case .failure(let error):
                    print("❌ ChatViewModel: Failed to kill session: \(error)")
                    completion(false)
                }
            }
        }
    }
    
    // MARK: Add System Message
    func addSystemMessage(_ message: Message, for project: Project) {
        messageManager.appendMessage(message, for: project)
    }
    
    // MARK: Lifecycle
    func onDisappear() {
        print("👋 ChatViewModel: View disappeared")
        // Cleanup operations if needed
    }
    
    // MARK: - Internal Helper Methods
    
    private func debugCurrentState() {
        print("🔍 ChatViewModel State Debug:")
        print("  - Current Project: \(currentProject?.name ?? "nil")")
        print("  - Messages Count: \(messages.count)")
        print("  - Is Loading: \(isLoading)")
        print("  - Queued Messages: \(queuedMessageCount)")
    }
}

// MARK: - Computed Properties for UI
extension ChatViewModel {
    var isWaitingForClaudeResponse: Bool {
        loadingStateManager.isWaitingForClaudeResponse
    }
}

// MARK: - Legacy Compatibility
// TODO: Remove this once all references are updated
extension ChatViewModel {
    // Add any legacy method signatures that ChatView might still be calling
}
