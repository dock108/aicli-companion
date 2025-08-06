import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ChatSessionMenu: View {
    let sessionId: String?
    let projectName: String
    let messageCount: Int
    let onClearSession: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var showingClearConfirmation = false
    
    var body: some View {
        Menu {
            Section {
                // Only show session ID if we have both a session and messages
                if let sessionId = sessionId, messageCount > 0 {
                    Label("Session ID: \(sessionId.prefix(8))...", systemImage: "number.circle")
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Label("\(messageCount) messages", systemImage: "message.circle")
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
            
            // Only show clear option if we have messages to clear
            if messageCount > 0 {
                Section {
                    Button(role: .destructive, action: {
                        showingClearConfirmation = true
                    }) {
                        Label("Clear Chat & Start Fresh", systemImage: "trash.circle")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
        }
        .confirmationDialog(
            "Clear Chat & Start Fresh",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear & Start Fresh", role: .destructive) {
                onClearSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all messages and start a new session for \(projectName). This action cannot be undone.")
        }
    }
}

#if DEBUG
@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat Session Menu") {
    VStack {
        HStack {
            Text("Sample Chat")
            Spacer()
            ChatSessionMenu(
                sessionId: "12345678-1234-1234-1234-123456789012",
                projectName: "Sample Project",
                messageCount: 5,
                onClearSession: {
                    print("Clear session requested")
                }
            )
        }
        .padding()
        Spacer()
    }
}
#endif