import SwiftUI

/// Live indicator showing Claude CLI status and progress
/// Appears above message input or replaces typing bubble
@available(iOS 16.0, macOS 13.0, *)
struct ClaudeStatusIndicator: View {
    // MARK: - State
    
    @ObservedObject var statusManager = ClaudeStatusManager.shared
    @State private var animationOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            if let status = statusManager.currentStatus {
                statusContent(for: status)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: statusManager.currentStatus)
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    // MARK: - Status Content
    
    @ViewBuilder
    private func statusContent(for status: ClaudeStatus) -> some View {
        HStack(spacing: 12) {
            // Status icon with animation
            statusIcon(for: status)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulseScale = status.canInterrupt ? 1.1 : 1.05
                    }
                }
            
            // Status text and details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(status.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if let duration = status.duration {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                if let subtitle = status.displaySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Progress bar for long-running tasks
                if status.showProgressBar, let duration = status.duration {
                    ProgressView(value: min(duration / 60.0, 1.0)) // Normalize to 60s max
                        .progressViewStyle(LinearProgressViewStyle(tint: statusColor(for: status)))
                        .scaleEffect(y: 0.5)
                }
            }
            
            // Interrupt button for interruptible tasks
            if status.canInterrupt {
                Button(action: {
                    // TODO: Implement interrupt functionality
                    print("Interrupt requested")
                }) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(statusColor(for: status).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Status Icon
    
    @ViewBuilder
    private func statusIcon(for status: ClaudeStatus) -> some View {
        let icon = iconName(for: status)
        let color = statusColor(for: status)
        
        Image(systemName: icon)
            .font(.title2)
            .foregroundColor(color)
            .offset(x: animationOffset)
            .onAppear {
                if status.statusType == "progress" {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        animationOffset = 2
                    }
                }
            }
    }
    
    // MARK: - Helper Methods
    
    private func iconName(for status: ClaudeStatus) -> String {
        switch status.statusType {
        case "progress":
            switch status.stage {
            case "creating": return "brain.head.profile"
            case "thinking": return "brain.head.profile.fill"
            case "working": return "gearshape.2.fill"
            case "processing": return "cpu.fill"
            default: return "hourglass"
            }
        case "tools": return "wrench.and.screwdriver.fill"
        case "completion": return "checkmark.circle.fill"
        case "interruption": return "stop.circle.fill"
        default: return "hourglass"
        }
    }
    
    private func statusColor(for status: ClaudeStatus) -> Color {
        switch status.statusType {
        case "progress": return .blue
        case "tools": return .orange
        case "completion": return .green
        case "interruption": return .red
        default: return .gray
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - Claude Status Manager

/// Manages the current Claude CLI status state
@available(iOS 16.0, macOS 13.0, *)
class ClaudeStatusManager: ObservableObject {
    static let shared = ClaudeStatusManager()
    
    @Published var currentStatus: ClaudeStatus?
    
    private init() {
        // Listen for status updates from WebSocket
        setupStatusHandlers()
    }
    
    private func setupStatusHandlers() {
        // HTTP architecture: Status updates are handled within HTTP responses
        // For now, status updates are not implemented for HTTP
        // This method is kept for future implementation
    }
    
    func updateStatus(_ status: ClaudeStatus) {
        currentStatus = status
        
        // Auto-hide completion and interruption statuses after a delay
        if status.statusType == "completion" || status.statusType == "interruption" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.currentStatus?.id == status.id {
                    self.currentStatus = nil
                }
            }
        }
    }
    
    func clearStatus() {
        currentStatus = nil
    }
}

// MARK: - Claude Status Model

/// Represents the current Claude CLI status
public struct ClaudeStatus: Identifiable, Equatable {
    public let id = UUID()
    public let statusType: String // "progress", "tools", "completion", "interruption"
    public let stage: String? // "creating", "thinking", "working", "completed", etc.
    public let duration: Double? // Duration in seconds
    public let tokens: Int? // Token count
    public let tools: [String]? // Tools being used
    public let canInterrupt: Bool // Whether the operation can be interrupted
    public let originalText: String // Original status text from Claude CLI
    public let sessionId: String
    public let timestamp = Date()
    
    // MARK: - Display Properties
    
    var displayTitle: String {
        switch statusType {
        case "progress":
            if let stage = stage {
                return stage.capitalized + "..."
            }
            return "Working..."
        case "tools":
            return "Using Tools"
        case "completion":
            return "Completed"
        case "interruption":
            return "Interrupted"
        default:
            return "Processing..."
        }
    }
    
    var displaySubtitle: String? {
        var parts: [String] = []
        
        if let tools = tools, !tools.isEmpty {
            parts.append("⚒ \(tools.joined(separator: ", "))")
        }
        
        if let tokens = tokens {
            let tokenStr = tokens >= 1000 ? "\(String(format: "%.1f", Double(tokens) / 1000))k" : "\(tokens)"
            parts.append("\(tokenStr) tokens")
        }
        
        if canInterrupt {
            parts.append("esc to interrupt")
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    
    var showProgressBar: Bool {
        return statusType == "progress" && duration != nil && duration! > 5.0
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: ClaudeStatus, rhs: ClaudeStatus) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 16.0, macOS 13.0, *)
struct ClaudeStatusIndicator_Previews: PreviewProvider {
    private static var systemGroupedBackgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.systemGroupedBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    static var previews: some View {
        VStack(spacing: 20) {
            // Progress status
            ClaudeStatusIndicator()
                .onAppear {
                    ClaudeStatusManager.shared.updateStatus(ClaudeStatus(
                        statusType: "progress",
                        stage: "creating",
                        duration: 45.3,
                        tokens: 27700,
                        tools: nil,
                        canInterrupt: true,
                        originalText: "Creating… (45.3s · ⚒ 27.7k tokens · esc to interrupt)",
                        sessionId: "test"
                    ))
                }
            
            // Tools status
            ClaudeStatusIndicator()
                .onAppear {
                    ClaudeStatusManager.shared.updateStatus(ClaudeStatus(
                        statusType: "tools",
                        stage: "tool_use",
                        duration: nil,
                        tokens: nil,
                        tools: ["Read", "Write", "Edit"],
                        canInterrupt: false,
                        originalText: "⚒ Using tools: Read, Write, Edit",
                        sessionId: "test"
                    ))
                }
            
            Spacer()
        }
        .padding()
        .background(Self.systemGroupedBackgroundColor)
    }
}
#endif
