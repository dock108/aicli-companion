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
    @Environment(\.scenePhase) var scenePhase
    
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
                // Project header (only on iPhone, iPad uses navigation bar)
                if let project = selectedProject, !isIPad {
                    ProjectContextHeader(
                        project: project,
                        session: session,
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
                    projectPath: selectedProject?.path, // Pass project path for project-specific scroll storage
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
                    // Use isRefresh=true to merge instead of replace
                    if let project = selectedProject {
                        viewModel.loadMessages(for: project, isRefresh: true)
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
                    .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 20 : 16)
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
        .navigationTitle(selectedProject?.name ?? "Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(isIPad ? .inline : .large)
        #endif
        .toolbar {
            #if os(iOS)
            if isIPad {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            clearCurrentSession()
                        } label: {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                }
            }
            #endif
        }
        .onAppear {
            // Ensure proper setup on view appearance
            if let project = selectedProject {
                // Only setup if project is different or not yet set
                if viewModel.currentProject?.path != project.path {
                    viewModel.currentProject = project
                    handleProjectChange()
                } else {
                    // Project already set, just ensure view is ready
                    setupView()
                }
            }
        }
        .onDisappear {
            cleanupView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Check for new messages when app returns from background
            if newPhase == .active && oldPhase == .background {
                print("📱 App returning from background - checking for new messages")
                if let project = selectedProject {
                    // Sync only new messages that arrived while backgrounded
                    viewModel.syncNewMessagesIfNeeded(for: project)
                    // Scroll position will be preserved by ChatMessageList
                }
            }
        }
        .onChange(of: selectedProject) { oldProject, newProject in
            // Handle project changes including initial selection
            if let newProject = newProject {
                // Save messages for the old project if it's different
                if let oldProject = oldProject, oldProject.path != newProject.path {
                    viewModel.saveMessages(for: oldProject)
                }
                
                // Update to new project (handles both initial and subsequent selections)
                viewModel.currentProject = newProject
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
        
        // Set the current project in the view model
        viewModel.setCurrentProject(project)
        
        // Set up keyboard observers
        setupKeyboardObservers()
        
        // HTTP doesn't need separate listeners - responses are handled directly
        setupPermissionHandling()
        
        // Connect HTTP service if needed  
        print("🔗 ChatView: Connecting HTTP service for project '\(project.name)'")
        connectHTTPIfNeeded {
            print("🔗 ChatView: HTTP service connected for project '\(project.name)'")
            
            // Load messages from persistence
            viewModel.loadMessages(for: project)
            
            print("🔷 ChatView: Loaded \(viewModel.messages.count) messages")
            
            // Clear loading state now that messages are loaded
            viewModel.clearLoadingState(for: project.path)
            
            // WhatsApp/iMessage pattern: Messages loaded from local database only
            // Push notifications will deliver any new messages automatically
        }
    }
    
    private func cleanupView() {
        guard let project = selectedProject else { return }
        
        // Save messages
        viewModel.saveMessages(for: project)
        
        // Scroll position is now saved by ChatMessageList's onDisappear
        
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
        
        // Send message directly - sessions are managed by the server
        viewModel.sendMessage(text, for: project, attachments: attachments)
    }
    
    private func clearCurrentSession() {
        guard let project = selectedProject else { return }
        
        // HTTP doesn't need to send clearChat to server - sessions are managed by the server
        // Just clear the local messages
        
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
