//
//  ServerManagerLogging.swift
//  AICLICompanionHost
//
//  Logging functionality for ServerManager
//

import Foundation

extension ServerManager {

    // MARK: - Logging

    func addLog(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message
        )

        logs.append(entry)

        // Trim logs if exceeding max entries
        let maxEntries = SettingsManager.shared.maxLogEntries
        if logs.count > maxEntries {
            logs = Array(logs.suffix(maxEntries))
        }

        // Also print to console for debugging
        #if DEBUG
        print("[\(level)] \(message)")
        #endif
    }

    func clearLogs() {
        logs.removeAll()
        addLog(.info, "Logs cleared")
    }

    // MARK: - Log Level Filtering

    func getFilteredLogs(level: LogLevel? = nil, searchText: String = "") -> [LogEntry] {
        var filtered = logs

        // Filter by level if specified
        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        // Filter by search text if provided
        if !searchText.isEmpty {
            filtered = filtered.filter { log in
                log.message.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    // MARK: - Log Export

    func exportLogs() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return logs.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let levelString = logLevelString(entry.level)
            return "[\(timestamp)] [\(levelString)] \(entry.message)"
        }.joined(separator: "\n")
    }

    private func logLevelString(_ level: LogLevel) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}
