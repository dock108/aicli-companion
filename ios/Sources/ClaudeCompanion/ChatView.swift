import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@available(iOS 14.0, macOS 11.0, *)
struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @StateObject private var webSocketService = WebSocketService()
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    @State private var keyboardHeight: CGFloat = 0
    @State private var inputBarOffset: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Pure charcoal background
            Colors.bgBase(for: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
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
                        .frame(height: 0.5)
                    
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
            connectWebSocket()
            setupKeyboardObservers()
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
    ChatView()
        .environmentObject(ClaudeCodeService())
        .preferredColorScheme(.light)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat View - Dark") {
    ChatView()
        .environmentObject(ClaudeCodeService())
        .preferredColorScheme(.dark)
}