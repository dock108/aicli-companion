import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct AutoResponseControls: View {
    @ObservedObject var autoResponseManager = AutoResponseManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Auto-response status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(autoResponseManager.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(autoResponseManager.isActive ? "Auto Mode Active" : "Auto Mode")
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
            
            Spacer()
            
            // Control buttons
            if autoResponseManager.isActive {
                if autoResponseManager.isPaused {
                    Button(action: {
                        autoResponseManager.resume()
                    }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Colors.accentPrimaryEnd)
                    }
                } else {
                    Button(action: {
                        autoResponseManager.pause()
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                }
                
                Button(action: {
                    autoResponseManager.deactivate()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Colors.accentDanger)
                }
            } else {
                Toggle("", isOn: Binding(
                    get: { autoResponseManager.config.enabled },
                    set: { enabled in
                        autoResponseManager.config.enabled = enabled
                        if enabled {
                            autoResponseManager.activate()
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Colors.accentPrimaryEnd))
                .labelsHidden()
                .scaleEffect(0.8)
            }
            
            // Iteration counter
            if autoResponseManager.isActive {
                Text("\(autoResponseManager.currentIteration)/\(autoResponseManager.config.maxIterations)")
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Colors.bgCard(for: colorScheme))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Colors.bgCard(for: colorScheme).opacity(0.5))
        )
    }
}

// MARK: - Compact Version for Chat Input Bar
@available(iOS 16.0, macOS 13.0, *)
struct CompactAutoResponseToggle: View {
    @ObservedObject var autoResponseManager = AutoResponseManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            if autoResponseManager.isActive {
                autoResponseManager.deactivate()
            } else {
                autoResponseManager.config.enabled = true
                autoResponseManager.activate()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: autoResponseManager.isActive ? "bolt.fill" : "bolt")
                    .font(.system(size: 16))
                    .foregroundColor(autoResponseManager.isActive ? Colors.accentPrimaryEnd : Colors.textSecondary(for: colorScheme))
                
                if autoResponseManager.isActive {
                    Text("\(autoResponseManager.currentIteration)/\(autoResponseManager.config.maxIterations)")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(autoResponseManager.isActive ? Colors.accentPrimaryEnd.opacity(0.1) : Colors.bgCard(for: colorScheme))
                    .overlay(
                        Capsule()
                            .stroke(autoResponseManager.isActive ? Colors.accentPrimaryEnd : Colors.strokeLight, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
