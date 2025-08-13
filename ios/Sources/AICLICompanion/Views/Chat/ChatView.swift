import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
struct ChatView: View {
    // MARK: - Environment & State
    @EnvironmentObject var aicliService: HTTPAICLIService
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sessionManager = ChatSessionManager.shared
    @StateObject private var queueManager = MessageQueueManager.shared
    
    @State private var messageText = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var inputBarOffset: CGFloat = 0
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    
    // Smart scroll tracking
    @State private var isNearBottom: Bool = true
    @State private var lastScrollPosition: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var unreadMessageCount: Int = 0
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Project information
    let selectedProject: Project?
    let session: ProjectSession?
    let onSwitchProject: () -> Void
    
    private var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    // MARK: - Initialization
    init(selectedProject: Project?, session: ProjectSession?, onSwitchProject: @escaping () -> Void) {
        self.selectedProject = selectedProject
        self.session = session
        self.onSwitchProject = onSwitchProject
        
        // ViewModule will be created lazily when environment objects are available
        // We'll initialize it in body where we have access to environment objects
        self._viewModel = StateObject(wrappedValue: ChatViewModel(aicliService: HTTPAICLIService.shared, settings: SettingsManager.shared))
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Background
            Colors.bgBase(for: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Project header
                if let project = selectedProject {
                    ProjectContextHeader(
                        project: project,
                        session: sessionManager.activeSession ?? session,
                        messageCount: viewModel.messages.count,
                        onSwitchProject: onSwitchProject,
                        onClearSession: clearCurrentSession
                    )
                }
                
                // Message queue indicator
                MessageQueueIndicator(
                    queuedMessageCount: queueManager.queuedMessageCount,
                    isReceivingQueued: queueManager.isReceivingQueued,
                    oldestQueuedTimestamp: queueManager.oldestQueuedTimestamp
                )
                
                // Auto-response controls
                AutoResponseControls()
                
                // Message list
                ChatMessageList(
                    messages: viewModel.messages,
                    isLoading: viewModel.isLoading,
                    progressInfo: viewModel.progressInfo,
                    isIPad: isIPad,
                    horizontalSizeClass: horizontalSizeClass,
                    colorScheme: colorScheme,
                    isNearBottom: $isNearBottom,
                    lastScrollPosition: $lastScrollPosition,
                    scrollViewHeight: $scrollViewHeight,
                    contentHeight: $contentHeight,
                    onScrollPositionChanged: checkIfNearBottom
                )
                #if os(iOS)
                .refreshable {
                    // Simple server poll on pull-to-refresh (best practices)
                    print("🔄 User triggered pull-to-refresh")
                    viewModel.pollServerForMessages()
                    
                    // Small delay for visual feedback
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                #endif
                
                // Input bar
                ChatInputBar(
                    messageText: $messageText,
                    isLoading: viewModel.isLoading,
                    isIPad: isIPad,
                    horizontalSizeClass: horizontalSizeClass,
                    colorScheme: colorScheme,
                    onSendMessage: { attachments in
                        sendMessage(with: attachments)
                    }
                )
                .offset(y: inputBarOffset)
            }
            
            // Scroll to bottom FAB
            ScrollToBottomButton(
                isVisible: !isNearBottom && !viewModel.messages.isEmpty,
                unreadCount: unreadMessageCount,
                onTap: scrollToBottom
            )
        }
        .copyConfirmationOverlay()
        .onAppear {
            viewModel.currentProject = selectedProject
            setupView()
        }
        .onDisappear {
            cleanupView()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshMessagesOnActivation()
        }
        #endif
        .onChange(of: selectedProject?.path) { oldPath, newPath in
            if let oldPath = oldPath, let newPath = newPath, oldPath != newPath {
                // Save messages for the old project before switching
                if let currentProject = viewModel.currentProject {
                    viewModel.saveMessages(for: currentProject)
                }
                
                // Update to new project
                viewModel.currentProject = selectedProject
                handleProjectChange()
            }
        }
        .onChange(of: viewModel.messages.count) { oldCount, newCount in
            handleMessageCountChange(oldCount: oldCount, newCount: newCount)
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            if let request = permissionRequest {
                ForEach(request.options, id: \.self) { option in
                    Button(option) {
                        handlePermissionResponse(option)
                    }
                }
            }
        } message: {
            if let request = permissionRequest {
                Text(request.prompt)
            }
        }
    }
    
    // MARK: - Setup & Cleanup
    private func setupView() {
        guard let project = selectedProject else { return }
        
        print("🔷 ChatView: Setting up for project '\(project.name)'")
        
        // Set up keyboard observers
        setupKeyboardObservers()
        
        // HTTP doesn't need separate listeners - responses are handled directly
        setupPermissionHandling()
        
        // Connect HTTP service if needed  
        print("🔗 ChatView: Connecting HTTP service for project '\(project.name)'")
        connectHTTPIfNeeded {
            print("🔗 ChatView: HTTP service connected, handling session for project '\(project.name)'")
            // Handle session after connection
            self.sessionManager.handleSessionAfterConnection(
                for: project,
                passedSession: self.session
            ) { result in
                switch result {
                case .success(let session):
                    print("🔷 ChatView: Session restored: \(session.sessionId)")
                    
                    // Set the active session and current session ID for message persistence
                    self.viewModel.setActiveSession(session)
                    self.viewModel.currentSessionId = session.sessionId
                    
                    // Load messages from persistence using the session ID
                    self.viewModel.loadMessages(for: project, sessionId: session.sessionId)
                    
                    print("🔷 ChatView: Loaded \(self.viewModel.messages.count) messages for restored session")
                    
                    // Poll server for any new messages (best practices approach)
                    self.viewModel.pollServerForMessages()
                    
                    // Sync messages from CloudKit
                    Task {
                        await self.viewModel.syncMessages(for: project)
                    }
                    
                    // Simple server poll for any new messages
                    self.viewModel.pollServerForMessages()
                    
                case .failure(let error):
                    // No existing session, user can start one when ready
                    print("ℹ️ No existing session (\(error.localizedDescription)), waiting for user to start")
                    
                    // Clear any stale session data
                    self.viewModel.setActiveSession(nil)
                    self.viewModel.currentSessionId = nil
                    self.viewModel.messages.removeAll()
                    
                    // Check for pending messages that might have been saved without a session ID
                    if let pendingMessages = BackgroundSessionCoordinator.shared.retrievePendingMessages(for: project.path) {
                        print("🔄 ChatView: Found \(pendingMessages.count) pending messages for project")
                        self.viewModel.messages = pendingMessages
                    }
                    
                    // Still sync from CloudKit even without a session
                    Task {
                        await self.viewModel.syncMessages(for: project)
                    }
                }
            }
        }
    }
    
    private func cleanupView() {
        guard let project = selectedProject else { return }
        
        // Save messages
        viewModel.saveMessages(for: project)
        
        // Clean up keyboard observers
        // swiftlint:disable:next notification_center_detachment
        NotificationCenter.default.removeObserver(self)
        
        // Note: Do NOT close session - let it continue in background
    }
    
    private func handleProjectChange() {
        guard let project = selectedProject else { return }
        
        print("🔄 ChatView: Project changed to '\(project.name)'")
        
        // Note: At this point, selectedProject is already the NEW project
        // We can't save messages for the old project here because we don't have a reference to it
        // Messages should have been saved in cleanupView() when leaving the old project
        
        // Clear current state
        viewModel.messages.removeAll()
        viewModel.activeSession = nil
        viewModel.currentSessionId = nil  // Clear Claude's session ID to prevent cross-project contamination
        messageText = ""
        
        // Set up for new project
        setupView()
    }
    
    // MARK: - Actions
    private func sendMessage(with attachments: [AttachmentData] = []) {
        guard let project = selectedProject else { return }
        
        let text = messageText
        messageText = ""
        
        // Check if we have a server connection
        guard settings.currentConnection != nil else {
            let errorMessage = Message(
                content: "❌ No server connection configured",
                sender: .assistant,
                type: .text
            )
            viewModel.messages.append(errorMessage)
            return
        }
        
        // Send message directly - let Claude handle session creation
        // For fresh chats: currentSessionId will be nil
        // For continued chats: currentSessionId will have Claude's session ID
        viewModel.sendMessage(text, for: project, attachments: attachments)
    }
    
    private func clearCurrentSession() {
        guard let project = selectedProject else { return }
        
        // HTTP doesn't need to send clearChat to server - sessions are stateless
        // Just clear the local session ID so next message starts fresh
        if let currentSessionId = viewModel.currentSessionId {
            print("🗑️ Clearing local session: \(currentSessionId)")
            viewModel.currentSessionId = nil
        }
        
        // Clear messages from UI
        viewModel.messages.removeAll()
        
        // Clear active session
        viewModel.setActiveSession(nil)
        
        // Clear persisted messages and session data
        let persistenceService = MessagePersistenceService.shared
        persistenceService.clearMessages(for: project.path)
        
        // Clear current session ID - next message will be a fresh chat
        viewModel.currentSessionId = nil
        
        // Sync clear operation to CloudKit for cross-device consistency
        Task {
            do {
                try await CloudKitSyncManager.shared.clearChat(for: project.path)
                print("✅ Chat cleared in CloudKit for project: \(project.path)")
            } catch {
                print("⚠️ Failed to clear chat in CloudKit: \(error)")
                // Continue anyway - local clear succeeded
            }
        }
        
        // HTTP doesn't maintain active sessions - they're request-scoped
    }
    
    // MARK: - HTTP Connection
    private func connectHTTPIfNeeded(completion: @escaping () -> Void) {
        guard let connection = settings.currentConnection else {
            print("⚠️ ChatView: No connection configuration available")
            completion()
            return
        }
        
        let httpURL = "http://\(connection.address):\(connection.port)"
        print("🔗 ChatView: Checking HTTP connection to \(httpURL)")
        print("   Current connection state: \(HTTPAICLIService.shared.isConnected)")
        
        if HTTPAICLIService.shared.isConnected {
            print("✅ ChatView: HTTP service already connected")
            completion()
            return
        }
        
        print("🔗 ChatView: Starting HTTP connection...")
        print("   aicliService instance: \(ObjectIdentifier(aicliService))")
        print("   HTTPAICLIService.shared instance: \(ObjectIdentifier(HTTPAICLIService.shared))")
        
        // Use the shared instance for connection to ensure consistency
        HTTPAICLIService.shared.connect(
            to: connection.address,
            port: connection.port,
            authToken: connection.authToken
        ) { result in
            switch result {
            case .success:
                print("✅ ChatView: HTTP connection established, proceeding with session handling")
                completion()
            case .failure(let error):
                print("❌ ChatView: HTTP connection failed: \(error)")
                // completion() is not called on failure - the UI will show connection error
            }
        }
    }
    
    // MARK: - Permission Handling
    private func setupPermissionHandling() {
        // Permission handling is now handled within HTTP responses
        // No separate WebSocket message handlers needed
    }
    
    private func handlePermissionResponse(_ response: String) {
        // HTTP-based permission handling would be integrated into the chat flow
        // For now, dismiss the permission alert
        showingPermissionAlert = false
        permissionRequest = nil
    }
    
    // MARK: - Keyboard Handling
    private func setupKeyboardObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleKeyboardShow(notification)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { notification in
            handleKeyboardHide(notification)
        }
        #endif
    }
    
    private func handleKeyboardShow(_ notification: Notification) {
        #if os(iOS)
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = keyboardFrame.height
        }
        #endif
    }
    
    private func handleKeyboardHide(_ notification: Notification) {
        #if os(iOS)
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = 0
        }
        #endif
    }
    
    // MARK: - Session Welcome Messages
    
    private func addRestoredSessionWelcome(for project: Project) {
        let welcomeMessage = Message(
            content: "✅ Session restored for **\(project.name)**\n\nYou can continue working on your project. I have access to all files in this directory.\n\nWhat can I help you with today?",
            sender: .assistant,
            type: .text
        )
        viewModel.messages.append(welcomeMessage)
    }
    
    // MARK: - Scroll Management
    private func checkIfNearBottom(_ position: CGFloat) {
        let threshold: CGFloat = 100
        let maxScrollPosition = max(0, contentHeight - scrollViewHeight)
        let wasNearBottom = isNearBottom
        isNearBottom = (maxScrollPosition - position) <= threshold
        
        // Reset unread count when user scrolls to bottom
        if isNearBottom && !wasNearBottom {
            unreadMessageCount = 0
        }
    }
    
    private func scrollToBottom() {
        // Trigger scroll to bottom via a notification that ChatMessageList can listen to
        NotificationCenter.default.post(
            name: .scrollToBottom,
            object: nil
        )
        
        // Reset unread count
        unreadMessageCount = 0
        
        // Update near bottom status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNearBottom = true
        }
    }
    
    private func handleMessageCountChange(oldCount: Int, newCount: Int) {
        // Only track new messages from assistant when user is not near bottom
        if newCount > oldCount, !isNearBottom {
            let newMessages = Array(viewModel.messages.suffix(newCount - oldCount))
            let assistantMessages = newMessages.filter { $0.sender == .assistant }
            unreadMessageCount += assistantMessages.count
        }
        
        // Reset count when switching projects or loading initial messages
        if oldCount == 0 {
            unreadMessageCount = 0
        }
    }
    
    
    private func refreshMessagesOnActivation() {
        // Simple server poll when app becomes active (best practices)
        print("🔄 ChatView: App became active - polling server")
        viewModel.pollServerForMessages()
        
        // Also sync from CloudKit when becoming active
        if let project = selectedProject {
            Task {
                await viewModel.syncMessages(for: project)
            }
        }
    }
}

// MARK: - Preview
@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat View") {
    ChatView(
        selectedProject: Project(name: "Test Project", path: "/test/path", type: "git"),
        session: nil,
        onSwitchProject: {}
    )
    .environmentObject(AICLIService())
    .environmentObject(SettingsManager())
}
