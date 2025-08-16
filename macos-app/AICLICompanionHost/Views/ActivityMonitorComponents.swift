//
//  ActivityMonitorComponents.swift
//  AICLICompanionHost
//
//  Small UI components for the Activity Monitor
//

import SwiftUI
import Charts

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        HStack {
            // Title and Status
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity Monitor")
                        .font(.headline)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(serverManager.isRunning ? Color.green : Color.red)
                            .frame(width: 6, height: 6)

                        Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Quick Stats
            HStack(spacing: 20) {
                StatItem(
                    label: "Sessions",
                    value: String(serverManager.activeSessions.count),
                    icon: "person.2.fill",
                    color: .blue
                )

                StatItem(
                    label: "Port",
                    value: String(serverManager.port),
                    icon: "network",
                    color: .green
                )

                StatItem(
                    label: "Health",
                    value: serverManager.serverHealth == .healthy ? "Good" : "Check",
                    icon: "heart.fill",
                    color: serverManager.serverHealth == .healthy ? .green : .orange
                )
            }
        }
        .padding()
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.headline)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Status Row
struct StatusRow: View {
    let label: String
    let value: String
    let icon: String?
    let color: Color

    init(label: String, value: String, color: Color) {
        self.label = label
        self.value = value
        self.icon = nil
        self.color = color
    }

    init(label: String, value: String, icon: String, color: Color) {
        self.label = label
        self.value = value
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.caption)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }

                Text(value)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Logs Toolbar
struct LogsToolbar: View {
    @Binding var searchText: String
    @Binding var selectedLogLevel: LogLevel?
    @Binding var autoScroll: Bool
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            // Log Level Filter
            Picker("Level", selection: $selectedLogLevel) {
                Text("All").tag(nil as LogLevel?)
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Label(level.displayName, systemImage: level.icon)
                        .tag(level as LogLevel?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            Spacer()

            // Auto-scroll Toggle
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            // Clear Logs Button
            Button("Clear") {
                serverManager.clearLogs()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Log Entry View
struct LogEntryView: View {
    let log: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Level Icon
            Image(systemName: log.level.icon)
                .foregroundStyle(log.level.color)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                // Message
                Text(log.message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                // Metadata
                HStack {
                    Text(log.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if !log.category.isEmpty {
                        Text("•")
                            .foregroundStyle(.quaternary)

                        Text(log.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
