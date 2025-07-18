import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    
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
                        
                        if isLoading {
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
        
        claudeService.sendPrompt(prompt) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let response):
                    let claudeMessage = Message(
                        id: UUID(),
                        content: response.result,
                        sender: .claude,
                        timestamp: Date(),
                        type: .text,
                        metadata: ClaudeMessageMetadata(
                            sessionId: response.sessionId,
                            duration: response.duration,
                            cost: response.totalCost
                        )
                    )
                    messages.append(claudeMessage)
                    
                case .failure(let error):
                    let errorMessage = Message(
                        id: UUID(),
                        content: "Error: \(error.localizedDescription)",
                        sender: .system,
                        timestamp: Date(),
                        type: .error
                    )
                    messages.append(errorMessage)
                }
            }
        }
    }
    
    private func loadChatHistory() {
        // TODO: Load persisted chat history if needed
        messages = []
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