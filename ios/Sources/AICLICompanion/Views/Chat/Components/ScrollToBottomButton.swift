import SwiftUI

/// Floating action button to scroll to bottom of chat
/// Appears when user scrolls up, similar to Slack/Discord
@available(iOS 16.0, macOS 13.0, *)
struct ScrollToBottomButton: View {
    let isVisible: Bool
    let unreadCount: Int
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 12, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, unreadCount > 0 ? 12 : 10)
            .padding(.vertical, 10)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Colors.accentPrimaryStart,
                                Colors.accentPrimaryEnd
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        } perform: {
            // Long press action if needed
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: unreadCount)
    }
}

/// Extension to add the scroll-to-bottom button as an overlay
@available(iOS 16.0, macOS 13.0, *)
extension View {
    func scrollToBottomButton(
        isVisible: Bool,
        unreadCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        self.overlay(alignment: .bottomTrailing) {
            ScrollToBottomButton(
                isVisible: isVisible,
                unreadCount: unreadCount,
                action: action
            )
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Preview
@available(iOS 17.0, macOS 14.0, *)
#Preview("Scroll Button States") {
    VStack(spacing: 40) {
        // Basic button
        ScrollToBottomButton(
            isVisible: true,
            unreadCount: 0,
            action: {}
        )
        
        // With unread count
        ScrollToBottomButton(
            isVisible: true,
            unreadCount: 3,
            action: {}
        )
        
        // With large unread count
        ScrollToBottomButton(
            isVisible: true,
            unreadCount: 99,
            action: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
