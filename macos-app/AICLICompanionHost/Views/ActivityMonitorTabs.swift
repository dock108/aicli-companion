//
//  ActivityMonitorTabs.swift
//  AICLICompanionHost
//
//  Tab views for the Activity Monitor
//

import SwiftUI
import Charts

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

    var body: some View {
        VStack(spacing: 0) {
            // Logs Toolbar
            LogsToolbar(
                searchText: $searchText,
                selectedLogLevel: $selectedLogLevel,
                autoScroll: $autoScroll
            )

            Divider()

            // Logs List
            logsList()
        }
    }

    @ViewBuilder
    private func logsList() -> some View {
        if filteredLogs.isEmpty {
            ContentUnavailableView(
                "No Logs",
                systemImage: "doc.text",
                description: Text(searchText.isEmpty ? "Server logs will appear here" : "No logs match your search")
            )
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredLogs) { log in
                        LogEntryView(log: log)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .id("bottom")
                }
                .listStyle(.plain)
                .onChange(of: filteredLogs.count) { _, _ in
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if autoScroll && !filteredLogs.isEmpty {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var filteredLogs: [LogEntry] {
        serverManager.logs.filter { log in
            let matchesSearch = searchText.isEmpty ||
                log.message.localizedCaseInsensitiveContains(searchText) ||
                log.category.localizedCaseInsensitiveContains(searchText)
            let matchesLevel = selectedLogLevel == nil || log.level == selectedLogLevel
            return matchesSearch && matchesLevel
        }
    }
}

// MARK: - Performance Tab
struct PerformanceTab: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Performance Chart
                PerformanceChart()

                HStack(spacing: 20) {
                    // Network Stats
                    NetworkStatsCard()

                    // System Stats (placeholder for future)
                    SystemStatsCard()
                }
            }
            .padding()
        }
    }
}

// Placeholder for system stats
private struct SystemStatsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                StatusRow(label: "Memory", value: "N/A", icon: "memorychip", color: .blue)
                StatusRow(label: "CPU", value: "N/A", icon: "cpu", color: .green)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
