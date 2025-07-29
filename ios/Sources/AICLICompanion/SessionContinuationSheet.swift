import SwiftUI

@available(iOS 15.0, macOS 12.0, *)
struct SessionContinuationSheet: View {
    let project: Project
    let sessionMetadata: SessionMetadata
    let onContinue: () -> Void
    let onStartFresh: () -> Void
    let onViewHistory: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var persistenceService = MessagePersistenceService.shared
    @State private var previewMessages: [Message] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: Colors.accentPrimary(for: colorScheme),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Continue Previous Session?")
                        .font(Typography.font(.heading2))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("You have an active session from \(sessionMetadata.formattedLastUsed)")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal)
                
                // Session Info
                HStack(spacing: 20) {
                    SessionInfoCard(
                        icon: "message",
                        value: "\(sessionMetadata.messageCount)",
                        label: "Messages"
                    )
                    
                    SessionInfoCard(
                        icon: "clock",
                        value: sessionMetadata.formattedLastUsed,
                        label: "Last Activity"
                    )
                }
                .padding(.vertical, 20)
                
                // Message Preview
                if !previewMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Messages")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .padding(.horizontal)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(previewMessages.suffix(5)) { message in
                                    MessagePreviewRow(message: message)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding(.vertical)
                    .background(Colors.bgCard(for: colorScheme))
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    // Continue Button
                    Button(action: {
                        onContinue()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Continue Conversation")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: Colors.accentPrimary(for: colorScheme),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    // Start Fresh Button
                    Button(action: {
                        onStartFresh()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Start Fresh")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Colors.bgCard(for: colorScheme))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Colors.strokeLight, lineWidth: 1)
                        )
                    }
                    
                    // View History Button
                    Button(action: {
                        onViewHistory()
                        dismiss()
                    }) {
                        Text("View Full History")
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.accentPrimaryEnd)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(Colors.bgBase(for: colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
        }
        .onAppear {
            loadPreviewMessages()
        }
    }
    
    private func loadPreviewMessages() {
        if let sessionId = sessionMetadata.aicliSessionId {
            previewMessages = persistenceService.loadMessages(
                for: project.path,
                sessionId: sessionId
            )
        }
    }
}

// MARK: - Supporting Views

@available(iOS 14.0, macOS 11.0, *)
struct SessionInfoCard: View {
    let icon: String
    let value: String
    let label: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Colors.accentPrimaryEnd)
            
            Text(value)
                .font(Typography.font(.heading3))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
            
            Text(label)
                .font(Typography.font(.caption))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Colors.bgCard(for: colorScheme))
        .cornerRadius(12)
    }
}

@available(iOS 14.0, macOS 11.0, *)
struct MessagePreviewRow: View {
    let message: Message
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.sender == .user ? "person.circle.fill" : "cpu")
                .font(.caption)
                .foregroundColor(message.sender == .user ? Colors.accentPrimaryEnd : Colors.textSecondary(for: colorScheme))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(message.sender == .user ? "You" : "AICLI")
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                
                Text(message.content)
                    .font(Typography.font(.bodySmall))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(message.timestamp, style: .time)
                .font(Typography.font(.caption))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 6)
    }
}