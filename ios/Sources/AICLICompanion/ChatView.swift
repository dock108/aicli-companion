import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 14.0, macOS 11.0, *)
struct ChatView: View {
    @EnvironmentObject var aicliService: AICLIService
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var webSocketService = WebSocketService()
    @StateObject private var persistenceService = MessagePersistenceService.shared
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var progressInfo: ProgressInfo?
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    @State private var keyboardHeight: CGFloat = 0
    @State private var inputBarOffset: CGFloat = 0
    @State private var projectContext: String = ""
    @State private var activeSession: ProjectSession?
    @State private var sessionError: String?
    @State private var messageTimeout: Timer?
    @State private var connectionStateTimer: Timer?
    @State private var autoSaveTimer: Timer?
    @State private var isRestoring = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    // Project information passed from parent view
    let selectedProject: Project?
    let session: ProjectSession?
    let onSwitchProject: () -> Void

    var body: some View {
        ZStack {
            // Pure charcoal background
            Colors.bgBase(for: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Project context header
                if let project = selectedProject {
                    ProjectContextHeader(project: project, session: session, onSwitchProject: onSwitchProject)
                        .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
                        .padding(.vertical, 12)
                }
                
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity
                                    ))
                                    .animation(.easeOut(duration: 0.12), value: messages.count)
                            }
                            
                            if isLoading {
                                LoadingIndicator(progressInfo: progressInfo, colorScheme: colorScheme)
                            }
                        }
                        .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input area with translucent blur
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(colorScheme == .dark ? Colors.divider : Colors.dividerLight)
                        .frame(height: 1)
                    
                    HStack(spacing: 12) {
                        // Message input field with terminal styling
                        HStack(spacing: 0) {
                            TextField("Type a message...", text: $messageText, axis: .vertical)
                                .font(Typography.font(.body))
                                .foregroundColor(Colors.textPrimary(for: colorScheme))
                                .textFieldStyle(.plain)
                                .lineLimit(1...4)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .onSubmit {
                                    sendMessage()
                                }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Colors.strokeLight, lineWidth: 1)
                                )
                        )
                        
                        // Send button
                        Button(action: {
                            sendMessage()
                        }, label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: messageText.isEmpty
                                            ? [Colors.textSecondary(for: colorScheme)]
                                            : Colors.accentPrimary(for: colorScheme),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        })
                        .disabled(messageText.isEmpty || isLoading)
                        .animation(.easeInOut(duration: 0.2), value: messageText.isEmpty)
                    }
                    .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                }
                .offset(y: inputBarOffset)
            }
        }
        .onAppear {
            loadProjectSession()
            connectWebSocket()
            setupKeyboardObservers()
            setupWebSocketListeners()
            restoreSessionIfNeeded()
            startAutoSave()
        }
        .onDisappear {
            // Only cleanup timers, don't disconnect WebSocket
            // Connection will be managed by app lifecycle
            messageTimeout?.invalidate()
            connectionStateTimer?.invalidate()
            autoSaveTimer?.invalidate()
            // Save messages before leaving
            saveMessagesToStorage()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadProjectSession() {
        guard let project = selectedProject else { return }
        
        // In a real implementation, we would fetch the active session from the server
        // For now, we'll create a mock session to show the project context
        projectContext = "Working in project: \(project.name)\nPath: \(project.path)"
    }
    
    private func addWelcomeMessage() {
        guard let project = selectedProject else { return }
        
        let welcomeMessage = Message(
            content: "🚀 AICLI starting in **\(project.name)**...\n\nPlease wait while I set up the session.",
            sender: .assistant,
            type: .text
        )
        messages.append(welcomeMessage)
    }
    
    private func startClaudeSession() {
        guard let project = selectedProject else { return }
        guard let connection = settings.currentConnection else {
            sessionError = "No server connection configured"
            return
        }
        
        addWelcomeMessage()
        isLoading = true
        
        // Start AICLI session for this project
        aicliService.startProjectSession(project: project, connection: connection) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.progressInfo = nil
                
                switch result {
                case .success(let session):
                    self.activeSession = session
                    self.sessionError = nil
                    
                    // Update welcome message
                    if let lastMessage = self.messages.last, lastMessage.sender == .assistant {
                        self.messages.removeLast()
                    }
                    
                    let successMessage = Message(
                        content: "✅ AICLI ready in **\(project.name)**\n\nYou can now interact with your project. I have access to all files in this directory and can help you with coding tasks, analysis, and more.\n\nType your first message to get started!",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(successMessage)
                    
                case .failure(let error):
                    self.sessionError = error.localizedDescription
                    
                    // Update welcome message with error
                    if let lastMessage = self.messages.last, lastMessage.sender == .assistant {
                        self.messages.removeLast()
                    }
                    
                    let errorMessage = Message(
                        content: "❌ Failed to start AICLI\n\n\(error.localizedDescription)\n\nPlease check that:\n1. The server is running\n2. AICLI is installed\n3. The project path is accessible",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }
    
    private func connectWebSocket() {
        // Connect using saved settings
        if let connection = settings.currentConnection,
           let wsURL = connection.wsURL {
            webSocketService.connect(to: wsURL, authToken: connection.authToken)
            
            // Monitor connection state
            startConnectionStateMonitoring()
        }
    }
    
    private func startConnectionStateMonitoring() {
        connectionStateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            // Check if we're stuck in loading state while disconnected
            if self.isLoading && !self.webSocketService.isConnected {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.progressInfo = nil
                    
                    let connectionLostMessage = Message(
                        content: "🔌 Connection lost. Attempting to reconnect...\n\nPlease wait while we try to restore the connection to the server.",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(connectionLostMessage)
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Add user message
        let userMessage = Message(
            content: messageText,
            sender: .user,
            type: .text
        )
        messages.append(userMessage)
        
        // Clear input
        let messageCopy = messageText
        messageText = ""
        isLoading = true
        
        // Send command to AICLI session
        sendAICLICommand(messageCopy)
    }
    
    private func sendAICLICommand(_ command: String) {
        guard let project = selectedProject else {
            isLoading = false
            return
        }
        
        // Check if we have an active session
        guard let session = activeSession else {
            isLoading = false
            let errorMessage = Message(
                content: "❌ No active AICLI session. Please wait for the session to start or try reloading the chat.",
                sender: .assistant,
                type: .text
            )
            messages.append(errorMessage)
            
            // Try to start a session again
            startClaudeSession()
            return
        }
        
        // Create the command request for AICLI
        let claudeRequest = AICLICommandRequest(
            command: command,
            projectPath: project.path,
            sessionId: session.sessionId
        )
        
        print("📤 Sending command to server: \(command)")
        print("   Session ID: \(session.sessionId)")
        print("   Project path: \(project.path)")
        
        // Set a timeout to clear loading state if no response comes
        messageTimeout?.invalidate()
        messageTimeout = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.isLoading = false
                let timeoutMessage = Message(
                    content: "⏰ Request timed out. The connection may have been lost or the server is taking too long to respond. Please try again.",
                    sender: .assistant,
                    type: .text
                )
                self.messages.append(timeoutMessage)
            }
        }
        
        // Send via WebSocket to AICLI session
        webSocketService.sendMessage(claudeRequest, type: .aicliCommand) { result in
            DispatchQueue.main.async {
                // Don't reset loading here - wait for actual response
                
                switch result {
                case .success(let message):
                    // Clear timeout since we got a response
                    self.messageTimeout?.invalidate()
                    self.isLoading = false
                    self.progressInfo = nil
                    
                    // Debug: Log message type
                    print("Received WebSocket message type: \(message.type)")
                    
                    // Handle different message types
                    switch message.data {
                    case .assistantMessage(let assistantResponse):
                        // Extract text content from content blocks
                        let textContent = assistantResponse.content
                            .compactMap { block in
                                block.type == "text" ? block.text : nil
                            }
                            .joined(separator: "\n\n")
                        
                        if !textContent.isEmpty {
                            let responseMessage = Message(
                                content: textContent,
                                sender: .assistant,
                                type: .text
                            )
                            self.messages.append(responseMessage)
                            // Save after receiving response
                            self.saveMessagesToStorage()
                        }
                        
                    case .streamData(let streamData):
                        // Handle streaming data
                        if streamData.streamType == "text", let text = streamData.content.text {
                            let responseMessage = Message(
                                content: text,
                                sender: .assistant,
                                type: .text
                            )
                            self.messages.append(responseMessage)
                            // Save after receiving response
                            self.saveMessagesToStorage()
                        }
                        
                    case .error(let errorResponse):
                        // Handle error messages
                        let errorMessage = Message(
                            content: "Error: \(errorResponse.message)",
                            sender: .assistant,
                            type: .text
                        )
                        self.messages.append(errorMessage)
                        
                        // If session not found, clear our active session
                        if errorResponse.code == "SESSION_NOT_FOUND" {
                            self.activeSession = nil
                            // Try to start a new session
                            self.startClaudeSession()
                        }
                        
                    default:
                        // Log unexpected message types for debugging
                        print("Unhandled message type: \(message.type)")
                    }
                    
                case .failure(let error):
                    // Clear timeout and loading state
                    self.messageTimeout?.invalidate()
                    self.isLoading = false
                    self.progressInfo = nil
                    
                    // Add error message
                    let errorMessage = Message(
                        content: "Error: \(error.localizedDescription)",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }
    
    private func setupWebSocketListeners() {
        // Listen for all WebSocket messages, not just responses to our commands
        webSocketService.onMessage = { [self] message in
            DispatchQueue.main.async {
                print("WebSocket global listener - message type: \(message.type)")
                
                // Clear timeout for any incoming message that indicates activity
                self.messageTimeout?.invalidate()
                
                switch message.data {
                case .assistantMessage(let assistantResponse):
                    self.isLoading = false
                    self.progressInfo = nil
                    
                    let textContent = assistantResponse.content
                        .compactMap { block in
                            block.type == "text" ? block.text : nil
                        }
                        .joined(separator: "\n\n")
                    
                    if !textContent.isEmpty {
                        let responseMessage = Message(
                            content: textContent,
                            sender: .assistant,
                            type: .text
                        )
                        self.messages.append(responseMessage)
                    }
                    
                case .streamData(let streamData):
                    self.isLoading = false
                    self.progressInfo = nil
                    
                    if streamData.streamType == "text", let text = streamData.content.text {
                        let responseMessage = Message(
                            content: text,
                            sender: .assistant,
                            type: .text
                        )
                        self.messages.append(responseMessage)
                    }
                    
                case .error(let errorResponse):
                    self.isLoading = false
                    self.progressInfo = nil
                    let errorMessage = Message(
                        content: "Error: \(errorResponse.message)",
                        sender: .assistant,
                        type: .text
                    )
                    self.messages.append(errorMessage)
                    
                case .progress(let progressResponse):
                    // Update progress info while keeping loading state
                    self.progressInfo = ProgressInfo(from: progressResponse)
                    
                default:
                    print("Global listener - unhandled message type: \(message.type)")
                }
            }
        }
    }
    
    private func setupKeyboardObservers() {
        #if os(iOS)
        // Keyboard appearance with overshoot animation
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.keyboardHeight = keyboardFrame.height
                    self.inputBarOffset = -8 // 8pt overshoot
                }
                
                // Spring back to normal position
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.1)) {
                    self.inputBarOffset = 0
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.keyboardHeight = 0
                self.inputBarOffset = 0
            }
        }
        #endif
    }
    
    // MARK: - Session Persistence
    
    private func restoreSessionIfNeeded() {
        guard let project = selectedProject else { return }
        
        // Check if we should restore from a previous session
        if let metadata = persistenceService.getSessionMetadata(for: project.path),
           let sessionId = metadata.aicliSessionId {
            isRestoring = true
            
            // Load previous messages
            let restoredMessages = persistenceService.loadMessages(for: project.path, sessionId: sessionId)
            if !restoredMessages.isEmpty {
                messages = restoredMessages
                
                // Add restoration notice
                let restorationNotice = Message(
                    content: "📂 Restored \(restoredMessages.count) messages from previous session",
                    sender: .assistant,
                    type: .text
                )
                messages.append(restorationNotice)
            }
            
            // Set the session ID in WebSocket service
            webSocketService.setActiveSession(sessionId)
            
            isRestoring = false
        } else {
            // Start fresh session
            startClaudeSession()
        }
    }
    
    private func startAutoSave() {
        // Set up auto-save timer (every 30 seconds)
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.saveMessagesToStorage()
        }
    }
    
    private func saveMessagesToStorage() {
        guard let project = selectedProject,
              !messages.isEmpty else { return }
        
        // Get current session ID from WebSocket service or active session
        let sessionId = webSocketService.getActiveSession() ?? activeSession?.sessionId ?? UUID().uuidString
        
        // Save messages
        persistenceService.saveMessages(
            for: project.path,
            messages: messages,
            sessionId: sessionId,
            project: project
        )
        
        print("💾 Auto-saved \(messages.count) messages for project \(project.name)")
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat View - Light") {
    ChatView(
        selectedProject: Project(name: "sample-project", path: "/path/to/project", type: "folder"),
        session: ProjectSession(
            sessionId: "test-session",
            projectName: "sample-project",
            projectPath: "/path/to/project",
            status: "running",
            startedAt: Date().ISO8601Format()
        ),
        onSwitchProject: { print("Switch project") }
    )
    .environmentObject(AICLIService())
    .environmentObject(SettingsManager())
    .preferredColorScheme(.light)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat View - Dark") {
    ChatView(
        selectedProject: Project(name: "sample-project", path: "/path/to/project", type: "folder"),
        session: ProjectSession(
            sessionId: "test-session",
            projectName: "sample-project",
            projectPath: "/path/to/project",
            status: "running",
            startedAt: Date().ISO8601Format()
        ),
        onSwitchProject: { print("Switch project") }
    )
    .environmentObject(AICLIService())
    .environmentObject(SettingsManager())
    .preferredColorScheme(.dark)
}

// MARK: - Project Context Header

@available(iOS 14.0, macOS 11.0, *)
struct ProjectContextHeader: View {
    let project: Project
    let session: ProjectSession?
    let onSwitchProject: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Project icon
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundColor(Colors.accentPrimaryEnd)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Colors.accentPrimaryEnd.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(Typography.font(.heading3))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    
                    Text(statusText)
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            
            Spacer()
            
            // Switch project button
            Button(action: onSwitchProject) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                    Text("Switch")
                        .font(Typography.font(.caption))
                }
                .foregroundColor(Colors.accentPrimaryEnd)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Colors.accentPrimaryEnd.opacity(0.1))
                )
            }
            
            // Session info button
            Button(action: {
                // TODO: Show session details
            }, label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            })
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Colors.bgCard(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.strokeLight, lineWidth: 1)
                )
        )
    }
    
    private var statusColor: Color {
        guard let session = session else { return .orange }
        
        switch session.status {
        case "running": return .green
        case "starting": return .orange
        case "stopped": return .red
        default: return .gray
        }
    }
    
    private var statusText: String {
        guard let session = session else { return "AICLI ready" }
        
        switch session.status {
        case "running": return "AICLI active"
        case "starting": return "Starting AICLI..."
        case "stopped": return "AICLI stopped"
        default: return "Unknown status"
        }
    }
}
// MARK: - Loading Indicator

@available(iOS 14.0, macOS 11.0, *)
struct LoadingIndicator: View {
    let progressInfo: ProgressInfo?
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Progress indicator
                if let progressInfo = progressInfo, let progress = progressInfo.progress {
                    // Show determinate progress
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: Colors.accentPrimaryEnd))
                        .frame(width: 60)
                } else {
                    // Show indeterminate spinner
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Colors.accentPrimaryEnd))
                        .scaleEffect(0.8)
                }
                
                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    Text(progressInfo?.message ?? "Thinking...")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .lineLimit(2)
                    
                    if let progressInfo = progressInfo {
                        HStack(spacing: 4) {
                            Text("Stage:")
                                .font(Typography.font(.caption))
                                .foregroundColor(Colors.textSecondary(for: colorScheme))
                            
                            Text(progressInfo.stage)
                                .font(Typography.font(.caption))
                                .foregroundColor(Colors.accentPrimaryEnd)
                                .fontWeight(.medium)
                        }
                    }
                }
                
                Spacer()
                
                // Progress percentage
                if let progressInfo = progressInfo, let progress = progressInfo.progress {
                    Text("\(Int(progress * 100))%")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Colors.bgCard(for: colorScheme))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Colors.strokeLight, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: progressInfo?.progress)
    }
}
