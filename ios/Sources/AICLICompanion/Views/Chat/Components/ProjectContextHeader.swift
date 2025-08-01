import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ProjectContextHeader: View {
    let project: Project
    let session: ProjectSession?
    let messageCount: Int
    let onSwitchProject: () -> Void
    let onClearSession: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Back to projects button
            Button(action: onSwitchProject) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                    Text("Projects")
                        .font(Typography.font(.body))
                        .fontWeight(.medium)
                }
                .foregroundColor(Colors.accentPrimary(for: colorScheme).first ?? Colors.accentPrimaryStart)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Colors.bgCard(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Colors.strokeLight, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            
            // Project info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(Typography.font(.body))
                        .fontWeight(.semibold)
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    if session != nil {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Text(project.path)
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            // Session menu
            ChatSessionMenu(
                sessionId: session?.sessionId,
                projectName: project.name,
                messageCount: messageCount,
                onClearSession: onClearSession
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Colors.bgCard(for: colorScheme).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.strokeLight, lineWidth: 1)
                )
        )
    }
}