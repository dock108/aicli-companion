import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ProjectContextHeader: View {
    let project: Project
    let session: ProjectSession?
    let onSwitchProject: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
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
            
            // Switch project button
            Button(action: onSwitchProject) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right.square")
                        .font(.system(size: 16, weight: .medium))
                    Text("Switch")
                        .font(Typography.font(.caption))
                        .fontWeight(.medium)
                }
                .foregroundColor(Colors.accentPrimary(for: colorScheme).first ?? Colors.accentPrimaryStart)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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