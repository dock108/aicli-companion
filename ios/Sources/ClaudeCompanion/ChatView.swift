import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @StateObject private var webSocketService = WebSocketService()
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
                .background(Color.clear)
                .onChange(of: messages.count) { oldValue, newValue in
                    if let lastMessage = messages.last {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input area
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    // Message input field
                    HStack {
                        TextField("Type a message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .onSubmit {
                                sendMessage()
                            }
                    }
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(20)
                    
                    // Send button
                    Button(action: {
                        sendMessage()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(messageText.isEmpty ? Color.secondary : Color.blue)
                    }
                    .disabled(messageText.isEmpty || isLoading)
                    .animation(.easeInOut(duration: 0.2), value: messageText.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            connectWebSocket()
        }
        .onDisappear {
            webSocketService.disconnect()
        }
    }
    
    // MARK: - Private Methods
    
    private func connectWebSocket() {
        // Connect using saved settings
        let settings = SettingsManager()
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
        
        // Send via WebSocket
        let pingRequest = PingRequest()
        webSocketService.sendMessage(pingRequest, type: .ping) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                // Add response message
                let responseMessage = Message(
                    content: "Connected! Message sent: \(messageCopy)",
                    sender: .claude,
                    type: .text
                )
                self.messages.append(responseMessage)
            }
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    ChatView()
        .environmentObject(ClaudeCodeService())
}
