import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
struct ChatView: View {
    // MARK: - Environment & State
    @EnvironmentObject var aicliService: AICLIService
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject private var viewModel = ChatViewModel.shared
    @StateObject private var sessionManager = ChatSessionManager.shared
    
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
                
                
                // FEATURE FLAG: Auto-response controls (currently hidden)
                if FeatureFlags.showAutoModeUI {
                    AutoResponseControls()
                }
                
                // Message list
                ChatMessageList(
                    messages: viewModel.messages,
                    isLoading: viewModel.isLoadingForProject(selectedProject?.path ?? ""),
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
                    // WhatsApp/iMessage pattern: Just reload local conversation
                    print("🔄 User triggered pull-to-refresh - reloading conversation")
                    
                    // Reload messages from local database (instant)
                    if let project = selectedProject, let sessionId = viewModel.currentSessionId {
                        viewModel.loadMessages(for: project, sessionId: sessionId)
                    }
                    
                    // Small delay for visual feedback
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                }
                #endif
                
                // FEATURE FLAG: Queue status indicator (currently hidden)
                if FeatureFlags.showQueueUI && viewModel.hasQueuedMessages {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundColor(Colors.accentWarning)
                        
                        Text("\(viewModel.queuedMessageCount) message\(viewModel.queuedMessageCount == 1 ? "" : "s") queued • Max \(viewModel.maxQueueSize)")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                        
                        Spacer()
                    }
                    .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
                    .padding(.vertical, 8)
                    .background(Colors.bgCard(for: colorScheme).opacity(0.8))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Input bar
                ChatInputBar(
                    messageText: $messageText,
                    isLoading: viewModel.isLoadingForProject(selectedProject?.path ?? ""),
                    isIPad: isIPad,
                    horizontalSizeClass: horizontalSizeClass,
                    colorScheme: colorScheme,
                    onSendMessage: { attachments in
                        sendMessage(with: attachments)
                    },
                    isSendBlocked: selectedProject.map { viewModel.shouldBlockSending(for: $0) } ?? true
                )
                .offset(y: inputBarOffset)
            }
            
            // Scroll to bottom FAB - Removed per user request
        }
        .copyConfirmationOverlay()
        .onAppear {
            viewModel.currentProject = selectedProject
            setupView()
        }
        .onDisappear {
            cleanupView()
        }
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
                    
                    // Clear loading state now that session is fully restored
                    self.viewModel.clearLoadingState(for: project.path)
                    
                    // WhatsApp/iMessage pattern: Messages loaded from local database only
                    // Push notifications will deliver any new messages automatically
                    
                case .failure(let error):
                    // No existing session, but check if we have saved messages for this project
                    print("ℹ️ No existing session (\(error.localizedDescription)), checking for saved conversations")
                    
                    // Clear any stale session data
                    self.viewModel.setActiveSession(nil)
                    self.viewModel.currentSessionId = nil
                    
                    // Clear any stuck loading state when no session exists
                    self.viewModel.clearLoadingState(for: project.path)
                    
                    // WhatsApp/iMessage pattern: Check if we have any saved conversations for this project
                    let persistenceService = MessagePersistenceService.shared
                    if let metadata = persistenceService.getSessionMetadata(for: project.path),
                       let sessionId = metadata.aicliSessionId {
                        print("🔄 ChatView: Found saved conversation with session \(sessionId), loading messages")
                        
                        // Load the saved conversation
                        self.viewModel.loadMessages(for: project, sessionId: sessionId)
                        
                        // Set the session ID for future messages
                        self.viewModel.currentSessionId = sessionId
                        
                        print("✅ ChatView: Loaded \(self.viewModel.messages.count) messages from saved conversation")
                        
                        // Clear loading state now that saved conversation is loaded
                        self.viewModel.clearLoadingState(for: project.path)
                    } else {
                        // Truly no conversation exists yet
                        print("ℹ️ ChatView: No saved conversation found for \(project.name)")
                        self.viewModel.messages.removeAll()
                        // Clear any stuck loading state when there's no conversation
                        self.viewModel.clearLoadingState(for: project.path)
                    }
                }
            }
        }
    }
    
    private func cleanupView() {
        guard let project = selectedProject else { return }
        
        // Save messages
        viewModel.saveMessages(for: project)
        
        // Stop polling (will resume if needed when returning)
        viewModel.onDisappear()
        
        // Clean up keyboard observers
        // swiftlint:disable:next notification_center_detachment
        NotificationCenter.default.removeObserver(self)
        
        // Note: Do NOT close session - let it continue in background
    }
    
    private func handleProjectChange() {
        guard let project = selectedProject else { return }
        
        print("🔄 ChatView: Project changed to '\(project.name)'")
        
        // The currentProject setter will handle saving old messages and loading new ones
        // Just update the currentProject and it will switch contexts
        viewModel.currentProject = project
        
        // Clear loading state for old project
        viewModel.isLoading = false  // Clear loading state
        viewModel.progressInfo = nil  // Clear progress info
        // Polling removed - using APNS delivery
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
        }
        
        // Use the new comprehensive clear function
        viewModel.clearSession()
        
        // Clear persisted messages and session data
        let persistenceService = MessagePersistenceService.shared
        persistenceService.clearMessages(for: project.path)
        
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
        print("   Current connection state: \(AICLIService.shared.isConnected)")
        
        if AICLIService.shared.isConnected {
            print("✅ ChatView: HTTP service already connected")
            completion()
            return
        }
        
        print("🔗 ChatView: Starting HTTP connection...")
        print("   aicliService instance: \(ObjectIdentifier(aicliService))")
        print("   AICLIService.shared instance: \(ObjectIdentifier(AICLIService.shared))")
        
        // Use the shared instance for connection to ensure consistency
        AICLIService.shared.connect(
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
}

// MARK: - Preview
@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat View") {
    ChatView(
        selectedProject: Project(name: "Test Project", path: "/test/path", type: "git"),
        session: nil,
        onSwitchProject: {}
    )
    .environmentObject(AICLIService.shared)
    .environmentObject(SettingsManager())
}
