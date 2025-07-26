import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 14.0, macOS 11.0, *)
struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var webSocketService = WebSocketService()
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    @State private var keyboardHeight: CGFloat = 0
    @State private var inputBarOffset: CGFloat = 0
    @State private var projectContext: String = ""
    @Environment(\.colorScheme) var colorScheme
    
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
                        .padding(.horizontal)
                        .padding(.bottom, 8)
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
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Colors.accentPrimaryEnd))
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(Typography.font(.caption))
                                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                                }
                                .padding()
                                .background(Colors.bgCard(for: colorScheme))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Colors.strokeLight, lineWidth: 1)
                                )
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { oldValue, newValue in
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
                        }) {
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
                        }
                        .disabled(messageText.isEmpty || isLoading)
                        .animation(.easeInOut(duration: 0.2), value: messageText.isEmpty)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
                .offset(y: inputBarOffset)
            }
        }
        .onAppear {
            loadProjectSession()
            connectWebSocket()
            setupKeyboardObservers()
            addWelcomeMessage()
            setupWebSocketListeners()
        }
        .onDisappear {
            webSocketService.disconnect()
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
            content: "🚀 Claude CLI started in **\(project.name)**\n\nYou can now interact with your project. I have access to all files in this directory and can help you with coding tasks, analysis, and more.\n\nType your first message to get started!",
            sender: .claude,
            type: .text
        )
        messages.append(welcomeMessage)
    }
    
    private func connectWebSocket() {
        // Connect using saved settings
        if let connection = settings.currentConnection,
           let wsURL = connection.wsURL {
            webSocketService.connect(to: wsURL, authToken: connection.authToken)
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
        
        // Send command to Claude CLI session
        sendClaudeCommand(messageCopy)
    }
    
    private func sendClaudeCommand(_ command: String) {
        guard let project = selectedProject else {
            isLoading = false
            return
        }
        
        // Create the command request for Claude CLI
        let claudeRequest = ClaudeCommandRequest(
            command: command,
            projectPath: project.path,
            sessionId: session?.sessionId
        )
        
        // Send via WebSocket to Claude CLI session
        webSocketService.sendMessage(claudeRequest, type: .claudeCommand) { result in
            DispatchQueue.main.async {
                // Don't reset loading here - wait for actual response
                
                switch result {
                case .success(let message):
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
                                sender: .claude,
                                type: .text
                            )
                            self.messages.append(responseMessage)
                        }
                        
                    case .streamData(let streamData):
                        // Handle streaming data
                        if streamData.streamType == "text", let text = streamData.content.text {
                            let responseMessage = Message(
                                content: text,
                                sender: .claude,
                                type: .text
                            )
                            self.messages.append(responseMessage)
                        }
                        
                    case .error(let errorResponse):
                        // Handle error messages
                        let errorMessage = Message(
                            content: "Error: \(errorResponse.message)",
                            sender: .claude,
                            type: .text
                        )
                        self.messages.append(errorMessage)
                        
                    default:
                        // Log unexpected message types for debugging
                        print("Unhandled message type: \(message.type)")
                    }
                    
                case .failure(let error):
                    // Add error message
                    let errorMessage = Message(
                        content: "Error: \(error.localizedDescription)",
                        sender: .claude,
                        type: .text
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }
    
    private func setupWebSocketListeners() {
        // Listen for all WebSocket messages, not just responses to our commands
        webSocketService.onMessage = { [weak self] message in
            guard let self else { return }
            
            DispatchQueue.main.async {
                
                print("WebSocket global listener - message type: \(message.type)")
                
                switch message.data {
                case .assistantMessage(let assistantResponse):
                    self.isLoading = false
                    let textContent = assistantResponse.content
                        .compactMap { block in
                            block.type == "text" ? block.text : nil
                        }
                        .joined(separator: "\n\n")
                    
                    if !textContent.isEmpty {
                        let responseMessage = Message(
                            content: textContent,
                            sender: .claude,
                            type: .text
                        )
                        self.messages.append(responseMessage)
                    }
                    
                case .streamData(let streamData):
                    self.isLoading = false
                    if streamData.streamType == "text", let text = streamData.content.text {
                        let responseMessage = Message(
                            content: text,
                            sender: .claude,
                            type: .text
                        )
                        self.messages.append(responseMessage)
                    }
                    
                case .error(let errorResponse):
                    self.isLoading = false
                    let errorMessage = Message(
                        content: "Error: \(errorResponse.message)",
                        sender: .claude,
                        type: .text
                    )
                    self.messages.append(errorMessage)
                    
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
    .environmentObject(ClaudeCodeService())
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
    .environmentObject(ClaudeCodeService())
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
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
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
        guard let session = session else { return "Claude CLI ready" }
        
        switch session.status {
        case "running": return "Claude CLI active"
        case "starting": return "Starting Claude CLI..."
        case "stopped": return "Claude CLI stopped"
        default: return "Unknown status"
        }
    }
}