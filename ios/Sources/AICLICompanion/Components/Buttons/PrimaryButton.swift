import SwiftUI

/// Primary button style with Dark-Slate Terminal design
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    let isLoading: Bool
    let isEnabled: Bool
    
    @State private var isPressed = false
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        _ title: String,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
        self.isLoading = isLoading
        self.isEnabled = isEnabled
    }
    
    public var body: some View {
        Button(action: {
            guard isEnabled && !isLoading else { return }
            
            // Haptic feedback
            HapticManager.shared.mediumImpact()
            
            // Execute action
            action()
        }) {
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Gradients.primaryButton(for: colorScheme))
                    .opacity(isEnabled && !isLoading ? 1.0 : 0.6)
                    .shadow(
                        color: Colors.shadowDark,
                        radius: 12,
                        x: 0,
                        y: 4
                    )
                
                // Content
                HStack(spacing: Spacing.xs) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(title)
                            .font(Typography.font(.body))
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .opacity(isEnabled || isLoading ? 1.0 : 0.6)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .offset(y: isPressed ? 3 : 0)
        }
        .buttonStyle(PressableButtonStyle(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        ))
        .disabled(!isEnabled || isLoading)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

/// Button press handler style
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct PressableButtonStyle: ButtonStyle {
    let onPress: () -> Void
    let onRelease: () -> Void
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    onPress()
                } else {
                    onRelease()
                }
            }
    }
}

// MARK: - Loading Button Variant
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct LoadingPrimaryButton: View {
    let title: String
    let loadingTitle: String
    @Binding var isLoading: Bool
    let action: () async -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isPressed = false
    @State private var showMorphAnimation = false
    
    public init(
        _ title: String,
        loadingTitle: String = "Loading...",
        isLoading: Binding<Bool>,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self._isLoading = isLoading
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            guard !isLoading else { return }
            
            Task {
                HapticManager.shared.mediumImpact()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isLoading = true
                    showMorphAnimation = true
                }
                
                await action()
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isLoading = false
                    showMorphAnimation = false
                }
            }
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: showMorphAnimation ? 26 : 12)
                    .fill(Gradients.primaryButton(for: colorScheme))
                    .shadow(
                        color: Colors.shadowDark,
                        radius: 12,
                        x: 0,
                        y: 4
                    )
                
                // Content
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .font(Typography.font(.body))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            .frame(width: showMorphAnimation ? 52 : nil, height: 52)
            .frame(maxWidth: showMorphAnimation ? 52 : .infinity)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .offset(y: isPressed ? 3 : 0)
        }
        .buttonStyle(PressableButtonStyle(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        ))
        .disabled(isLoading)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

// MARK: - Preview
@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
#Preview("Primary Buttons") {
    VStack(spacing: Spacing.lg) {
        PrimaryButton("Scan QR Code") {
            print("Scan tapped")
        }
        
        PrimaryButton("Disabled Button", isEnabled: false) {
            print("Won't be called")
        }
        
        PrimaryButton("Loading", isLoading: true) {
            print("Won't be called")
        }
        
        LoadingPrimaryButton(
            "Connect",
            isLoading: .constant(false)
        ) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}