import SwiftUI

/// Claude thinking indicator showing progress like "Creating... (1096s · ⚒ 27.7k tokens · esc to interrupt)"
@available(iOS 16.0, macOS 13.0, *)
struct ThinkingIndicator: View {
    let isVisible: Bool
    let duration: TimeInterval
    let tokenCount: Int
    let activity: String
    
    @Environment(\.colorScheme) var colorScheme
    @State private var pulseOpacity: Double = 0.3
    
    init(
        isVisible: Bool = false,
        duration: TimeInterval = 0,
        tokenCount: Int = 0,
        activity: String = "Thinking"
    ) {
        self.isVisible = isVisible
        self.duration = duration
        self.tokenCount = tokenCount
        self.activity = activity
    }
    
    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                // Animated thinking dots
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Colors.accentPrimaryEnd)
                            .frame(width: 6, height: 6)
                            .opacity(pulseOpacity)
                            .animation(
                                Animation.easeInOut(duration: 0.8)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.2),
                                value: pulseOpacity
                            )
                    }
                }
                
                // Activity text with stats
                Text(formattedText)
                    .font(Typography.font(.bodySmall))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .animation(.easeInOut(duration: 0.3), value: duration)
                    .animation(.easeInOut(duration: 0.3), value: tokenCount)
                
                // Interrupt hint
                if duration > 10 {
                    Text("• esc to interrupt")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme).opacity(0.7))
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Colors.bgCard(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Colors.accentPrimaryEnd.opacity(0.2), lineWidth: 1)
                    )
            )
            .onAppear {
                pulseOpacity = 1.0
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
    
    private var formattedText: String {
        let durationText = formatDuration(duration)
        let tokenText = formatTokenCount(tokenCount)
        
        if duration > 0 && tokenCount > 0 {
            return "\(activity)... (\(durationText) · ⚒ \(tokenText))"
        } else if duration > 0 {
            return "\(activity)... (\(durationText))"
        } else if tokenCount > 0 {
            return "\(activity)... (⚒ \(tokenText))"
        } else {
            return "\(activity)..."
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            let remainingSeconds = totalSeconds % 60
            return remainingSeconds > 0 ? "\(minutes)m \(remainingSeconds)s" : "\(minutes)m"
        } else {
            let hours = totalSeconds / 3600
            let remainingMinutes = (totalSeconds % 3600) / 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fk tokens", thousands)
        } else {
            return "\(count) tokens"
        }
    }
}

// MARK: - Thinking Activity Types

@available(iOS 16.0, macOS 13.0, *)
extension ThinkingIndicator {
    enum Activity {
        case thinking
        case creating
        case writing
        case analyzing
        case processing
        case generating
        case reviewing
        case planning
        
        var displayText: String {
            switch self {
            case .thinking: return "Thinking"
            case .creating: return "Creating"
            case .writing: return "Writing"
            case .analyzing: return "Analyzing"
            case .processing: return "Processing"
            case .generating: return "Generating"
            case .reviewing: return "Reviewing"
            case .planning: return "Planning"
            }
        }
    }
    
    init(
        isVisible: Bool = false,
        duration: TimeInterval = 0,
        tokenCount: Int = 0,
        activity: Activity = .thinking
    ) {
        self.init(
            isVisible: isVisible,
            duration: duration,
            tokenCount: tokenCount,
            activity: activity.displayText
        )
    }
}

// MARK: - Message Integration Extension

@available(iOS 16.0, macOS 13.0, *)
extension ThinkingIndicator {
    /// Create thinking indicator from message metadata
    init(from message: Message?) {
        guard let message = message,
              message.sender == .assistant,
              let metadata = message.metadata as? AICLIMessageMetadata else {
            self.init(
                isVisible: false,
                duration: 0,
                tokenCount: 0,
                activity: "Thinking"
            )
            return
        }
        
        // Check if this is a streaming/incomplete message
        let isStreaming = metadata.additionalInfo?["isStreaming"] as? Bool ?? false
        let isComplete = metadata.additionalInfo?["isComplete"] as? Bool ?? true
        
        if isStreaming || !isComplete {
            let tokenCount = metadata.additionalInfo?["tokenCount"] as? Int ?? 0
            let activity = metadata.additionalInfo?["activity"] as? String ?? "Thinking"
            
            self.init(
                isVisible: true,
                duration: metadata.duration,
                tokenCount: tokenCount,
                activity: activity
            )
        } else {
            self.init(
                isVisible: false,
                duration: 0,
                tokenCount: 0,
                activity: "Thinking"
            )
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Thinking States") {
    VStack(spacing: 16) {
        // Basic thinking
        ThinkingIndicator(
            isVisible: true,
            activity: "Thinking"
        )
        
        // With duration
        ThinkingIndicator(
            isVisible: true,
            duration: 45,
            activity: "Processing"
        )
        
        // With tokens
        ThinkingIndicator(
            isVisible: true,
            tokenCount: 1250,
            activity: "Writing"
        )
        
        // Full example (like from user's request)
        ThinkingIndicator(
            isVisible: true,
            duration: 1096,
            tokenCount: 27700,
            activity: "Creating"
        )
        
        // Long duration with interrupt hint
        ThinkingIndicator(
            isVisible: true,
            duration: 300,
            tokenCount: 5000,
            activity: "Analyzing"
        )
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}
