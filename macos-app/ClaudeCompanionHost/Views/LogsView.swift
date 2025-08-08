//
//  LogsView.swift
//  ClaudeCompanionHost
//
//  Server logs viewer for debugging and monitoring
//

import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var selectedLogLevel: LogLevel?
    @State private var searchText = ""
    @State private var showingExportPicker = false
    @State private var autoScroll = true
    @State private var showLastMinutes = 10

    private var filteredLogs: [LogEntry] {
        let cutoffTime = Date().addingTimeInterval(-TimeInterval(showLastMinutes * 60))

        return serverManager.logs
            .filter { $0.timestamp >= cutoffTime }
            .filter { selectedLogLevel == nil || $0.level == selectedLogLevel }
            .filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.timestamp > $1.timestamp } // Most recent first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with controls
            VStack(alignment: .leading, spacing: 12) {
                Text("Server Logs")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Filter controls
                HStack {
                    // Time filter
                    HStack {
                        Text("Last")
                        Picker("Time Range", selection: $showLastMinutes) {
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("30 min").tag(30)
                            Text("1 hour").tag(60)
                            Text("All").tag(Int.max)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                    }

                    Spacer()

                    // Log level filter
                    HStack {
                        Text("Level:")
                        Picker("Log Level", selection: $selectedLogLevel) {
                            Text("All").tag(nil as LogLevel?)
                            Text("Debug").tag(LogLevel.debug)
                            Text("Info").tag(LogLevel.info)
                            Text("Warning").tag(LogLevel.warning)
                            Text("Error").tag(LogLevel.error)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                }

                // Search and controls
                HStack {
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)

                    Button("Export...") {
                        showingExportPicker = true
                    }
                    .buttonStyle(.borderless)

                    Button("Clear") {
                        clearLogs()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)

            // Logs list
            if filteredLogs.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No logs found")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Server logs will appear here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(filteredLogs) { log in
                        LogEntryRow(entry: log)
                            .id(log.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: filteredLogs.count) { _, newCount in
                        if autoScroll && newCount > 0 {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(filteredLogs.first?.id, anchor: .top)
                            }
                        }
                    }
                }
            }

            // Status bar
            HStack {
                Text("\(filteredLogs.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if serverManager.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Server Running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("Server Stopped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: LogsDocument(logs: filteredLogs),
            contentType: .plainText,
            defaultFilename: "claude-companion-logs-\(DateFormatter.filenameSafe.string(from: Date())).txt"
        ) { result in
            handleExport(result)
        }
    }

    private func clearLogs() {
        serverManager.clearLogs()
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            NotificationManager.shared.showNotification(
                title: "Logs Exported",
                body: "Server logs have been exported successfully"
            )

        case .failure(let error):
            print("Export failed: \(error)")
            NotificationManager.shared.showNotification(
                title: "Export Failed",
                body: error.localizedDescription
            )
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Level indicator
            Image(systemName: entry.level.icon)
                .foregroundStyle(colorForLevel(entry.level))
                .frame(width: 16)
                .font(.caption)

            // Timestamp
            Text(DateFormatter.logTime.string(from: entry.timestamp))
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // PID
            Text("PID: \(getServerPID())")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.caption)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }

            Button("Copy Full Entry") {
                let fullEntry = "\(DateFormatter.logTimestamp.string(from: entry.timestamp)) [\(entry.level)] \(entry.message)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullEntry, forType: .string)
            }
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    // getServerPID moved to ServerManager extension
}

// MARK: - Logs Document for Export

struct LogsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let logs: [LogEntry]

    init(logs: [LogEntry]) {
        self.logs = logs
    }

    init(configuration: ReadConfiguration) throws {
        // Not implemented - export only
        self.logs = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let content = logs.map { entry in
            "\(DateFormatter.logTimestamp.string(from: entry.timestamp)) [\(entry.level)] \(entry.message)"
        }.joined(separator: "\n")

        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Date Formatters

extension DateFormatter {
    static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let filenameSafe: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}
