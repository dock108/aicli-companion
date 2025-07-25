import SwiftUI

/// Primary button component with gradient background based on Figma design
public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool
    let isEnabled: Bool
    
    @State private var isPressed = false
    
    public init(
        _ title: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            if isEnabled && !isLoading {
                action()
            }
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: CornerRadius.button)
                    .fill(Gradients.primaryButton)
                    .opacity(isEnabled ? 1.0 : 0.4)
                    .overlay(
                        // Hover/Press state overlay
                        RoundedRectangle(cornerRadius: CornerRadius.button)
                            .fill(Colors.surface10)
                            .opacity(isPressed ? 1 : 0)
                    )
                
                // Content
                HStack(spacing: Spacing.xs) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(title)
                            .buttonText()
                    }
                }
                .padding(.vertical, Spacing.Component.buttonPaddingVertical)
                .padding(.horizontal, Spacing.Component.buttonPaddingHorizontal)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled || isLoading)
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
struct PrimaryButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            PrimaryButton("Scan QR Code") {
                print("Scan tapped")
            }
            
            PrimaryButton("Loading...", isLoading: true) {
                print("Loading")
            }
            
            PrimaryButton("Disabled", isEnabled: false) {
                print("Disabled")
            }
        }
        .padding()
    }
}