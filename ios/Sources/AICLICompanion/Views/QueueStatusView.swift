import SwiftUI
#if os(iOS)
import UIKit
#endif

/// View displaying message queue status and controls
@available(iOS 16.0, macOS 13.0, *)
struct QueueStatusView: View {
    @StateObject private var queueService = MessageQueueService.shared
    let sessionId: String
    
    @State private var showingMessages = false
    @State private var showingDeadLetter = false
    @State private var selectedMessage: MessageQueueService.QueuedMessage?
    
    var body: some View {
        VStack(spacing: 16) {
            // Queue Status Card
            if let status = queueService.queueStatus?.queue {
                StatusCard(status: status)
                    .padding(.horizontal)
                
                // Control Buttons
                ControlButtons(
                    sessionId: sessionId,
                    isPaused: status.paused,
                    isProcessing: status.processing,
                    queueService: queueService
                )
                .padding(.horizontal)
                
                // Message Lists
                if !queueService.queuedMessages.isEmpty {
                    MessageSection(
                        title: "Queued Messages (\(queueService.queuedMessages.count))",
                        messages: queueService.queuedMessages,
                        isExpanded: $showingMessages,
                        selectedMessage: $selectedMessage,
                        sessionId: sessionId,
                        queueService: queueService
                    )
                }
                
                if !queueService.deadLetterMessages.isEmpty {
                    MessageSection(
                        title: "Failed Messages (\(queueService.deadLetterMessages.count))",
                        messages: queueService.deadLetterMessages,
                        isExpanded: $showingDeadLetter,
                        selectedMessage: $selectedMessage,
                        sessionId: sessionId,
                        queueService: queueService,
                        isDeadLetter: true
                    )
                }
            } else if queueService.isLoading {
                ProgressView("Loading queue status...")
                    .padding()
            } else {
                EmptyQueueView()
                    .padding()
            }
        }
        .task {
            await queueService.fetchQueueStatus(for: sessionId)
            queueService.startMonitoring(sessionId: sessionId)
        }
        .onDisappear {
            queueService.stopMonitoring()
        }
        .refreshable {
            await queueService.fetchQueueStatus(for: sessionId)
        }
    }
}

// MARK: - Status Card

@available(iOS 16.0, macOS 13.0, *)
struct StatusCard: View {
    let status: MessageQueueService.QueueStatus.QueueInfo
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Queue Status", systemImage: "tray.2.fill")
                    .font(.headline)
                Spacer()
                StatusBadge(isProcessing: status.processing, isPaused: status.paused)
            }
            
            Divider()
            
            HStack(spacing: 20) {
                StatItem(
                    title: "Queued",
                    value: "\(status.length)",
                    color: .blue
                )
                
                StatItem(
                    title: "Processed",
                    value: "\(status.stats.messagesProcessed)",
                    color: .green
                )
                
                StatItem(
                    title: "Failed",
                    value: "\(status.stats.messagesFailed)",
                    color: .red
                )
                
                if status.deadLetterQueueSize > 0 {
                    StatItem(
                        title: "DLQ",
                        value: "\(status.deadLetterQueueSize)",
                        color: .orange
                    )
                }
            }
            
            if status.stats.averageProcessingTime > 0 {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Avg processing: \(String(format: "%.1fs", status.stats.averageProcessingTime / 1000))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        #else
        .background(Color(.windowBackgroundColor))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Control Buttons

@available(iOS 16.0, macOS 13.0, *)
struct ControlButtons: View {
    let sessionId: String
    let isPaused: Bool
    let isProcessing: Bool
    let queueService: MessageQueueService
    
    @State private var isPerformingAction = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Pause/Resume Button
            Button(action: {
                Task {
                    isPerformingAction = true
                    if isPaused {
                        _ = await queueService.resumeQueue(for: sessionId)
                    } else {
                        _ = await queueService.pauseQueue(for: sessionId)
                    }
                    isPerformingAction = false
                }
            }) {
                Label(
                    isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isPaused ? .green : .orange)
            .disabled(isPerformingAction)
            
            // Clear Queue Button
            Button(action: {
                Task {
                    isPerformingAction = true
                    _ = await queueService.clearQueue(for: sessionId)
                    isPerformingAction = false
                }
            }) {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isPerformingAction || isProcessing)
        }
    }
}

// MARK: - Message Section

@available(iOS 16.0, macOS 13.0, *)
struct MessageSection: View {
    let title: String
    let messages: [MessageQueueService.QueuedMessage]
    @Binding var isExpanded: Bool
    @Binding var selectedMessage: MessageQueueService.QueuedMessage?
    let sessionId: String
    let queueService: MessageQueueService
    var isDeadLetter: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            
            if isExpanded {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            QueueMessageRow(
                                message: message,
                                sessionId: sessionId,
                                queueService: queueService,
                                isDeadLetter: isDeadLetter
                            )
                            .onTapGesture {
                                selectedMessage = message
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
        }
    }
}

// MARK: - Message Row

@available(iOS 16.0, macOS 13.0, *)
struct QueueMessageRow: View {
    let message: MessageQueueService.QueuedMessage
    let sessionId: String
    let queueService: MessageQueueService
    let isDeadLetter: Bool
    
    @State private var showingPriorityMenu = false
    
    var body: some View {
        HStack {
            // Priority Indicator
            Image(systemName: message.prioritySymbol)
                .foregroundColor(Color(message.priorityColor))
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.id)
                    .font(.caption)
                    .lineLimit(1)
                
                HStack {
                    Text(message.status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if message.attempts > 0 {
                        Text("Attempts: \(message.attempts)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                if let error = message.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if !isDeadLetter {
                Menu {
                    ForEach([0, 1, 2], id: \.self) { priority in
                        Button(action: {
                            Task {
                                _ = await queueService.updateMessagePriority(
                                    sessionId: sessionId,
                                    messageId: message.id,
                                    priority: priority
                                )
                            }
                        }) {
                            Label(
                                MessageQueueService.MessagePriority(rawValue: priority)?.name ?? "",
                                systemImage: MessageQueueService.MessagePriority(rawValue: priority)?.symbol ?? ""
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(.controlBackgroundColor))
        #endif
        .cornerRadius(8)
    }
}

// MARK: - Helper Views

@available(iOS 16.0, macOS 13.0, *)
struct StatusBadge: View {
    let isProcessing: Bool
    let isPaused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(12)
    }
    
    var statusColor: Color {
        if isPaused { return .orange }
        if isProcessing { return .green }
        return .gray
    }
    
    var statusText: String {
        if isPaused { return "Paused" }
        if isProcessing { return "Processing" }
        return "Idle"
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct StatItem: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No messages in queue")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Messages will appear here when queued")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
