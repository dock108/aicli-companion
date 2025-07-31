import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ChatInputBar: View {
    @Binding var messageText: String
    let isLoading: Bool
    let isIPad: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let colorScheme: ColorScheme
    let onSendMessage: () -> Void
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Colors.strokeLight)
            
            HStack(alignment: .bottom, spacing: 12) {
                // Text input
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .accentColor(Colors.accentPrimary(for: colorScheme).first ?? Colors.accentPrimaryStart)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .disabled(isLoading)
                    .onSubmit {
                        if !messageText.isEmpty {
                            onSendMessage()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Colors.bgCard(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Colors.strokeLight, lineWidth: 1)
                            )
                    )
                
                // Send button
                Button(action: onSendMessage) {
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
            .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
    }
}