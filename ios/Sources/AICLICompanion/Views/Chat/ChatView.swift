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
    @ObservedObject private var statusManager = ProjectStatusManager.shared
    
    @State private var messageText = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var inputBarOffset: CGFloat = 0
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    @State private var showingStopConfirmation = false
    @State private var showingQueueStatus = false
    @State private var showingPlanningDashboard = false
    @State private var showingProjectCreation = false
    @State private var selectedMode: ChatMode = .normal // Will be loaded per project
    @State private var showingAutoReplySettings = false
    @StateObject private var autoReplyStore = AutoReplySettingsStore.shared
    
    // Removed complex scroll tracking - handled by ChatMessageList now
    
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
                
                
                // Auto-Reply Controls - Replace old auto-response with new system
                if let project = selectedProject {
                    AutoReplyStatusBar(
                        project: project,
                        onShowSettings: { showingAutoReplySettings = true }
                    )
                }
                
                // Workspace Mode Features
                if let project = selectedProject, project.type == "workspace" {
                    WorkspaceModeToolbar(
                        showingPlanningDashboard: $showingPlanningDashboard,
                        showingProjectCreation: $showingProjectCreation
                    )
                }
                
                // Queue Status Bar (always visible if there are queued messages)
                if let sessionId = viewModel.currentSessionId {
                    QueueStatusBar(sessionId: sessionId, showingDetails: $showingQueueStatus)
                        .padding(.horizontal)
                }
                
                // Message list
                Group {
                    if let project = selectedProject {
                        ChatMessageList(
                            messages: viewModel.messages,
                            isLoading: viewModel.isLoadingForProject(project.path),
                            progressInfo: viewModel.progressInfo,
                            isIPad: isIPad,
                            horizontalSizeClass: horizontalSizeClass,
                            colorScheme: colorScheme,
                            claudeStatus: statusManager.statusFor(project)
                        )
                    } else {
                        // Empty state when no project selected
                        Text("Select a project to start chatting")
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                }
                #if os(iOS)
                .refreshable {
                    // Pull-to-refresh: Load older messages or sync latest
                    print("🔄 User triggered pull-to-refresh")
                    
                    if let project = selectedProject {
                        // First, try to load older messages from persistence
                        let oldestMessageId = viewModel.messages.first?.id
                        
                        // Load older messages if available
                        await viewModel.loadOlderMessages(for: project, beforeMessageId: oldestMessageId)
                        
                        // Also sync any new messages that might have arrived
                        viewModel.syncNewMessagesIfNeeded(for: project)
                        
                        // Check server for any missed messages (in case APNS failed)
                        if let sessionId = viewModel.currentSessionId {
                            await viewModel.checkForMissedMessages(sessionId: sessionId, for: project)
                        }
                    }
                    
                    // Small haptic feedback for completion
                    #if os(iOS)
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    #endif
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
                    isSendBlocked: selectedProject.map { viewModel.shouldBlockSending(for: $0) } ?? true,
                    isProcessing: selectedProject.map { statusManager.statusFor($0).isProcessing } ?? false,
                    onStopProcessing: selectedProject != nil ? {
                        stopProcessing()
                    } : nil,
                    selectedMode: $selectedMode
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
                    HStack(spacing: 16) {
                        // Queue Status Button
                        if let sessionId = viewModel.currentSessionId {
                            Button(action: { showingQueueStatus.toggle() }) {
                                Image(systemName: "tray.2.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                            }
                        }
                        
                        // Existing menu
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
            } else {
                // iPhone toolbar - add queue button
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let sessionId = viewModel.currentSessionId {
                        Button(action: { showingQueueStatus.toggle() }) {
                            Image(systemName: "tray.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Colors.textSecondary(for: colorScheme))
                        }
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingQueueStatus) {
            if let sessionId = viewModel.currentSessionId {
                NavigationView {
                    QueueStatusView(sessionId: sessionId)
                        .navigationTitle("Message Queue")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingQueueStatus = false
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingPlanningDashboard) {
            NavigationView {
                PlanningValidationDashboard()
                    .navigationTitle("Planning Validation")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingPlanningDashboard = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingProjectCreation) {
            ProjectCreationWizard()
        }
        .sheet(isPresented: $showingAutoReplySettings) {
            if let project = selectedProject {
                let projectUUID = ProjectUUIDConverter.uuid(for: project)
                AutoReplySettingsView(
                    projectId: projectUUID,
                    projectName: project.name
                )
            }
        }
        .onAppear {
            // Ensure proper setup on view appearance
            if let project = selectedProject {
                // Mark messages as read when viewing the conversation
                MessagePersistenceService.shared.markAsRead(for: project.path)
                
                // Clear all notifications for this project immediately
                PushNotificationService.shared.clearProjectNotifications(project.path)
                
                // Load the saved mode for this project
                selectedMode = ChatMode.loadSavedMode(for: project.path)
                
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
                
                // Mark as read and clear notifications for new project
                MessagePersistenceService.shared.markAsRead(for: newProject.path)
                PushNotificationService.shared.clearProjectNotifications(newProject.path)
                
                // Load the saved mode for the new project
                selectedMode = ChatMode.loadSavedMode(for: newProject.path)
                
                // Update to new project (handles both initial and subsequent selections)
                viewModel.currentProject = newProject
                handleProjectChange()
            }
        }
        .onChange(of: selectedMode) { _, newMode in
            // Save the mode when it changes
            if let project = selectedProject {
                newMode.save(for: project.path)
            }
        }
        // Removed message count change handling - ChatMessageList handles auto-scroll now
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
        .alert("Stop Claude?", isPresented: $showingStopConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Stop Work", role: .destructive) {
                confirmStopProcessing()
            }
        } message: {
            Text("This will immediately stop Claude's current work and end your session. You'll need to start a new conversation.")
        }
    }
    
    // MARK: - Setup & Cleanup
    private func setupView() {
        guard let project = selectedProject else { return }
        
        print("🔷 ChatView: Setting up for project '\(project.name)'")
        
        // Store the current project path for FileContentService to use
        UserDefaults.standard.set(project.path, forKey: "currentProjectPath")
        print("🔷 ChatView: Stored project path for file access: \(project.path)")
        
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
        
        // Load the saved mode for this project
        selectedMode = ChatMode.loadSavedMode(for: project.path)
        print("🔄 ChatView: Loaded mode '\(selectedMode.displayName)' for project '\(project.name)'")
        
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
        
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if message is empty (unless we have attachments)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        
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
        viewModel.sendMessage(text, for: project, attachments: attachments, mode: selectedMode)
    }
    
    private func clearCurrentSession() {
        guard let project = selectedProject else { return }
        
        // Clear UI immediately for responsiveness
        viewModel.clearSession()
        
        // Do heavy cleanup truly async with background priority
        Task.detached(priority: .background) {
            // Get session ID on main thread
            let sessionId = await MainActor.run {
                aicliService.getSessionId(for: project.path)
            }
            
            // Kill the server session if it exists
            if let sessionId = sessionId {
                print("🔄 Clearing server session \(sessionId) for project \(project.name)")
                
                // Call kill session async (no APNS for clear)
                await MainActor.run {
                    viewModel.killSession(sessionId, for: project, sendNotification: false) { success in
                        if success {
                            print("✅ Server session cleared successfully")
                        } else {
                            print("⚠️ Failed to clear server session, continuing with local cleanup")
                        }
                    }
                }
            }
            
            // Permanently delete messages from CloudKit (hard delete)
            let cloudKitManager = await CloudKitSyncManager.shared
            if await cloudKitManager.iCloudAvailable {
                do {
                    print("☁️ Deleting all messages from CloudKit for project: \(project.path)")
                    try await cloudKitManager.deleteAllMessages(for: project.path)
                    print("☁️ Successfully deleted all CloudKit messages")
                } catch {
                    print("⚠️ Failed to delete CloudKit messages: \(error)")
                    // Continue with local cleanup even if CloudKit fails
                }
            }
            
            // Do all file I/O operations in background
            // Clear persisted messages and session data
            let persistenceService = MessagePersistenceService.shared
            persistenceService.clearMessages(for: project.path)
            
            // Clear saved chat mode for this project (reset to default)
            ChatMode.clearSavedMode(for: project.path)
            
            // Clear stored session ID on main thread
            await MainActor.run {
                aicliService.clearSessionId(for: project.path)
                // Reset mode to default after clearing
                selectedMode = ChatMode.loadSavedMode() // Load global default
            }
            
            // Clear notifications in background
            let pushService = PushNotificationService.shared
            pushService.clearProjectNotifications(project.path)
            pushService.clearProcessedMessagesForProject(project.path)
            
            print("🗑️ Cleared chat: messages, persistence, session ID, notifications, and processed IDs for project \(project.name)")
            
            // Notify on main thread
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .projectMessagesCleared,
                    object: nil,
                    userInfo: ["projectPath": project.path, "projectName": project.name]
                )
            }
        }
    }
    
    // MARK: - Stop Processing
    private func stopProcessing() {
        // Show confirmation dialog
        showingStopConfirmation = true
    }
    
    private func confirmStopProcessing() {
        guard let project = selectedProject else { return }
        
        print("⏹️ Stopping Claude processing for project: \(project.name)")
        
        // Get the current session ID for this project
        let sessionId = aicliService.getSessionId(for: project.path)
        
        guard let sessionId = sessionId else {
            print("⚠️ No active session to stop")
            return
        }
        
        // Call the kill endpoint
        viewModel.killSession(sessionId, for: project) { success in
            if success {
                print("✅ Successfully stopped Claude processing")
                
                // Clear the processing state
                statusManager.statusFor(project).reset()
                
                // Add a system message to show the session was terminated
                let terminationMessage = Message(
                    content: "⏹️ Session terminated by user",
                    sender: .assistant,
                    type: .text
                )
                viewModel.addSystemMessage(terminationMessage, for: project)
            } else {
                print("❌ Failed to stop Claude processing")
            }
        }
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
    
    // MARK: - Removed Scroll Management
    // All scroll management is now handled by ChatMessageList with simple iMessage-like behavior
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
