import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Optimized message list with lazy loading and virtualization
@available(iOS 16.0, *)
struct OptimizedMessageList: View {
    let messages: [Message]
    let isLoading: Bool
    let progressInfo: ProgressInfo?
    @Binding var selectedMessage: Message?
    
    // Performance optimization
    @State private var visibleRange: Range<Int> = 0..<0
    private let messageRenderLimit = 100 // Only render last 100 messages for performance
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Only render recent messages for performance
                    ForEach(recentMessages) { message in
                        MessageRow(
                            message: message,
                            isSelected: selectedMessage?.id == message.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedMessage = message
                                }
                            }
                        )
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                    
                    // Loading indicator
                    if isLoading {
                        LoadingIndicator(progressInfo: progressInfo)
                            .padding()
                            .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                // Auto-scroll to bottom on new message
                withAnimation {
                    if isLoading {
                        proxy.scrollTo("loading", anchor: .bottom)
                    } else if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // Compute only recent messages for rendering
    private var recentMessages: [Message] {
        guard messages.count > messageRenderLimit else {
            return messages
        }
        // Return last N messages for performance
        return Array(messages.suffix(messageRenderLimit))
    }
}

/// Optimized message row with lazy rendering
@available(iOS 16.0, *)
private struct MessageRow: View {
    let message: Message
    let isSelected: Bool
    let onTap: () -> Void
    
    // Cache expensive computations
    @State private var renderedContent: AttributedString?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Sender indicator
            Circle()
                .fill(senderColor)
                .frame(width: 8, height: 8)
                .offset(y: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Sender label
                Text(message.sender.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Message content (cached)
                if let content = renderedContent {
                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .onAppear {
                            Task {
                                renderedContent = await renderMarkdown(message.content)
                            }
                        }
                }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onTapGesture(perform: onTap)
    }
    
    private var senderColor: Color {
        switch message.sender {
        case .user:
            return .blue
        case .assistant:
            return .green
        case .system:
            return .orange
        }
    }
    
    // Async markdown rendering for performance
    private func renderMarkdown(_ text: String) async -> AttributedString {
        // Simple markdown rendering - can be enhanced
        return AttributedString(text)
    }
}

/// Loading indicator component
@available(iOS 16.0, *)
private struct LoadingIndicator: View {
    let progressInfo: ProgressInfo?
    
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.2)
            
            if let info = progressInfo {
                Text(info.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let stage = info.stage {
                    Text(stage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(iOS)
                .fill(Color(UIColor.systemBackground))
                #else
                .fill(Color(NSColor.windowBackgroundColor))
                #endif
                .shadow(radius: 2)
        )
    }
}

// Extension for sender display names
private extension MessageSender {
    var displayName: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "Claude"
        case .system:
            return "System"
        }
    }
}