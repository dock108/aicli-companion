import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Compact queue status bar shown in chat view
@available(iOS 16.0, macOS 13.0, *)
struct QueueStatusBar: View {
    let sessionId: String
    @Binding var showingDetails: Bool
    @StateObject private var queueService = MessageQueueService.shared
    
    var body: some View {
        if let status = queueService.queueStatus?.queue, status.length > 0 {
            Button(action: { showingDetails = true }) {
                HStack(spacing: 12) {
                    // Status indicator
                    HStack(spacing: 6) {
                        if status.processing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "tray.2.fill")
                                .font(.system(size: 14))
                                .foregroundColor(status.paused ? .orange : .blue)
                        }
                        
                        Text("\(status.length) queued")
                            .font(.system(size: 13, weight: .medium))
                    }
                    
                    Spacer()
                    
                    // Quick stats
                    HStack(spacing: 16) {
                        if status.paused {
                            Label("Paused", systemImage: "pause.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if status.stats.messagesFailed > 0 {
                            Label("\(status.stats.messagesFailed)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                #if os(iOS)
                .background(Color(UIColor.secondarySystemBackground))
                #else
                .background(Color(.controlBackgroundColor))
                #endif
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .task {
                await queueService.fetchQueueStatus(for: sessionId)
            }
        }
    }
}
