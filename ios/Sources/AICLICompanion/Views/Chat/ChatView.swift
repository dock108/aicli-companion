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
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var sessionManager = ChatSessionManager.shared
    @ObservedObject private var webSocketService = WebSocketService.shared
    
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
        
        // Create view model with dependencies
        let aicliService = AICLIService()
        let settings = SettingsManager()
        self._viewModel = StateObject(wrappedValue: ChatViewModel(aicliService: aicliService, settings: settings))
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
                        onSwitchProject: onSwitchProject
                    )
                    .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
                    .padding(.vertical, 12)
                }
                
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
                
                // Input bar
                ChatInputBar(
                    messageText: $messageText,
                    isLoading: viewModel.isLoading,
                    isIPad: isIPad,
                    horizontalSizeClass: horizontalSizeClass,
                    colorScheme: colorScheme,
                    onSendMessage: sendMessage
                )
                .offset(y: inputBarOffset)
            }
        }
        .copyConfirmationOverlay()
        .onAppear {
            setupView()
        }
        .onDisappear {
            cleanupView()
        }
        .onChange(of: selectedProject?.path) { oldPath, newPath in
            if let oldPath = oldPath, let newPath = newPath, oldPath != newPath {
                handleProjectChange()
            }
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
        
        // Set up WebSocket listeners
        viewModel.setupWebSocketListeners()
        setupPermissionHandling()
        
        // Connect WebSocket if needed
        connectWebSocketIfNeeded {
            // Handle session after connection
            self.sessionManager.handleSessionAfterConnection(
                for: project,
                passedSession: self.session
            ) { result in
                switch result {
                case .success(let session):
                    self.viewModel.setActiveSession(session)
                    self.viewModel.loadMessages(for: project, sessionId: session.sessionId)
                    
                case .failure:
                    // No existing session, user can start one when ready
                    print("ℹ️ No existing session, waiting for user to start")
                }
            }
        }
    }
    
    private func cleanupView() {
        guard let project = selectedProject else { return }
        
        // Save messages
        viewModel.saveMessages(for: project)
        
        // Close session if needed
        sessionManager.closeSession()
        
        // Clean up keyboard observers
        NotificationCenter.default.removeObserver(self)
    }
    
    private func handleProjectChange() {
        guard let project = selectedProject else { return }
        
        print("🔄 ChatView: Project changed to '\(project.name)'")
        
        // Save current messages
        if let oldProject = selectedProject {
            viewModel.saveMessages(for: oldProject)
        }
        
        // Clear current state
        viewModel.messages.removeAll()
        viewModel.activeSession = nil
        messageText = ""
        
        // Set up for new project
        setupView()
    }
    
    // MARK: - Actions
    private func sendMessage() {
        guard let project = selectedProject else { return }
        
        let text = messageText
        messageText = ""
        
        // Check if we have a session
        if viewModel.activeSession == nil {
            // Start a new session first
            if let connection = settings.currentConnection {
                viewModel.startSession(for: project, connection: connection)
            } else {
                let errorMessage = Message(
                    content: "❌ No server connection configured",
                    sender: .assistant,
                    type: .text
                )
                viewModel.messages.append(errorMessage)
            }
            return
        }
        
        viewModel.sendMessage(text, for: project)
    }
    
    // MARK: - WebSocket Connection
    private func connectWebSocketIfNeeded(completion: @escaping () -> Void) {
        guard let connection = settings.currentConnection,
              let wsURL = connection.wsURL else {
            completion()
            return
        }
        
        if webSocketService.isConnected {
            completion()
            return
        }
        
        // Set up connection observer
        var connectionObserver: AnyCancellable?
        connectionObserver = webSocketService.$isConnected
            .dropFirst()
            .first(where: { $0 })
            .sink { connected in
                if connected {
                    completion()
                    connectionObserver?.cancel()
                }
            }
        
        webSocketService.connect(to: wsURL, authToken: connection.authToken)
    }
    
    // MARK: - Permission Handling
    private func setupPermissionHandling() {
        webSocketService.setMessageHandler(for: .permissionRequest) { message in
            
            if case .permissionRequest(let request) = message.data {
                Task { @MainActor in
                    self.permissionRequest = request
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    private func handlePermissionResponse(_ response: String) {
        guard let request = permissionRequest,
              let session = viewModel.activeSession else { return }
        
        webSocketService.respondToPermission(
            sessionId: session.sessionId,
            response: response,
            remember: false
        )
        
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
    
    // MARK: - Scroll Management
    private func checkIfNearBottom(_ position: CGFloat) {
        let threshold: CGFloat = 100
        let maxScrollPosition = max(0, contentHeight - scrollViewHeight)
        isNearBottom = (maxScrollPosition - position) <= threshold
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