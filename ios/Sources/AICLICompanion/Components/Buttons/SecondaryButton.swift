import SwiftUI

/// Secondary outlined button style with Dark-Slate Terminal design
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    let isEnabled: Bool
    
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        _ title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
        self.isEnabled = isEnabled
    }
    
    public var body: some View {
        Button(action: {
            guard isEnabled else { return }
            
            // Haptic feedback
            HapticManager.shared.lightImpact()
            
            // Execute action
            action()
        }) {
            ZStack {
                // Outlined background
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: Colors.accentPrimary(for: colorScheme),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.clear)
                    )
                
                // Text content
                Text(title)
                    .font(Typography.font(.body))
                    .fontWeight(.medium)
                    .foregroundColor(
                        isEnabled 
                            ? Colors.accentPrimaryEnd 
                            : Colors.textSecondary(for: colorScheme)
                    )
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .opacity(isEnabled ? 1.0 : 0.5)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PressableButtonStyle(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        ))
        .disabled(!isEnabled)
    }
}

/// Text link button style
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct TextLinkButton: View {
    let title: String
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        _ title: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            HapticManager.shared.selectionChanged()
            action()
        }) {
            Text(title)
                .font(Typography.font(.bodySmall))
                .foregroundColor(Colors.accentPrimaryEnd)
                .underline(isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

/// Icon button style
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct IconButton: View {
    let systemName: String
    let action: () -> Void
    let size: CGFloat
    
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        systemName: String,
        size: CGFloat = 24,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.size = size
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Colors.bgCard(for: colorScheme))
                        .opacity(isPressed ? 0.8 : 0)
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(PressableButtonStyle(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        ))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }
}

// MARK: - Preview
@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
#Preview("Secondary Buttons") {
    VStack(spacing: Spacing.lg) {
        SecondaryButton("Manual Setup") {
            print("Manual setup tapped")
        }
        
        SecondaryButton("Disabled Secondary", isEnabled: false) {
            print("Won't be called")
        }
        
        HStack {
            TextLinkButton("Need help?") {
                print("Help tapped")
            }
            
            Spacer()
            
            IconButton(systemName: "questionmark.circle") {
                print("Question tapped")
            }
        }
        .padding(.horizontal)
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}