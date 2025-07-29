import SwiftUI

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
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
        Group {
            if sessionMetadata.sessionId.isEmpty {
                // Debug view when metadata is invalid
                VStack {
                    Text("Invalid Session Data")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("Session ID is empty")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // Additional debug info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debug Information:")
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text("Project: \(project.name)")
                            .font(.caption2)
                        Text("Path: \(project.path)")
                            .font(.caption2)
                        Text("AICLI Session: \(sessionMetadata.aicliSessionId ?? "nil")")
                            .font(.caption2)
                        Text("Message Count: \(sessionMetadata.messageCount)")
                            .font(.caption2)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding()
                }
                .onAppear {
                    print("❌ SessionContinuationSheet: Invalid session metadata - empty session ID")
                    print("   Project: \(project.name) at \(project.path)")
                    print("   AICLI Session ID: \(sessionMetadata.aicliSessionId ?? "nil")")
                    print("   Message Count: \(sessionMetadata.messageCount)")
                }
            } else {
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
                        print("🟣 SessionContinuationSheet: Continue button pressed")
                        print("   - Calling onContinue callback")
                        onContinue()
                        print("   - onContinue callback completed")
                        // Don't dismiss here - let the parent handle it after navigation state is updated
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
                        print("🟣 SessionContinuationSheet: Start Fresh button pressed")
                        print("   - Calling onStartFresh callback")
                        onStartFresh()
                        print("   - onStartFresh callback completed")
                        // Don't dismiss here - let the parent handle it after navigation state is updated
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
            }
        }
        .onAppear {
            print("🎭 SessionContinuationSheet: Sheet appeared for project '\(project.name)'")
            print("   Session metadata:")
            print("   - Session ID: \(sessionMetadata.sessionId)")
            print("   - AICLI Session ID: \(sessionMetadata.aicliSessionId ?? "nil")")
            print("   - Message Count: \(sessionMetadata.messageCount)")
            print("   - Last Used: \(sessionMetadata.formattedLastUsed)")
            
            // Debug check for NavigationStack availability
            if #available(iOS 16.0, *) {
                print("✅ NavigationStack is available")
            } else {
                print("❌ NavigationStack is NOT available - this should not happen on iOS 17+")
            }
            
            loadPreviewMessages()
        }
        .onDisappear {
            print("🎭 SessionContinuationSheet: Sheet disappeared")
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

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
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

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
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