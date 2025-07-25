import SwiftUI

/// Secondary button component with outline style based on Figma design
public struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    let isEnabled: Bool
    
    @State private var isPressed = false
    
    public init(
        _ title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            if isEnabled {
                action()
            }
        }) {
            ZStack {
                // Background with border
                RoundedRectangle(cornerRadius: CornerRadius.button)
                    .stroke(Colors.brandBlue500.opacity(0.2), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.button)
                            .fill(isPressed ? Colors.surface10 : Color.clear)
                    )
                
                // Content
                Text(title)
                    .font(Typography.font(.button))
                    .foregroundColor(isEnabled ? Colors.brandBlue500 : Colors.brandBlue500.opacity(0.4))
                    .padding(.vertical, Spacing.Component.buttonPaddingVertical)
                    .padding(.horizontal, Spacing.Component.buttonPaddingHorizontal)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
}

// MARK: - Preview
struct SecondaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SecondaryButton("Manual Setup") {
                print("Manual setup tapped")
            }
            
            SecondaryButton("Disabled", isEnabled: false) {
                print("Disabled")
            }
        }
        .padding()
    }
}