//
//  ServerManagerProcess.swift
//  AICLICompanionHost
//
//  Core process management functionality for ServerManager
//

import Foundation

extension ServerManager {

    // MARK: - Server Process Management

    func startServerProcess() async throws {
        try validateServerStart()

        isProcessing = true
        defer { isProcessing = false }

        addLog(.info, "🚀 Starting server process...")

        // Ensure port is available
        await ensurePortAvailable()

        // Create and configure server process
        let process = try await createConfiguredProcess()
        serverProcess = process

        // Setup output handling
        setupProcessOutputHandling(for: process)

        // Start the process
        try await launchProcess(process)
    }

    private func createConfiguredProcess() async throws -> Process {
        let process = Process()

        // Setup environment
        let environment = try await setupServerEnvironment()
        process.environment = environment

        // Setup working directory
        let serverDir = try findServerDirectory()
        process.currentDirectoryURL = URL(fileURLWithPath: serverDir)
        addLog(.debug, "Working directory set to: \(serverDir)")

        // Configure executable and arguments
        let (executablePath, arguments) = try await parseServerCommand()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        return process
    }

    private func launchProcess(_ process: Process) async throws {
        do {
            try process.run()
            isRunning = true
            serverStartTime = Date()
            addLog(.info, "✅ Server process started with PID \(process.processIdentifier)")

            // Wait a moment for server to initialize
            try await Task.sleep(for: .seconds(2))

            // Start health checking
            startHealthChecking()

            // Check for tunnel URL if enabled
            if SettingsManager.shared.enableTunnel {
                Task {
                    await self.waitForTunnelURL()
                    // Small delay to ensure publicURL is fully set
                    try? await Task.sleep(for: .milliseconds(500))
                    // Log connection string after tunnel is ready
                    await MainActor.run {
                        addLog(.info, "📱 Mobile app connection: \(self.connectionString)")
                    }
                }
            } else {
                // Log connection string for local connection
                addLog(.info, "📱 Mobile app connection: \(connectionString)")
            }

        } catch {
            isRunning = false
            serverProcess = nil
            addLog(.error, "❌ Failed to start server: \(error.localizedDescription)")
            throw ServerError.processSpawnFailed
        }
    }

    func stopServerProcess() async {
        guard isRunning, let process = serverProcess else {
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
            isRunning = false
            serverProcess = nil
            publicURL = nil
            activeSessions = []
            stopHealthChecking()
        }

        addLog(.info, "🛑 Stopping server process...")

        // Try graceful shutdown first
        process.interrupt()

        // Wait for graceful shutdown (max 5 seconds)
        for index in 0..<50 {
            if !process.isRunning {
                addLog(.info, "✅ Server stopped gracefully")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))

            if index == 20 {
                addLog(.warning, "Server is taking longer than expected to stop...")
            }
        }

        // Force termination if still running
        if process.isRunning {
            addLog(.warning, "⚠️ Force terminating server process")
            process.terminate()
            process.waitUntilExit()
        }

        addLog(.info, "✅ Server process stopped")
    }

    // MARK: - Helper Methods

    private func validateServerStart() throws {
        guard !isRunning else {
            throw ServerError.serverAlreadyRunning
        }

        // Prevent multiple simultaneous start attempts
        guard serverProcess == nil else {
            addLog(.warning, "Server process already starting, ignoring duplicate request")
            throw ServerError.serverAlreadyRunning
        }
    }

    private func ensurePortAvailable() async {
        let portAvailable = await isPortAvailable(port)
        if !portAvailable {
            let newPort = await findAvailablePort(starting: port)
            if newPort != port {
                addLog(.warning, "Port \(port) is in use, using port \(newPort) instead")
                port = newPort
                SettingsManager.shared.serverPort = newPort
            }
        }
    }
}
