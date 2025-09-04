//
//  MockServerManager.swift
//  AICLICompanionHostTests
//
//  Mock server manager for unit testing without launching actual server processes
//

import Foundation
import Combine
@testable import AICLICompanionHost

@MainActor
class MockServerManager: ObservableObject {
    // MARK: - Published Properties (matching real ServerManager)
    @Published var isRunning = false
    @Published var port: Int = 3001
    @Published var localIP = "127.0.0.1"
    @Published var authToken: String?
    @Published var activeSessions: [Session] = []
    @Published var isProcessing = false
    @Published var serverHealth: ServerHealth = .unknown
    @Published var logs: [LogEntry] = []
    @Published var publicURL: String?

    // MARK: - Test Tracking Properties
    var startServerCalled = false
    var startServerCallCount = 0
    var startServerShouldThrow: Error?

    var stopServerCalled = false
    var stopServerCallCount = 0

    var restartServerCalled = false
    var restartServerCallCount = 0
    var restartServerShouldThrow: Error?

    var generateAuthTokenCalled = false
    var generateAuthTokenCallCount = 0

    var refreshStatusCalled = false
    var refreshStatusCallCount = 0

    // MARK: - Computed Properties
    var connectionString: String {
        guard isRunning else { return "" }

        if let publicURL = publicURL {
            return buildPublicConnectionString(from: publicURL)
        } else {
            return buildLocalConnectionString()
        }
    }

    var serverFullURL: String {
        publicURL ?? "http://\(localIP):\(port)"
    }

    var serverPID: Int32? {
        return isRunning ? 12345 : nil
    }

    // MARK: - Public Methods

    func startServer() async throws {
        startServerCalled = true
        startServerCallCount += 1

        if let error = startServerShouldThrow {
            throw error
        }

        isProcessing = true

        // Simulate server startup delay
        try await Task.sleep(for: .milliseconds(100))

        isRunning = true
        serverHealth = .healthy
        isProcessing = false

        // Add a log entry
        addLog(.info, "Mock server started on port \(port)")
    }

    func stopServer() async {
        stopServerCalled = true
        stopServerCallCount += 1

        isProcessing = true

        // Simulate server shutdown delay
        try? await Task.sleep(for: .milliseconds(50))

        isRunning = false
        serverHealth = .unknown
        activeSessions.removeAll()
        publicURL = nil
        isProcessing = false

        addLog(.info, "Mock server stopped")
    }

    func restartServerWithCurrentConfig() async throws {
        restartServerCalled = true
        restartServerCallCount += 1

        if let error = restartServerShouldThrow {
            throw error
        }

        await stopServer()
        try await startServer()
    }

    func generateAuthToken() {
        generateAuthTokenCalled = true
        generateAuthTokenCallCount += 1

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        authToken = token

        addLog(.info, "Generated mock auth token")
    }

    func refreshStatus() async {
        refreshStatusCalled = true
        refreshStatusCallCount += 1

        isProcessing = true

        // Simulate status check delay
        try? await Task.sleep(for: .milliseconds(50))

        if isRunning {
            serverHealth = .healthy
            // Simulate some active sessions
            activeSessions = [
                Session(sessionId: "mock-session-1", deviceName: "Mock Device 1", connectedAt: Date(), signalStrength: 0.9),
                Session(sessionId: "mock-session-2", deviceName: "Mock Device 2", connectedAt: Date(), signalStrength: 0.7)
            ]
        }

        isProcessing = false
    }

    func addLog(_ level: AICLICompanionHost.LogLevel, _ message: String) {
        let logEntry = LogEntry(level: level, message: message)
        logs.append(logEntry)
    }

    // MARK: - Private Helper Methods

    private func buildPublicConnectionString(from publicURL: String) -> String {
        let wsURL = convertToWebSocketURL(publicURL)
        return addAuthTokenToURL(wsURL)
    }

    private func buildLocalConnectionString() -> String {
        let baseURL = "ws://\(localIP):\(port)/ws"
        return addAuthTokenToURL(baseURL)
    }

    private func convertToWebSocketURL(_ url: String) -> String {
        var wsURL = url
        if url.hasPrefix("https://") {
            wsURL = url.replacingOccurrences(of: "https://", with: "wss://")
        } else if url.hasPrefix("http://") {
            wsURL = url.replacingOccurrences(of: "http://", with: "ws://")
        }

        if !wsURL.contains("/ws") {
            wsURL = wsURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/ws"
        }

        return wsURL
    }

    private func addAuthTokenToURL(_ baseURL: String) -> String {
        guard let token = authToken else {
            return baseURL
        }

        let separator = baseURL.contains("?") ? "&" : "?"
        return "\(baseURL)\(separator)token=\(token)"
    }

    // MARK: - Test Helpers

    func reset() {
        isRunning = false
        port = 3001
        localIP = "127.0.0.1"
        authToken = nil
        activeSessions = []
        isProcessing = false
        serverHealth = .unknown
        logs = []
        publicURL = nil

        startServerCalled = false
        startServerCallCount = 0
        startServerShouldThrow = nil

        stopServerCalled = false
        stopServerCallCount = 0

        restartServerCalled = false
        restartServerCallCount = 0
        restartServerShouldThrow = nil

        generateAuthTokenCalled = false
        generateAuthTokenCallCount = 0

        refreshStatusCalled = false
        refreshStatusCallCount = 0
    }
}
