//
//  ActivityMonitorView.swift
//  ClaudeCompanionHost
//
//  Real-time activity monitoring and log viewer
//

import SwiftUI
import Charts

struct ActivityMonitorView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var selectedLogLevel: LogLevel?
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Tab Selection
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Sessions").tag(1)
                Text("Logs").tag(2)
                Text("Performance").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab Content
            switch selectedTab {
            case 0:
                OverviewTab()
            case 1:
                SessionsTab()
            case 2:
                LogsTab(
                    searchText: $searchText,
                    selectedLogLevel: $selectedLogLevel,
                    autoScroll: $autoScroll
                )
            case 3:
                PerformanceTab()
            default:
                EmptyView()
            }
        }
        .frame(width: 800, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

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

// MARK: - Overview Tab
struct OverviewTab: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Server Status Card
                ServerStatusCard()

                // Connection Info Card
                ConnectionInfoCard()

                // Recent Activity Card
                RecentActivityCard()
            }
            .padding()
        }
    }
}

// MARK: - Sessions Tab
struct SessionsTab: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        if serverManager.activeSessions.isEmpty {
            ContentUnavailableView(
                "No Active Sessions",
                systemImage: "person.2.slash",
                description: Text("Connected clients will appear here")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(serverManager.activeSessions) { session in
                        SessionDetailCard(session: session)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Logs Tab
struct LogsTab: View {
    @EnvironmentObject private var serverManager: ServerManager
    @Binding var searchText: String
    @Binding var selectedLogLevel: LogLevel?
    @Binding var autoScroll: Bool

    var filteredLogs: [LogEntry] {
        serverManager.logs.filter { log in
            let matchesSearch = searchText.isEmpty ||
                log.message.localizedCaseInsensitiveContains(searchText)
            let matchesLevel = selectedLogLevel == nil || log.level == selectedLogLevel
            return matchesSearch && matchesLevel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            LogsToolbar(
                searchText: $searchText,
                selectedLogLevel: $selectedLogLevel,
                autoScroll: $autoScroll
            )

            Divider()

            // Logs List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLogs) { log in
                            LogEntryView(log: log)
                                .id(log.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: filteredLogs.count) { _, _ in
                    if autoScroll, let lastLog = filteredLogs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Performance Tab
struct PerformanceTab: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // CPU Usage Chart
                PerformanceChart(
                    title: "CPU Usage",
                    data: cpuHistory,
                    color: .blue,
                    unit: "%"
                )
                .frame(height: 200)

                // Memory Usage Chart
                PerformanceChart(
                    title: "Memory Usage",
                    data: memoryHistory,
                    color: .green,
                    unit: "MB"
                )
                .frame(height: 200)

                // Network Stats
                NetworkStatsCard()
            }
            .padding()
        }
        .onAppear {
            startPerformanceMonitoring()
        }
        .onDisappear {
            stopPerformanceMonitoring()
        }
    }

    private func startPerformanceMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Simulate performance data - in real app, fetch actual metrics
            let cpu = Double.random(in: 10...30)
            let memory = Double.random(in: 100...200)

            cpuHistory.append(cpu)
            memoryHistory.append(memory)

            // Keep last 60 data points
            if cpuHistory.count > 60 {
                cpuHistory.removeFirst()
                memoryHistory.removeFirst()
            }
        }
    }

    private func stopPerformanceMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Supporting Views
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
                    value: "2h 34m", // TODO: Calculate actual uptime
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
}

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

struct RecentActivityCard: View {
    @EnvironmentObject private var serverManager: ServerManager

    var recentLogs: [LogEntry] {
        Array(serverManager.logs.suffix(5))
    }

    var body: some View {
        GroupBox("Recent Activity") {
            if recentLogs.isEmpty {
                Text("No recent activity")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recentLogs) { log in
                        HStack {
                            Image(systemName: log.level.icon)
                                .foregroundStyle(Color(log.level.color))
                                .font(.caption)

                            Text(log.message)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            Text(log.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct SessionDetailCard: View {
    let session: Session

    var body: some View {
        GroupBox {
            HStack {
                // Device Icon
                Image(systemName: "iphone")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.deviceName)
                        .font(.headline)

                    Text("Session ID: \(session.sessionId)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)

                    HStack {
                        Label("Connected", systemImage: "clock")
                        Text(session.connectedAt, style: .relative)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Signal Strength
                VStack {
                    Image(systemName: "wifi", variableValue: session.signalStrength)
                        .font(.title2)
                        .foregroundStyle(.green)

                    Text("Signal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Actions
                Button {
                    // Disconnect session
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Disconnect Session")
            }
            .padding(.vertical, 4)
        }
    }
}

struct LogsToolbar: View {
    @Binding var searchText: String
    @Binding var selectedLogLevel: LogLevel?
    @Binding var autoScroll: Bool
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(width: 200)

            // Level Filter
            Picker("Level", selection: $selectedLogLevel) {
                Text("All").tag(nil as LogLevel?)
                Divider()
                Text("Debug").tag(LogLevel.debug as LogLevel?)
                Text("Info").tag(LogLevel.info as LogLevel?)
                Text("Warning").tag(LogLevel.warning as LogLevel?)
                Text("Error").tag(LogLevel.error as LogLevel?)
            }
            .pickerStyle(.menu)
            .frame(width: 100)

            Spacer()

            // Controls
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            Button("Clear") {
                serverManager.logs.removeAll()
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }
}

struct LogEntryView: View {
    let log: LogEntry
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(log.timestamp, style: .time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // PID
            Text("PID: \(getServerPID())")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)

            // Level Icon
            Image(systemName: log.level.icon)
                .foregroundStyle(Color(log.level.color))
                .font(.caption)
                .frame(width: 20)

            // Message
            Text(log.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            log.level == .error ? Color.red.opacity(0.1) : Color.clear
        )
    }

    // Removed getServerPID function; now using serverManager.serverPIDString
}

struct PerformanceChart: View {
    let title: String
    let data: [Double]
    let color: Color
    let unit: String

    var body: some View {
        GroupBox(title) {
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Performance data will appear here")
                )
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(color)

                    AreaMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis(.hidden)
            }
        }
    }
}

struct NetworkStatsCard: View {
    var body: some View {
        GroupBox("Network Statistics") {
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Requests/sec", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("42")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Avg Response Time", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("125ms")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Data Transferred", systemImage: "arrow.up.arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("1.2 MB")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Helper Views
struct StatusRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(value)
                    .fontWeight(.medium)
            }
        }
    }
}

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
