//
//  ServerManager.swift
//  AICLICompanionHost
//
//  Manages the AICLI Companion server lifecycle
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

    // MARK: - Internal Properties
    var serverProcess: Process?
    var healthCheckTimer: Timer?
    var cancellables = Set<AnyCancellable>()
    let serverURL = "http://localhost"
    var serverStartTime: Date?

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

    func startServer() async throws {
        guard !isRunning else { return }

        isProcessing = true
        defer { isProcessing = false }

        // Always kill any existing process on our port first
        addLog(.debug, "Checking for existing process on port \(port)...")
        if await !isPortAvailable(port) {
            addLog(.warning, "Port \(port) is in use, killing existing process...")
            await killProcessOnPort(port)
            // Wait for port to be released
            try await Task.sleep(for: .milliseconds(1000))
        }

        // Start the server process
        do {
            addLog(.info, "Launching server process...")
            try await startServerProcess()

            // Wait for server to actually be ready
            addLog(.info, "Waiting for server to become ready...")
            try await waitForServerReady()

            // Only NOW mark as running since we know it's actually ready
            isRunning = true
            serverStartTime = Date()
            addLog(.info, "Server is ready, starting health monitoring...")
            startHealthChecking()

            // Send notification (only if permissions granted)
            NotificationManager.shared.showNotification(
                title: "Server Started",
                body: "AICLI Companion server is now running on port \(port)"
            )

            // Log the event
            addLog(.info, "✅ Server started successfully on port \(port)")
        } catch {
            addLog(.error, "Failed to start server: \(error.localizedDescription)")
            
            // Clean up failed process
            if let process = serverProcess {
                if process.isRunning {
                    process.terminate()
                }
                serverProcess = nil
            }
            
            throw error
        }
    }

    func stopServer() async {
        addLog(.info, "Stopping server...")
        isProcessing = true

        // Stop health checking immediately
        stopHealthChecking()

        // Update state immediately to prevent any new requests
        isRunning = false
        serverHealth = .unknown
        activeSessions.removeAll()
        publicURL = nil
        serverStartTime = nil

        defer {
            isProcessing = false
        }

        // Stop our managed process if we have one
        if serverProcess != nil {
            await stopServerProcess()
        }
        
        // Always kill anything on our port to ensure clean state
        await killProcessOnPort(port)

        // Send notification
        NotificationManager.shared.showNotification(
            title: "Server Stopped",
            body: "AICLI Companion server has been stopped"
        )

        addLog(.info, "Server stopped")
    }

    /// Restart server with current configuration
    func restartServerWithCurrentConfig() async throws {
        addLog(.info, "🔄 Starting server restart process...")
        isProcessing = true
        defer { isProcessing = false }

        // Stop existing server
        addLog(.info, "Phase 1: Stopping existing server...")
        await stopServer()

        // Wait for cleanup
        addLog(.debug, "Phase 2: Waiting for cleanup...")
        try await Task.sleep(for: .milliseconds(2000))

        // Start server with new configuration
        addLog(.info, "Phase 3: Starting server with current configuration...")
        try await startServer()

        addLog(.info, "✅ Server restart completed successfully")

        // Mark configuration as applied
        await MainActor.run {
            SettingsManager.shared.markConfigurationApplied()
        }
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

    private func loadSettings() {
        port = SettingsManager.shared.serverPort
        authToken = KeychainManager.shared.loadAuthToken()

        if authToken == nil && SettingsManager.shared.requireAuthentication {
            generateAuthToken()
        }
    }

    private func checkExternalServer() async -> Bool {
        do {
            let url = URL(string: "\(serverURL):\(port)/health")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.0

            if let token = authToken, SettingsManager.shared.requireAuthentication {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Server not running
        }
        return false
    }

    private func waitForServerReady() async throws {
        let maxAttempts = 30
        let delayMs = 1000

        for attempt in 1...maxAttempts {
            // Check if process has already exited
            if let process = serverProcess, !process.isRunning {
                addLog(.error, "Server process exited unexpectedly during startup")
                throw ServerError.processSpawnFailed
            }
            
            addLog(.debug, "Checking server readiness (attempt \(attempt)/\(maxAttempts))...")

            if await checkIfServerHealthy() {
                addLog(.info, "✅ Server is ready and responding to health checks")
                return
            }

            if attempt < maxAttempts {
                try await Task.sleep(for: .milliseconds(UInt64(delayMs)))
            }
        }

        throw ServerError.serverNotResponding
    }

    private func checkIfServerHealthy() async -> Bool {
        do {
            let url = URL(string: "\(serverURL):\(port)/health")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0

            if let token = authToken, SettingsManager.shared.requireAuthentication {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {

                if let health = try? JSONDecoder().decode(HealthResponse.self, from: data) {
                    return health.status == "ok"
                }
                return true
            }
        } catch {
            // Server not ready yet
        }
        return false
    }

    private func fetchServerStatus() async {
        _ = await checkIfServerHealthy()
        await fetchActiveSessions()
    }
}

// MARK: - Additional Error Cases
extension ServerError {
    static var serverNotResponding: ServerError {
        return .networkError("Server did not respond within timeout period")
    }

    static func portNotAvailable(_ port: Int) -> ServerError {
        return .networkError("Port \(port) is not available after multiple attempts")
    }
}
