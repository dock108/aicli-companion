//
//  ActivityMonitorViewModel.swift
//  AICLICompanionHost
//
//  ViewModel for Activity Monitor functionality
//

import Foundation
import Combine
import SwiftUI

@MainActor
class ActivityMonitorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var sessions: [Session] = []
    @Published var serverHealth: ServerHealth = .unknown
    @Published var isRefreshing: Bool = false
    @Published var serverUptime: String = ""
    @Published var requestCount: Int = 0
    @Published var errorCount: Int = 0
    @Published var averageResponseTime: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var cpuUsage: Double = 0

    // MARK: - Properties
    private let serverManager = ServerManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    // MARK: - Computed Properties
    var healthColor: Color {
        switch serverHealth {
        case .healthy:
            return .green
        case .unhealthy:
            return .red
        case .unknown:
            return .gray
        }
    }

    var healthIcon: String {
        switch serverHealth {
        case .healthy:
            return "checkmark.circle.fill"
        case .unhealthy:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var activeSessions: [Session] {
        sessions // Simplified - all sessions are considered active
    }

    var totalSessions: Int {
        sessions.count
    }

    // MARK: - Initialization
    init() {
        setupBindings()
        startAutoRefresh()
    }

    // deinit removed - stopAutoRefresh needs to be called from MainActor

    // MARK: - Setup
    private func setupBindings() {
        // Bind to ServerManager properties
        serverManager.$activeSessions
            .receive(on: DispatchQueue.main)
            .assign(to: &$sessions)

        serverManager.$serverHealth
            .receive(on: DispatchQueue.main)
            .assign(to: &$serverHealth)

        // Uptime calculation removed - serverStartTime is not @Published
    }

    // MARK: - Public Methods
    func refreshData() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Refresh server status
        await serverManager.refreshStatus()

        // Fetch active sessions
        await serverManager.fetchActiveSessions()

        // Update metrics
        updateMetrics()
    }

    func exportLogs() -> URL? {
        let logs = serverManager.exportLogs()
        guard !logs.isEmpty else { return nil }

        let fileName = "server-logs-\(Date().timeIntervalSince1970).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try logs.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to export logs: \(error)")
            return nil
        }
    }

    func clearSessions() {
        sessions.removeAll()
        serverManager.activeSessions.removeAll()
    }

    func clearLogs() {
        serverManager.clearLogs()
    }

    func terminateSession(_ session: Session) async {
        // Send termination request to server
        // This would need server API implementation
        sessions.removeAll { $0.id == session.id }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { [weak self] in
                await self?.refreshData()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Private Methods

    private func updateMetrics() {
        // Calculate metrics from logs and sessions
        let recentLogs = serverManager.logs.suffix(100)

        // Count errors
        errorCount = recentLogs.filter { $0.level == .error }.count

        // Count requests (this would need proper tracking)
        requestCount = recentLogs.filter {
            $0.message.contains("Request") || $0.message.contains("API")
        }.count

        // Mock response time (would need actual measurement)
        averageResponseTime = Double.random(in: 50...200)

        // Mock resource usage (would need actual measurement)
        memoryUsage = Double.random(in: 100...500)
        cpuUsage = Double.random(in: 5...25)
    }

    // MARK: - Chart Data
    func getRequestChartData() -> [(Date, Int)] {
        // Generate mock data for charts
        var data: [(Date, Int)] = []
        let now = Date()

        for index in 0..<10 {
            let date = now.addingTimeInterval(Double(-index * 60))
            let requests = Int.random(in: 10...50)
            data.append((date, requests))
        }

        return data.reversed()
    }

    func getResponseTimeChartData() -> [(Date, Double)] {
        // Generate mock data for response time chart
        var data: [(Date, Double)] = []
        let now = Date()

        for index in 0..<10 {
            let date = now.addingTimeInterval(Double(-index * 60))
            let responseTime = Double.random(in: 50...200)
            data.append((date, responseTime))
        }

        return data.reversed()
    }
}
