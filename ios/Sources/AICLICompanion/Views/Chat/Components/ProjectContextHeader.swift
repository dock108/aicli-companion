import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ProjectContextHeader: View {
    let project: Project
    let session: ProjectSession?
    let messageCount: Int
    let onSwitchProject: () -> Void
    let onClearSession: () -> Void
    let onShowAutoReplySettings: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Back to projects button (only on iPhone)
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom != .pad {
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
            }
            #endif
            
            // Project name or workspace indicator
            HStack(spacing: 8) {
                if project.type == "workspace" {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(Color.purple)
                }
                Text(project.name)
                    .font(Typography.font(.body))
                    .fontWeight(.medium)
                    .foregroundColor(project.type == "workspace" ? Color.purple : Colors.textPrimary(for: colorScheme))
                if project.type == "workspace" {
                    Text("• Cross-project operations enabled")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            
            Spacer()
            
            // Project settings menu
            Menu {
                Button {
                    onShowAutoReplySettings()
                } label: {
                    Label("Auto-Reply Settings...", systemImage: "play.circle")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onClearSession()
                } label: {
                    Label("Clear Chat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Colors.bgCard(for: colorScheme).opacity(0.95))
                .overlay(
                    Rectangle()
                        .fill(Colors.strokeLight.opacity(0.3))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
}
