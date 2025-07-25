import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct MessageBubble: View {
    let message: Message
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(message.sender == .user ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(backgroundForSender)
                    )
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if message.sender != .user {
                Spacer(minLength: 60)
            }
        }
    }
    
    private var backgroundForSender: Color {
        switch message.sender {
        case .user:
            return Color.blue
        case .claude:
            return colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95)
        case .system:
            return Color.orange.opacity(0.2)
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    VStack(spacing: 20) {
        MessageBubble(message: Message(
            content: "Hello, how can I help you today?",
            sender: .claude
        ))
        
        MessageBubble(message: Message(
            content: "I need help with my code",
            sender: .user
        ))
        
        MessageBubble(message: Message(
            content: "System notification",
            sender: .system
        ))
    }
    .padding()
}