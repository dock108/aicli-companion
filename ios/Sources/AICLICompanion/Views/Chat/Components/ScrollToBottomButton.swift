import SwiftUI

/// Floating action button that appears when user scrolls up to help them quickly return to bottom
@available(iOS 16.0, macOS 13.0, *)
struct ScrollToBottomButton: View {
    let isVisible: Bool
    let unreadCount: Int
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                Button(action: onTap) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Colors.accentPrimaryEnd)
                        
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(Typography.font(.caption))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Colors.accentPrimaryEnd)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Colors.bgCard(for: colorScheme))
                            .shadow(
                                color: Colors.shadowDark.opacity(0.15),
                                radius: 8,
                                x: 0,
                                y: 2
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: unreadCount)
                
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }
}

// ScaleButtonStyle is already defined in AnimationConstants.swift

// MARK: - Notification Names

extension Notification.Name {
    static let scrollToBottom = Notification.Name("com.aiclicompanion.scrollToBottom")
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Scroll Button - Visible") {
    ZStack {
        Colors.bgBase(for: .dark)
            .ignoresSafeArea()
        
        ScrollToBottomButton(
            isVisible: true,
            unreadCount: 3,
            onTap: {}
        )
    }
    .preferredColorScheme(.dark)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Scroll Button - Hidden") {
    ZStack {
        Colors.bgBase(for: .dark)
            .ignoresSafeArea()
        
        ScrollToBottomButton(
            isVisible: false,
            unreadCount: 0,
            onTap: {}
        )
    }
    .preferredColorScheme(.dark)
}
