import SwiftUI

/// View that displays message queue status and indicators
@available(iOS 16.0, macOS 13.0, *)
struct MessageQueueIndicator: View {
    let queuedMessageCount: Int
    let isReceivingQueued: Bool
    let oldestQueuedTimestamp: Date?
    
    @State private var animationPhase = 0.0
    @Environment(\.colorScheme) var colorScheme
    
    @ViewBuilder
    var body: some View {
        if isReceivingQueued || queuedMessageCount > 0 {
            indicatorContent
        }
    }
    
    @ViewBuilder
    private var indicatorContent: some View {
        HStack(spacing: Spacing.sm) {
            // Animated indicator
            if isReceivingQueued {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                    .tint(Colors.accentWarning)
            }
            
            // Message count and info
            VStack(alignment: .leading, spacing: 2) {
                if queuedMessageCount > 0 {
                    messageCountText
                }
                
                if let timestamp = oldestQueuedTimestamp {
                    timestampText(timestamp)
                }
            }
            
            Spacer()
        }
        .padding(Spacing.sm)
        .background(indicatorBackground)
        .overlay(indicatorBorder)
        .padding(.horizontal, Spacing.md)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    private var messageCountText: some View {
        Text("\(queuedMessageCount) message\(queuedMessageCount == 1 ? "" : "s") queued")
            .font(Typography.font(.caption))
            .foregroundColor(Colors.textSecondary(for: colorScheme))
    }
    
    private func timestampText(_ timestamp: Date) -> some View {
        Text("Queued \(timestamp, style: .relative)")
            .font(Typography.font(.caption))
            .foregroundColor(Colors.textSecondary(for: colorScheme))
    }
    
    private var indicatorBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(Colors.accentWarning.opacity(0.15))
    }
    
    private var indicatorBorder: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm)
            .stroke(Colors.accentWarning.opacity(0.3), lineWidth: 1)
    }
}

/// Message cell enhancement to show queued status
@available(iOS 16.0, macOS 13.0, *)
struct QueuedMessageBadge: View {
    let deliveryDelay: TimeInterval
    
    private var isSignificantlyDelayed: Bool {
        deliveryDelay > 60 // More than 1 minute delay
    }
    
    var body: some View {
        if isSignificantlyDelayed {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 10))
                Text("Delayed \(formatDelay(deliveryDelay))")
                    .font(Typography.font(.caption))
            }
            .foregroundColor(Colors.accentWarning)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Colors.accentWarning.opacity(0.15))
            )
        }
    }
    
    private func formatDelay(_ delay: TimeInterval) -> String {
        if delay < 120 {
            return "\(Int(delay))s"
        } else if delay < 3600 {
            return "\(Int(delay / 60))m"
        } else {
            return "\(Int(delay / 3600))h"
        }
    }
}

/// Message metadata extension for queue information
@available(iOS 16.0, macOS 13.0, *)
extension Message {
    /// Time between when message was queued and when it was delivered
    var queueDeliveryDelay: TimeInterval? {
        guard let queuedAt = metadata?.queuedAt,
              let deliveredAt = metadata?.deliveredAt else {
            return nil
        }
        return deliveredAt.timeIntervalSince(queuedAt)
    }
    
    /// Whether this message was delivered from queue
    var wasQueued: Bool {
        metadata?.queuedAt != nil
    }
}

/// Enhanced message cell with queue indicators
@available(iOS 16.0, macOS 13.0, *)
struct QueueAwareMessageCell: View {
    let message: Message
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
            // Queue badge if delayed significantly
            if let delay = message.queueDeliveryDelay, delay > 60 {
                QueuedMessageBadge(deliveryDelay: delay)
            }
            
            // Regular message bubble
            MessageBubble(message: message)
            
            // Timestamp with queue indicator
            HStack(spacing: 4) {
                if message.wasQueued {
                    Image(systemName: "tray.full")
                        .font(.system(size: 10))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Text(message.timestamp, style: .time)
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }
}

/// Message ordering helper for queued messages
@available(iOS 16.0, macOS 13.0, *)
struct MessageQueueOrganizer {
    /// Sort messages considering both timestamp and queue delivery order
    static func sortMessages(_ messages: [Message]) -> [Message] {
        return messages.sorted { msg1, msg2 in
            // First, sort by original timestamp
            if msg1.timestamp != msg2.timestamp {
                return msg1.timestamp < msg2.timestamp
            }
            
            // If timestamps are equal, prioritize non-queued messages
            if msg1.wasQueued != msg2.wasQueued {
                return !msg1.wasQueued
            }
            
            // Finally, sort by delivery time if both are queued
            if let delivery1 = msg1.metadata?.deliveredAt,
               let delivery2 = msg2.metadata?.deliveredAt {
                return delivery1 < delivery2
            }
            
            return true
        }
    }
    
    /// Group consecutive queued messages for batch display
    static func groupQueuedMessages(_ messages: [Message]) -> [[Message]] {
        var groups: [[Message]] = []
        var currentGroup: [Message] = []
        var lastWasQueued = false
        
        for message in messages {
            if message.wasQueued == lastWasQueued {
                currentGroup.append(message)
            } else {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [message]
                lastWasQueued = message.wasQueued
            }
        }
        
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
}
