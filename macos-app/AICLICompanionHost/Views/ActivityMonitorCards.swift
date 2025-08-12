//
//  ActivityMonitorCards.swift
//  AICLICompanionHost
//
//  Card views for the Activity Monitor
//

import SwiftUI
import Charts

// MARK: - Server Status Card
struct ServerStatusCard: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        GroupBox("Server Status") {
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    label: "Status",
                    value: serverManager.isRunning ? "Running" : "Stopped",
                    color: serverManager.isRunning ? .green : .red
                )

                StatusRow(
                    label: "Health",
                    value: healthString,
                    color: healthColor
                )

                StatusRow(
                    label: "Uptime",
                    value: formatUptime(serverManager.serverStartTime),
                    color: .blue
                )

                if let token = serverManager.authToken {
                    StatusRow(
                        label: "Auth Token",
                        value: String(token.prefix(8)) + "...",
                        color: .purple
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var healthString: String {
        switch serverManager.serverHealth {
        case .healthy: return "Healthy"
        case .unhealthy: return "Unhealthy"
        case .unknown: return "Unknown"
        }
    }

    private var healthColor: Color {
        switch serverManager.serverHealth {
        case .healthy: return .green
        case .unhealthy: return .red
        case .unknown: return .gray
        }
    }

    private func formatUptime(_ startTime: Date?) -> String {
        guard let startTime = startTime else { return "Not running" }

        let interval = Date().timeIntervalSince(startTime)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Connection Info Card
struct ConnectionInfoCard: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        GroupBox("Connection Info") {
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "Local IP", value: serverManager.localIP)
                InfoRow(label: "Port", value: String(serverManager.port))
                InfoRow(label: "Full URL", value: serverManager.serverFullURL)

                if !serverManager.connectionString.isEmpty {
                    HStack {
                        Text("Connection String")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(serverManager.connectionString)
                            .fontDesign(.monospaced)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Recent Activity Card
struct RecentActivityCard: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        GroupBox("Recent Activity") {
            if serverManager.logs.isEmpty {
                Text("No recent activity")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentLogs.prefix(5)) { log in
                        HStack(spacing: 8) {
                            Image(systemName: log.level.icon)
                                .foregroundStyle(log.level.color)
                                .font(.caption)
                                .frame(width: 12)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.message)
                                    .font(.caption)
                                    .lineLimit(2)

                                Text(log.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var recentLogs: [LogEntry] {
        Array(serverManager.logs.suffix(10).reversed())
    }
}

// MARK: - Session Detail Card
struct SessionDetailCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.deviceName)
                        .font(.headline)

                    Text("Session \(session.sessionId.prefix(8))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Text(session.connectedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Details
            VStack(alignment: .leading, spacing: 8) {
                SessionInfoRow(label: "Device", value: session.deviceName)
                SessionInfoRow(label: "Session ID", value: session.sessionId)
                SessionInfoRow(label: "Signal", value: String(format: "%.1f%%", session.signalStrength * 100))
                SessionInfoRow(label: "Connected", value: formatLastActivity(session.connectedAt))

                // Attachment indicator
                if session.hasAttachments {
                    SessionInfoRow(
                        label: "Attachments",
                        value: "\(session.attachmentCount) file(s)",
                        icon: "paperclip",
                        color: .blue
                    )
                }

                // Auto-response indicator
                if session.autoResponseActive {
                    SessionInfoRow(
                        label: "Auto-Response",
                        value: "Active (Iteration \(session.autoResponseIteration))",
                        icon: "play.circle.fill",
                        color: .green
                    )
                }

                // Thinking indicator
                if session.isThinking {
                    SessionInfoRow(
                        label: session.thinkingActivity ?? "Thinking",
                        value: formatThinkingInfo(duration: session.thinkingDuration, tokens: session.tokenCount),
                        icon: "brain",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatLastActivity(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatThinkingInfo(duration: Int, tokens: Int) -> String {
        var parts: [String] = []

        if duration > 0 {
            parts.append("\(duration)s")
        }

        if tokens > 0 {
            let tokenText = tokens > 1000
                ? "\((Double(tokens) / 1000.0).formatted(.number.precision(.fractionLength(1))))k"
                : "\(tokens)"
            parts.append("\(tokenText) tokens")
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - Network Stats Card
struct NetworkStatsCard: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                StatusRow(
                    label: "Active Sessions",
                    value: String(serverManager.activeSessions.count),
                    icon: "person.2.fill",
                    color: .blue
                )

                StatusRow(
                    label: "Server Port",
                    value: String(serverManager.port),
                    icon: "network",
                    color: .green
                )

                StatusRow(
                    label: "Status",
                    value: serverManager.isRunning ? "Online" : "Offline",
                    icon: serverManager.isRunning ? "checkmark.circle" : "xmark.circle",
                    color: serverManager.isRunning ? .green : .red
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Session Info Row
private struct SessionInfoRow: View {
    let label: String
    let value: String
    var icon: String?
    var color: Color = .primary

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 16)
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(1)

            Spacer()
        }
    }
}
