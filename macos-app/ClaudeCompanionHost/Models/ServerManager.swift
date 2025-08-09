//
//  ServerManager.swift
//  ClaudeCompanionHost
//
//  Manages the Claude Companion server lifecycle
//

import Foundation
import Combine
import Network

@MainActor
class ServerManager: ObservableObject {
    static let shared = ServerManager()

    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var port: Int = 3001
    @Published var localIP = "127.0.0.1"
    @Published var authToken: String?
    @Published var activeSessions: [Session] = []
    @Published var isProcessing = false
    @Published var serverHealth: ServerHealth = .unknown
    @Published var logs: [LogEntry] = []

    // MARK: - Private Properties
    private var serverProcess: Process?
    private var healthCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let serverURL = "http://localhost"

    // MARK: - Computed Properties
    var connectionString: String {
        guard isRunning else { return "" }
        if let token = authToken, SettingsManager.shared.requireAuthentication {
            return "\(localIP):\(port)?token=\(token)"
        } else {
            return "\(localIP):\(port)"
        }
    }

    var serverFullURL: String {
        "http://\(localIP):\(port)"
    }

    var serverPID: Int32? {
        return serverProcess?.processIdentifier
    }

    // MARK: - Initialization
    private init() {
        setupNetworkMonitoring()
        loadSettings()
    }

    // MARK: - Public Methods
    func startServer() async throws {
        guard !isRunning else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Check if server is already running externally
        if await checkExternalServer() {
            // Server is running externally, just update our state
            isRunning = true
            startHealthChecking()
            await fetchServerStatus()
            return
        }

        // Start the server process
        do {
            try await launchServerProcess()
            isRunning = true
            startHealthChecking()

            // Send notification
            NotificationManager.shared.showNotification(
                title: "Server Started",
                body: "Claude Companion server is now running on port \(port)"
            )

            // Log the event
            addLog(.info, "Server started successfully on port \(port)")
        } catch {
            addLog(.error, "Failed to start server: \(error.localizedDescription)")
            throw error
        }
    }

    func stopServer() async {
        guard isRunning else { return }

        isProcessing = true

        // Stop health checking immediately
        stopHealthChecking()

        // Update state immediately to prevent any new requests
        isRunning = false
        serverHealth = .unknown
        activeSessions.removeAll()

        defer {
            isProcessing = false
        }

        // Check if this is our process or external
        if let process = serverProcess {
            // Our process - terminate it
            process.terminate()
            try? await Task.sleep(for: .seconds(0.5))

            if process.isRunning {
                process.interrupt()
            }

            serverProcess = nil
        }
        // Removed shutdown request for external process - just stop tracking it

        // Send notification
        NotificationManager.shared.showNotification(
            title: "Server Stopped",
            body: "Claude Companion server has been stopped"
        )

        addLog(.info, "Server stopped")
    }

    func generateAuthToken() {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        authToken = token
        KeychainManager.shared.saveAuthToken(token)

        addLog(.info, "Generated new authentication token")
    }

    func refreshStatus() async {
        isProcessing = true
        defer { isProcessing = false }

        await fetchServerStatus()
    }

    // MARK: - Private Methods
    private func setupNetworkMonitoring() {
        // Subscribe to network changes
        NetworkMonitor.shared.$localIP
            .assign(to: &$localIP)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        port = defaults.integer(forKey: "serverPort") == 0 ? 3001 : defaults.integer(forKey: "serverPort")
        authToken = KeychainManager.shared.loadAuthToken()
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(port, forKey: "serverPort")
        if let token = authToken {
            KeychainManager.shared.saveAuthToken(token)
        }
    }

    private func launchServerProcess() async throws {
        let task = Process()

        // Try to find npm in common locations
        let npmPaths = [
            "/Users/michaelfuscoletti/.nvm/versions/node/v22.18.0/bin/npm",
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
            "/usr/bin/npm"
        ]

        var npmPath: String?
        for path in npmPaths {
            // swiftlint:disable:next for_where
            if FileManager.default.fileExists(atPath: path) {
                npmPath = path
                break
            }
        }

        guard let validNpmPath = npmPath else {
            throw NSError(domain: "ServerManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "npm not found. Please ensure Node.js is installed."
            ])
        }

        task.executableURL = URL(fileURLWithPath: validNpmPath)
        task.currentDirectoryURL = URL(fileURLWithPath: "/Users/michaelfuscoletti/Desktop/claude-companion/server")
        task.arguments = ["start"]

        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = String(port)
        // Add PATH to include node
        environment["PATH"] = "/Users/michaelfuscoletti/.nvm/versions/node/v22.18.0/bin:/usr/local/bin:/usr/bin:/bin"
        if let token = authToken {
            environment["AUTH_TOKEN"] = token
        }
        // Pass the configured server directory to use for projects
        let serverDir = SettingsManager.shared.serverDirectory
        if !serverDir.isEmpty {
            environment["CONFIG_PATH"] = serverDir
        }
        task.environment = environment

        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // Monitor output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processServerOutput(output)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.processServerError(output)
                }
            }
        }

        try task.run()
        serverProcess = task

        // Wait for server to be ready
        try await waitForServerReady()
    }

    private func waitForServerReady() async throws {
        for _ in 0..<30 { // 30 attempts, 1 second each
            // Use a simple health check without the isRunning guard
            if await checkServerHealthDuringStartup() {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw ServerError.startupTimeout
    }

    private func checkServerHealthDuringStartup() async -> Bool {
        // Use localhost for startup checks
        guard let url = URL(string: "http://localhost:\(port)/health") else { return false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0

            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func checkExternalServer() async -> Bool {
        guard let url = URL(string: "\(serverFullURL)/health") else { return false }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func checkServerHealth() async -> Bool {
        // Don't check if we know the server isn't running
        guard isRunning else {
            await MainActor.run {
                self.serverHealth = .unknown
            }
            return false
        }

        // Use localhost for local health checks
        guard let url = URL(string: "http://localhost:\(port)/health") else { return false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0 // Short timeout to prevent hanging

            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode == 200 {
                // Parse health data
                if let health = try? JSONDecoder().decode(HealthResponse.self, from: data) {
                    await MainActor.run {
                        self.serverHealth = health.status == "healthy" ? .healthy : .unhealthy
                        self.updateActiveSessions(from: health)
                    }
                }
                return true
            }
        } catch {
            // Only update to unhealthy if we think the server should be running
            if isRunning {
                await MainActor.run {
                    self.serverHealth = .unhealthy
                }
            }
        }

        return false
    }

    private func fetchServerStatus() async {
        // Only fetch if server is running
        guard isRunning else { return }
        guard let url = URL(string: "\(serverFullURL)/api/status") else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0

            let (data, _) = try await URLSession.shared.data(for: request)
            if let status = try? JSONDecoder().decode(ServerStatus.self, from: data) {
                await MainActor.run {
                    self.updateFromStatus(status)
                }
            }
        } catch {
            // Only log if we expect the server to be running
            if isRunning {
                addLog(.warning, "Could not fetch server status")
            }
        }
    }

    private func sendShutdownRequest() async {
        // Only send if we think server is running
        guard isRunning else { return }
        guard let url = URL(string: "\(serverFullURL)/api/shutdown") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            // Silently fail - server might already be stopped
        }
    }

    private func startHealthChecking() {
        stopHealthChecking()

        // Only start health checking if server is running
        guard isRunning else { return }

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            Task {
                await self.checkServerHealth()
            }
        }
    }

    private func stopHealthChecking() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    private func processServerOutput(_ output: String) {
        // Parse and handle server output
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            if line.contains("Server running") {
                addLog(.info, line)
            } else if line.contains("Session") {
                addLog(.info, line)
            } else {
                addLog(.debug, line)
            }
        }
    }

    private func processServerError(_ output: String) {
        addLog(.error, output)
    }

    private func updateActiveSessions(from health: HealthResponse) {
        // Update active sessions from health response
        if let sessions = health.activeSessions {
            self.activeSessions = sessions.map { sessionData in
                Session(
                    id: sessionData.sessionId,
                    sessionId: sessionData.sessionId,
                    deviceName: sessionData.deviceName ?? "Unknown Device",
                    connectedAt: Date(),
                    signalStrength: 1.0
                )
            }
        }
    }

    private func updateFromStatus(_ status: ServerStatus) {
        // Update state from server status
        if let sessions = status.sessions {
            self.activeSessions = sessions.map { sessionData in
                Session(
                    id: sessionData.id,
                    sessionId: sessionData.id,
                    deviceName: sessionData.name ?? "Unknown Device",
                    connectedAt: Date(),
                    signalStrength: 1.0
                )
            }
        }
    }

    func clearLogs() {
        logs.removeAll()
        addLog(.info, "Logs cleared by user")
    }

    private func addLog(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            message: message
        )

        logs.append(entry)

        // Keep only last 1000 logs
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }
}

// MARK: - Supporting Types
enum ServerHealth {
    case unknown
    case healthy
    case unhealthy
}

enum ServerError: LocalizedError {
    case startupTimeout
    case alreadyRunning
    case notRunning

    var errorDescription: String? {
        switch self {
        case .startupTimeout:
            return "Server failed to start within the timeout period"
        case .alreadyRunning:
            return "Server is already running"
        case .notRunning:
            return "Server is not running"
        }
    }
}

struct Session: Identifiable {
    let id: String
    let sessionId: String
    let deviceName: String
    let connectedAt: Date
    let signalStrength: Double
}

struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
}

enum LogLevel {
    case debug
    case info
    case warning
    case error

    var icon: String {
        switch self {
        case .debug: return "ant.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    var color: String {
        switch self {
        case .debug: return "gray"
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        }
    }
}

// MARK: - API Response Types
struct HealthResponse: Codable {
    let status: String
    let uptime: TimeInterval?
    let activeSessions: [SessionData]?
}

struct ServerStatus: Codable {
    let running: Bool
    let port: Int
    let sessions: [SessionInfo]?
}

struct SessionData: Codable {
    let sessionId: String
    let deviceName: String?
}

struct SessionInfo: Codable {
    let id: String
    let name: String?
}
