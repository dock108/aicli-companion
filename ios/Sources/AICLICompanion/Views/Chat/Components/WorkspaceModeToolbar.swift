//
//  WorkspaceModeToolbar.swift
//  AICLICompanion
//
//  Workspace mode specific tools and features
//

import SwiftUI

struct WorkspaceModeToolbar: View {
    @Binding var showingPlanningDashboard: Bool
    @Binding var showingProjectCreation: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Planning Validation - only show if enabled
                if FeatureFlags.showPlanningValidation {
                    ToolButton(
                        icon: "chart.bar.doc.horizontal",
                        title: "Planning Validation",
                        subtitle: "Analyze project readiness",
                        color: .blue,
                        action: { showingPlanningDashboard = true }
                    )
                }
                
                // Project Creation - only show if enabled
                if FeatureFlags.showProjectCreation {
                    ToolButton(
                        icon: "folder.badge.plus",
                        title: "New Project",
                        subtitle: "Create with AI guidance",
                        color: .green,
                        action: { showingProjectCreation = true }
                    )
                }
                
                // Code Review - only show if enabled
                if FeatureFlags.showCodeReview {
                    ToolButton(
                        icon: "doc.text.magnifyingglass",
                        title: "Code Review",
                        subtitle: "Coming soon",
                        color: .orange,
                        disabled: true,
                        action: { }
                    )
                }
                
                // Refactor Assistant - only show if enabled
                if FeatureFlags.showRefactorAssistant {
                    ToolButton(
                        icon: "arrow.triangle.merge",
                        title: "Refactor Assistant",
                        subtitle: "Coming soon",
                        color: .purple,
                        disabled: true,
                        action: { }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.purple.opacity(0.05))
    }
}

struct ToolButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(disabled ? Color.gray : color)
                    
                    Spacer()
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(disabled ? Color.gray : Colors.textPrimary(for: colorScheme))
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(disabled ? Color.gray.opacity(0.7) : Colors.textSecondary(for: colorScheme))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 140, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(disabled ? Color.gray.opacity(0.1) : color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(disabled ? Color.gray.opacity(0.2) : color.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(disabled)
        .scaleEffect(disabled ? 1.0 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }
}

// MARK: - Preview

struct WorkspaceModeToolbar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            WorkspaceModeToolbar(
                showingPlanningDashboard: .constant(false),
                showingProjectCreation: .constant(false)
            )
            
            Spacer()
        }
    }
}
