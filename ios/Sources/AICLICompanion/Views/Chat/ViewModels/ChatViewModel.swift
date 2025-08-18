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
    private let messageManager = ChatMessageManager()
    private let projectStateManager = ChatProjectStateManager()
    private let loadingStateManager = ChatLoadingStateManager()
    private let queueManager = ChatMessageQueueManager()
    private var notificationHandler: ChatNotificationHandler!
    
    // MARK: - Dependencies
    private let persistenceService: MessagePersistenceService
    private let aicliService: AICLIService
    private let hapticManager: HapticManager
    private let performanceMonitor: PerformanceMonitor
    
    // MARK: - Published Properties (Delegated to Managers)
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var progressInfo: ProgressInfo?
    @Published var currentProject: Project?
    
    // MARK: - Computed Properties
    var hasQueuedMessages: Bool { queueManager.hasQueuedMessages }
    var queuedMessageCount: Int { queueManager.queuedMessageCount }
    var maxQueueSize: Int { queueManager.maxQueueSize }
    
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
    func loadMessages(for project: Project) {
        messageManager.loadMessages(for: project)
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
        return projectStateManager.isLoadingForProject(projectPath)
    }
    
    func shouldBlockSending(for project: Project) -> Bool {
        return projectStateManager.shouldBlockSending(for: project)
    }
    
    // MARK: Loading State Operations
    func clearLoadingState(for projectPath: String) {
        loadingStateManager.clearLoadingState(for: projectPath)
    }
    
    // MARK: Message Sending
    func sendMessage(_ text: String, for project: Project, attachments: [AttachmentData] = []) {
        print("📤 ChatViewModel: Sending message for project: \(project.name)")
        
        // Set loading state
        loadingStateManager.setLoading(true, for: project.path)
        
        // Create user message with request ID for tracking
        let requestId = UUID().uuidString
        let userMessage = Message(
            content: text,
            sender: .user,
            type: .text,
            requestId: requestId
        )
        
        // Add to UI immediately (local-first pattern)
        messageManager.appendMessage(userMessage, for: project)
        
        // Send to server
        aicliService.sendMessage(
            text,
            projectPath: project.path,
            attachments: attachments
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    print("✅ ChatViewModel: Message accepted by server")
                    // Message was accepted and will be delivered via APNS
                    // Keep loading state active to show Claude is working
                    // The APNS handler will clear it when the response arrives
                    
                case .failure(let error):
                    print("❌ ChatViewModel: Failed to send message: \(error)")
                    self.loadingStateManager.setLoading(false, for: project.path)
                    
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
