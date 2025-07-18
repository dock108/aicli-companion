import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @StateObject private var webSocketService = WebSocketService()
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var currentStreamingMessage: Message?
    @State private var activeSessionId: String?
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    
    var body: some View {
        VStack {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading || currentStreamingMessage != nil {
                            TypingIndicator()
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input area
            VStack {
                Divider()
                
                HStack {
                    TextField("Type a command or question...", text: $messageText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            sendMessage()
                        }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(messageText.isEmpty ? .gray : .blue)
                    }
                    .disabled(messageText.isEmpty || isLoading)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Clear Chat") {
                        messages.removeAll()
                    }
                    Button("CLI Mode") {
                        // TODO: Switch to CLI mode
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadChatHistory()
            setupWebSocketHandlers()
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            if let request = permissionRequest {
                ForEach(request.options, id: \.self) { option in
                    Button(option.uppercased()) {
                        respondToPermission(option)
                    }
                }
                Button("Cancel", role: .cancel) {
                    respondToPermission("n")
                }
            }
        } message: {
            if let request = permissionRequest {
                Text(request.prompt)
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = Message(
            id: UUID(),
            content: messageText,
            sender: .user,
            timestamp: Date(),
            type: .text
        )
        
        messages.append(userMessage)
        let prompt = messageText
        messageText = ""
        isLoading = true
        
        if let sessionId = activeSessionId {
            // Send to existing streaming session
            webSocketService.sendToStream(sessionId: sessionId, prompt: prompt)
            isLoading = false
        } else {
            // Start new streaming session
            webSocketService.startStream(prompt: prompt, workingDirectory: nil, sessionName: "Chat Session") { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let sessionId):
                        self.activeSessionId = sessionId
                        self.isLoading = false
                    case .failure(let error):
                        self.isLoading = false
                        let errorMessage = Message(
                            id: UUID(),
                            content: "Error: \(error.localizedDescription)",
                            sender: .system,
                            timestamp: Date(),
                            type: .error
                        )
                        self.messages.append(errorMessage)
                    }
                }
            }
        }
    }
    
    private func loadChatHistory() {
        // TODO: Load persisted chat history if needed
        messages = []
    }
    
    private func setupWebSocketHandlers() {
        // Handle streaming data
        webSocketService.setMessageHandler(for: .streamData) { [weak self] message in
            DispatchQueue.main.async {
                self?.handleStreamData(message)
            }
        }
        
        // Handle stream completion
        webSocketService.setMessageHandler(for: .streamComplete) { [weak self] message in
            DispatchQueue.main.async {
                self?.handleStreamComplete(message)
            }
        }
        
        // Handle permission requests
        webSocketService.setMessageHandler(for: .permissionRequest) { [weak self] message in
            DispatchQueue.main.async {
                self?.handlePermissionRequest(message)
            }
        }
        
        // Handle tool usage
        webSocketService.setMessageHandler(for: .streamToolUse) { [weak self] message in
            DispatchQueue.main.async {
                self?.handleToolUse(message)
            }
        }
        
        // Handle errors
        webSocketService.setMessageHandler(for: .error) { [weak self] message in
            DispatchQueue.main.async {
                self?.handleError(message)
            }
        }
    }
    
    private func handleStreamData(_ message: WebSocketMessage) {
        guard case .streamData(let streamData) = message.data else { return }
        
        // Create or update streaming message
        if currentStreamingMessage == nil {
            currentStreamingMessage = Message(
                id: UUID(),
                content: "",
                sender: .claude,
                timestamp: Date(),
                type: .text,
                streamingState: .streaming
            )
        }
        
        // Append content to current streaming message
        if let text = streamData.content.text {
            if currentStreamingMessage != nil {
                currentStreamingMessage!.content += text
            }
        }
        
        // Update the message in the messages array or add it
        if let streamingMessage = currentStreamingMessage {
            if let index = messages.firstIndex(where: { $0.id == streamingMessage.id }) {
                messages[index] = streamingMessage
            } else {
                messages.append(streamingMessage)
            }
        }
        
        // If stream is complete, finalize the message
        if streamData.isComplete {
            finalizeStreamingMessage()
        }
    }
    
    private func handleStreamComplete(_ message: WebSocketMessage) {
        guard case .streamComplete(let completeData) = message.data else { return }
        
        // Update message metadata if we have a streaming message
        if var streamingMessage = currentStreamingMessage {
            streamingMessage.streamingState = .completed
            streamingMessage.metadata = ClaudeMessageMetadata(
                sessionId: completeData.sessionId,
                duration: completeData.duration,
                cost: completeData.cost
            )
            
            if let index = messages.firstIndex(where: { $0.id == streamingMessage.id }) {
                messages[index] = streamingMessage
            }
        }
        
        finalizeStreamingMessage()
    }
    
    private func handlePermissionRequest(_ message: WebSocketMessage) {
        guard case .permissionRequest(let request) = message.data else { return }
        
        permissionRequest = request
        showingPermissionAlert = true
    }
    
    private func handleToolUse(_ message: WebSocketMessage) {
        guard case .streamToolUse(let toolUse) = message.data else { return }
        
        // Add a tool usage message
        let toolMessage = Message(
            id: UUID(),
            content: "🔧 Using tool: \(toolUse.toolName) - \(toolUse.status)",
            sender: .system,
            timestamp: Date(),
            type: .toolUse
        )
        
        messages.append(toolMessage)
    }
    
    private func handleError(_ message: WebSocketMessage) {
        guard case .error(let error) = message.data else { return }
        
        let errorMessage = Message(
            id: UUID(),
            content: "Error: \(error.message)",
            sender: .system,
            timestamp: Date(),
            type: .error
        )
        
        messages.append(errorMessage)
        finalizeStreamingMessage()
    }
    
    private func finalizeStreamingMessage() {
        currentStreamingMessage = nil
        isLoading = false
    }
    
    private func respondToPermission(_ response: String) {
        guard let request = permissionRequest else { return }
        
        webSocketService.respondToPermission(
            sessionId: request.sessionId,
            response: response,
            remember: false
        )
        
        permissionRequest = nil
        showingPermissionAlert = false
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer()
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(16)
                    .textSelection(.enabled)
                
                HStack {
                    if message.sender == .claude, let metadata = message.metadata {
                        Text("Session: \(metadata.sessionId.prefix(8))...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
            }
            
            if message.sender != .user {
                Spacer()
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.sender {
        case .user:
            return .blue
        case .claude:
            return Color.gray.opacity(0.2)
        case .system:
            return Color.red.opacity(0.2)
        }
    }
    
    private var textColor: Color {
        switch message.sender {
        case .user:
            return .white
        case .claude, .system:
            return .primary
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: animating)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(16)
            
            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

#Preview {
    NavigationView {
        ChatView()
            .environmentObject(ClaudeCodeService())
    }
}