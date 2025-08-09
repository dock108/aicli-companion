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
    @Published var publicURL: String?

    // MARK: - Private Properties
    private var serverProcess: Process?
    private var healthCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let serverURL = "http://localhost"

    // MARK: - Computed Properties
    var connectionString: String {
        guard isRunning else { return "" }
        
        // Use public URL if available (when tunneling is active)
        let baseURL = publicURL ?? "http://\(localIP):\(port)"
        
        if let token = authToken, SettingsManager.shared.requireAuthentication {
            // For public URLs, append token as query parameter
            if publicURL != nil {
                return "\(baseURL)?token=\(token)"
            } else {
                // For local connections, use the local format
                return "\(localIP):\(port)?token=\(token)"
            }
        } else {
            // Return public URL if available, otherwise local
            return publicURL ?? "\(localIP):\(port)"
        }
    }

    var serverFullURL: String {
        // Return public URL if available, otherwise local URL
        publicURL ?? "http://\(localIP):\(port)"
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
    
    /// Restart server with current configuration, ensuring clean shutdown and startup
    func restartServerWithCurrentConfig() async throws {
        addLog(.info, "Restarting server with current configuration...")
        isProcessing = true
        defer { isProcessing = false }
        
        // Force stop any existing server
        await forceStopAnyServerOnPort()
        
        // Wait for cleanup
        try await Task.sleep(for: .milliseconds(1000))
        
        // Verify port is free
        let portFree = await isPortAvailable(port)
        if !portFree {
            addLog(.warning, "Port \(port) still in use after cleanup, attempting force kill...")
            await forceKillProcessOnPort(port)
            try await Task.sleep(for: .milliseconds(500))
        }
        
        // Start with current configuration
        try await startServer()
        addLog(.info, "Server restart completed successfully")
        
        // Mark configuration as applied
        await MainActor.run {
            SettingsManager.shared.markConfigurationApplied()
        }
    }
    
    func startServer() async throws {
        guard !isRunning else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Check if server is already running externally (quick check)
        addLog(.debug, "Checking for existing server at \(serverFullURL)")
        if await checkExternalServer() {
            // Server is running externally, just update our state
            addLog(.info, "Found existing server, connecting to it")
            isRunning = true
            startHealthChecking()
            await fetchServerStatus()
            return
        }
        addLog(.debug, "No existing server found, starting new instance")

        // Start the server process
        do {
            addLog(.info, "Launching server process...")
            try await launchServerProcess()
            isRunning = true
            addLog(.info, "Server process launched, starting health checks...")
            startHealthChecking()

            // Send notification (only if permissions granted)
            NotificationManager.shared.showNotification(
                title: "Server Started",
                body: "AICLI Companion server is now running on port \(port)"
            )

            // Log the event
            addLog(.info, "Server started successfully on port \(port)")
        } catch {
            addLog(.error, "Failed to start server: \(error.localizedDescription)")
            // Additional error details
            if let nsError = error as NSError? {
                addLog(.debug, "Error details: domain=\(nsError.domain), code=\(nsError.code)")
            }
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
        publicURL = nil

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
            body: "AICLI Companion server has been stopped"
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
    
    /// Force stop any server running on our configured port
    private func forceStopAnyServerOnPort() async {
        addLog(.debug, "Force stopping any server on port \(port)...")
        
        // First, try our normal stop process
        if isRunning {
            await stopServer()
        }
        
        // Then force kill any remaining processes on the port
        await forceKillProcessOnPort(port)
        
        // Reset our state
        serverProcess = nil
        isRunning = false
        publicURL = nil
        activeSessions.removeAll()
        serverHealth = .unknown
    }
    
    /// Force kill any process using the specified port
    private func forceKillProcessOnPort(_ port: Int) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-ti", ":\(port)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                
                for pid in pids where !pid.isEmpty {
                    addLog(.debug, "Killing process \(pid) using port \(port)")
                    let killTask = Process()
                    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killTask.arguments = ["-9", pid]
                    try? killTask.run()
                    killTask.waitUntilExit()
                }
            }
        } catch {
            addLog(.debug, "Could not kill processes on port \(port): \(error)")
        }
    }
    
    /// Check if a port is available
    private func isPortAvailable(_ port: Int) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-i", ":\(port)"]
        
        do {
            try task.run()
            task.waitUntilExit()
            // lsof returns 0 if processes are found, 1 if none found
            return task.terminationStatus != 0
        } catch {
            // If lsof fails, assume port is available
            return true
        }
    }
    
    /// Build server environment variables from current settings
    private func buildServerEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = String(port)
        environment["PATH"] = "/Users/michaelfuscoletti/.nvm/versions/node/v22.18.0/bin:/usr/local/bin:/usr/bin:/bin"
        
        // Configure authentication based on settings
        let requireAuth = SettingsManager.shared.requireAuthentication || SettingsManager.shared.enableTunnel
        environment["AUTH_REQUIRED"] = requireAuth ? "true" : "false"
        
        if requireAuth {
            // Generate token if we don't have one
            if authToken == nil {
                generateAuthToken()
            }
            
            if let token = authToken {
                environment["AUTH_TOKEN"] = token
                addLog(.info, "Starting server with authentication enabled")
            }
        } else {
            addLog(.info, "Starting server without authentication")
        }
        
        // Configure tunnel settings
        let enableTunnel = SettingsManager.shared.enableTunnel
        environment["ENABLE_TUNNEL"] = enableTunnel ? "true" : "false"
        
        if enableTunnel {
            environment["TUNNEL_PROVIDER"] = SettingsManager.shared.tunnelProvider
            
            if SettingsManager.shared.tunnelProvider == "ngrok" {
                let ngrokToken = SettingsManager.shared.ngrokAuthToken
                if !ngrokToken.isEmpty {
                    environment["NGROK_AUTH_TOKEN"] = ngrokToken
                    // Log first 8 chars for debugging (masked for security)
                    let maskedToken = String(ngrokToken.prefix(8)) + "...****"
                    addLog(.info, "Starting server with ngrok tunnel enabled (token: \(maskedToken))")
                } else {
                    addLog(.warning, "ngrok auth token not configured - tunnel may fail")
                }
            }
            
            addLog(.debug, "Tunnel configuration: provider=\(SettingsManager.shared.tunnelProvider), enabled=\(enableTunnel)")
        }
        
        // Pass the configured server directory to use for projects
        let serverDir = SettingsManager.shared.serverDirectory
        if !serverDir.isEmpty {
            environment["CONFIG_PATH"] = serverDir
        }
        
        return environment
    }
    
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

        // Use centralized environment building
        let environment = buildServerEnvironment()
        task.environment = environment
        
        // Debug log environment variables (masked sensitive ones)
        addLog(.debug, "Environment variables set:")
        for (key, value) in environment {
            if key.contains("TOKEN") {
                let maskedValue = value.count > 8 ? String(value.prefix(8)) + "...****" : "****"
                addLog(.debug, "  \(key)=\(maskedValue)")
            } else {
                addLog(.debug, "  \(key)=\(value)")
            }
        }

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
                    self?.addLog(.error, "Server stderr: \(output)")
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
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0  // Quick check - don't wait long
            
            let (_, response) = try await URLSession.shared.data(for: request)
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            if success {
                addLog(.info, "Found existing server running externally")
            }
            return success
        } catch {
            // This is normal - no external server running
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
            } else if line.contains("Public URL:") || line.contains("Tunnel URL:") || line.contains("Ngrok tunnel established:") {
                // Extract tunnel URL
                if let urlRange = line.range(of: "https?://[^\\s]+", options: .regularExpression) {
                    let extractedURL = String(line[urlRange])
                    publicURL = extractedURL
                    addLog(.info, "Tunnel established: \(extractedURL)")
                }
            } else if line.contains("ngrok") || line.contains("tunnel") {
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

    func addLog(_ level: LogLevel, _ message: String) {
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
