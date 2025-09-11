import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct AutoReplyStatusBar: View {
    let project: Project
    let onShowSettings: () -> Void
    
    @StateObject private var store = AutoReplySettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var projectUUID: UUID {
        ProjectUUIDConverter.uuid(for: project)
    }
    
    private var settings: AutoReplySettings? {
        store.settings(for: projectUUID)
    }
    
    private var isEnabled: Bool {
        settings?.isEnabled ?? false
    }
    
    var body: some View {
        if isEnabled || store.syncStatus != .idle {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        
                        Text(statusText)
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                    }
                    
                    Spacer()
                    
                    // Mode and progress info
                    if let settings = settings, settings.isEnabled {
                        HStack(spacing: 8) {
                            // Mode badge
                            Text(settings.mode.displayName)
                                .font(Typography.font(.caption2))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Colors.accentPrimaryEnd.opacity(0.1))
                                )
                                .foregroundColor(Colors.accentPrimaryEnd)
                            
                            // Progress info based on mode
                            if let progressText = getProgressText(for: settings) {
                                Text(progressText)
                                    .font(Typography.font(.caption2))
                                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                            }
                        }
                    }
                    
                    // Control buttons
                    HStack(spacing: 8) {
                        // Settings button
                        Button(action: onShowSettings) {
                            Image(systemName: "gear")
                                .font(.system(size: 14))
                                .foregroundColor(Colors.textSecondary(for: colorScheme))
                        }
                        
                        // Quick toggle
                        Toggle("", isOn: Binding(
                            get: { isEnabled },
                            set: { enabled in
                                toggleAutoReply(enabled)
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: Colors.accentPrimaryEnd))
                        .labelsHidden()
                        .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(backgroundColor)
                )
                
                // Sync status indicator
                if store.syncStatus != .idle {
                    HStack(spacing: 8) {
                        Image(systemName: syncStatusIcon)
                            .font(.system(size: 12))
                            .foregroundColor(store.syncStatus.color)
                        
                        Text(store.syncStatus.displayName)
                            .font(Typography.font(.caption2))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                        
                        Spacer()
                        
                        if store.syncStatus == .syncing {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(
                        Rectangle()
                            .fill(Colors.bgCard(for: colorScheme).opacity(0.3))
                    )
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: isEnabled)
            .animation(.easeInOut(duration: 0.3), value: store.syncStatus)
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        guard let settings = settings, settings.isEnabled else {
            return Colors.textSecondary(for: colorScheme)
        }
        
        switch settings.mode {
        case .smartStop:
            return Colors.accentSuccess
        case .untilCompletion:
            return Colors.accentWarning
        case .timeBased:
            return Colors.accentPrimaryEnd
        case .messageBased:
            return Colors.accentInfo
        case .hybrid:
            return Colors.accentPurple
        }
    }
    
    private var statusText: String {
        guard let settings = settings, settings.isEnabled else {
            return "Auto-Reply Disabled"
        }
        
        return "Auto-Reply: \(settings.mode.displayName)"
    }
    
    private var backgroundColor: Color {
        if isEnabled {
            return Colors.bgCard(for: colorScheme).opacity(0.8)
        } else {
            return Colors.bgCard(for: colorScheme).opacity(0.5)
        }
    }
    
    private var syncStatusIcon: String {
        switch store.syncStatus {
        case .idle:
            return "icloud"
        case .syncing:
            return "icloud.and.arrow.up"
        case .completed:
            return "checkmark.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }
    
    // MARK: - Helper Methods
    
    private func getProgressText(for settings: AutoReplySettings) -> String? {
        switch settings.mode {
        case .smartStop:
            return "Max \(settings.smartStopSettings.maxLoopAttempts) attempts"
            
        case .untilCompletion:
            return "Until done"
            
        case .timeBased:
            if settings.timeLimits.enabled {
                return "\(settings.timeLimits.minutes) min limit"
            }
            return nil
            
        case .messageBased:
            if settings.messageLimits.enabled {
                return "Max \(settings.messageLimits.maxMessages) msgs"
            }
            return nil
            
        case .hybrid:
            var limits: [String] = []
            if settings.hybridSettings.enableTimeLimit && settings.timeLimits.enabled {
                limits.append("\(settings.timeLimits.minutes)m")
            }
            if settings.hybridSettings.enableMessageLimit && settings.messageLimits.enabled {
                limits.append("\(settings.messageLimits.maxMessages) msgs")
            }
            if settings.hybridSettings.enableSmartStop {
                limits.append("smart stop")
            }
            
            return limits.isEmpty ? nil : limits.joined(separator: " • ")
        }
    }
    
    private func toggleAutoReply(_ enabled: Bool) {
        if enabled {
            // Create settings if they don't exist
            let settings = store.getOrCreateSettings(for: projectUUID, projectName: project.name)
            var updatedSettings = settings
            updatedSettings.isEnabled = true
            store.updateSettings(updatedSettings)
        } else {
            // Disable existing settings
            if var settings = store.settings(for: projectUUID) {
                settings.isEnabled = false
                store.updateSettings(settings)
            }
        }
    }
}

// MARK: - Preview
@available(iOS 16.0, macOS 13.0, *)
struct AutoReplyStatusBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Disabled state
            AutoReplyStatusBar(
                project: Project(name: "Test Project", path: "/test/path", type: "git"),
                onShowSettings: {}
            )
            
            // Enabled state would need mock data
            AutoReplyStatusBar(
                project: Project(name: "Active Project", path: "/active/path", type: "workspace"),
                onShowSettings: {}
            )
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
