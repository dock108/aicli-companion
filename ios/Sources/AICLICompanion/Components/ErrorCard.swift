import SwiftUI

/// Error card that slides in from the top
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ErrorCard: View {
    let message: String
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
            
            Text(message)
                .font(Typography.font(.body))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.card)
                .fill(Color(red: 0.9, green: 0.2, blue: 0.2))
                .shadow(Shadows.large)
        )
        .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
    }
}