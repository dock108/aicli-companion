import SwiftUI

// MARK: - Main Message Bubble View
// Uses composition pattern with specialized rendering components

@available(iOS 17.0, macOS 14.0, *)
struct MessageBubble: View {
    let message: Message
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @StateObject private var clipboardManager = ClipboardManager.shared
    
    // Adaptive max width based on device
    private var maxBubbleWidth: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return horizontalSizeClass == .regular ? 700 : 500
        } else {
            return 500
        }
        #else
        return 600
        #endif
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.sender == .user {
                Spacer(minLength: horizontalSizeClass == .regular ? 60 : 40)
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                Group {
                    if message.sender == .user {
                        MessageContentRenderer.userBubble(
                            for: message,
                            colorScheme: colorScheme,
                            clipboardManager: clipboardManager
                        )
                    } else {
                        MessageContentRenderer.aiBubble(
                            for: message,
                            colorScheme: colorScheme,
                            clipboardManager: clipboardManager
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
            }
            .frame(maxWidth: maxBubbleWidth)
            
            if message.sender != .user {
                Spacer(minLength: horizontalSizeClass == .regular ? 60 : 40)
            }
        }
    }
}
