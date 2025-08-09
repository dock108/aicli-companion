//
//  ServerManagerNetworking.swift
//  AICLICompanionHost
//
//  Networking and health check functionality for ServerManager
//

import Foundation
import Network

extension ServerManager {

    // MARK: - Network Monitoring

    func setupNetworkMonitoring() {
        NetworkMonitor.shared.$localIP
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ip in
                self?.localIP = ip
            }
            .store(in: &cancellables)
    }

    // MARK: - Health Checks

    func startHealthChecking() {
        stopHealthChecking()

        // Initial health check
        Task {
            await checkServerHealth()
        }

        // Regular health checks every 5 seconds
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkServerHealth()
            }
        }
    }

    func stopHealthChecking() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        serverHealth = .unknown
    }

    @MainActor
    func checkServerHealth() async {
        guard isRunning else {
            serverHealth = .unknown
            return
        }

        do {
            let url = URL(string: "\(serverURL):\(port)/health")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0

            if let token = authToken, SettingsManager.shared.requireAuthentication {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {

                // Parse health response
                if let health = try? JSONDecoder().decode(HealthResponse.self, from: data) {
                    serverHealth = health.status == "ok" ? .healthy : .unhealthy

                    // Update sessions if available
                    if health.sessions > 0 {
                        await fetchActiveSessions()
                    } else {
                        activeSessions = []
                    }
                } else {
                    serverHealth = .healthy
                }
            } else {
                serverHealth = .unhealthy
            }
        } catch {
            // Don't log timeout errors as they're expected when server is starting
            if !error.localizedDescription.contains("timed out") {
                addLog(.debug, "Health check failed: \(error.localizedDescription)")
            }
            serverHealth = .unhealthy
        }
    }

    @MainActor
    func fetchActiveSessions() async {
        guard isRunning else {
            activeSessions = []
            return
        }

        do {
            let url = URL(string: "\(serverURL):\(port)/api/sessions")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 3.0

            if let token = authToken, SettingsManager.shared.requireAuthentication {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {

                let sessionInfo = try JSONDecoder().decode(SessionInfo.self, from: data)

                // Convert to Session objects
                activeSessions = sessionInfo.sessions.map { sessionData in
                    Session(
                        sessionId: sessionData.sessionId,
                        deviceName: sessionData.deviceId,
                        connectedAt: Date(),
                        signalStrength: 1.0
                    )
                }
            } else {
                activeSessions = []
            }
        } catch {
            // Silent fail - sessions might not be available yet
            activeSessions = []
        }
    }

    // MARK: - Port Checking

    func isPortAvailable(_ port: Int) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", ":\(port)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            // If lsof returns 0, port is in use
            return task.terminationStatus != 0
        } catch {
            // If lsof fails, assume port is available
            return true
        }
    }

    func findAvailablePort(starting: Int = 3001) async -> Int {
        for port in starting...(starting + 100) {
            if await isPortAvailable(port) {
                return port
            }
        }
        return starting
    }

    // MARK: - Process Management

    func killProcessOnPort(_ port: Int) async {
        addLog(.info, "Killing any process on port \(port)...")

        // Get our own PID to avoid killing ourselves
        let ourPID = ProcessInfo.processInfo.processIdentifier
        addLog(.debug, "Our process PID: \(ourPID)")

        // Use lsof to find PIDs using the port (only LISTEN state to get servers, not clients)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-t", "-i", ":\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.split(separator: "\n").compactMap { Int($0) }

                for pid in pids {
                    // Skip our own process!
                    if pid == Int(ourPID) {
                        addLog(.warning, "Skipping our own process (PID \(pid))")
                        continue
                    }

                    // Also skip if it's our managed server process
                    if let serverPID = serverPID, pid == Int(serverPID) {
                        addLog(.debug, "Found our managed server process (PID \(pid)), will handle separately")
                        continue
                    }

                    addLog(.debug, "Killing external process with PID \(pid)")
                    let killTask = Process()
                    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killTask.arguments = ["-9", String(pid)]

                    do {
                        try killTask.run()
                        killTask.waitUntilExit()
                        addLog(.info, "Killed external process \(pid) on port \(port)")
                    } catch {
                        addLog(.error, "Failed to kill process \(pid): \(error.localizedDescription)")
                    }
                }

                if pids.isEmpty {
                    addLog(.debug, "No server processes found on port \(port)")
                } else {
                    // Wait a moment for processes to fully terminate
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
        } catch {
            addLog(.error, "Failed to check processes on port \(port): \(error.localizedDescription)")
        }
    }
}
