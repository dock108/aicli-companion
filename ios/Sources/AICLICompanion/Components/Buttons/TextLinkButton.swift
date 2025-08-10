import SwiftUI

/// Text link button with terminal-style appearance
@available(iOS 16.0, macOS 13.0, *)
public struct TextLinkButton: View {
    let title: String
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            Text(title)
                .font(Typography.font(.body))
                .foregroundColor(Colors.accentPrimaryEnd)
                .underline(isHovered)
                .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview
@available(iOS 17.0, macOS 14.0, *)
#Preview("Text Link Button") {
    VStack(spacing: Spacing.lg) {
        TextLinkButton("Need help connecting?") {
            print("Help tapped")
        }
        
        TextLinkButton("View documentation") {
            print("Documentation tapped")
        }
        
        TextLinkButton("Reset settings") {
            print("Reset tapped")
        }
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}
