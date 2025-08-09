//
//  ServerManagerProcess.swift
//  AICLICompanionHost
//
//  Process management functionality for ServerManager
//

import Foundation

extension ServerManager {

    // MARK: - Server Process Management

    func startServerProcess() async throws {
        guard !isRunning else {
            throw ServerError.serverAlreadyRunning
        }
        
        // Prevent multiple simultaneous start attempts
        guard serverProcess == nil else {
            addLog(.warning, "Server process already starting, ignoring duplicate request")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        addLog(.info, "🚀 Starting server process...")

        // Check if port is available
        let portAvailable = await isPortAvailable(port)
        if !portAvailable {
            let newPort = await findAvailablePort(starting: port)
            if newPort != port {
                addLog(.warning, "Port \(port) is in use, using port \(newPort) instead")
                port = newPort
                SettingsManager.shared.serverPort = newPort
            }
        }

        // Create server process
        let process = Process()
        serverProcess = process

        // Setup environment
        var environment = ProcessInfo.processInfo.environment
        
        // Get the actual paths we'll be using
        let actualNodePath = await findNodeExecutable()
        let actualNpmPath = await findNpmExecutable()
        
        // Add the directory containing node and npm to PATH
        let currentPath = environment["PATH"] ?? ""
        var pathComponents: [String] = []
        
        // Add the directory of the actual node executable
        let nodeBinPath = URL(fileURLWithPath: actualNodePath).deletingLastPathComponent().path
        pathComponents.append(nodeBinPath)
        addLog(.debug, "Added to PATH: \(nodeBinPath)")
        
        // Add the directory of the actual npm executable if different
        let npmBinPath = URL(fileURLWithPath: actualNpmPath).deletingLastPathComponent().path
        if npmBinPath != nodeBinPath {
            pathComponents.append(npmBinPath)
            addLog(.debug, "Added to PATH: \(npmBinPath)")
        }
        
        // Add common paths as fallback
        pathComponents.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ])
        
        // Combine all paths
        pathComponents.append(currentPath)
        environment["PATH"] = pathComponents.joined(separator: ":")
        
        environment["PORT"] = String(port)
        environment["NODE_ENV"] = "production"

        // Configure authentication if needed
        if SettingsManager.shared.requireAuthentication {
            if authToken == nil {
                generateAuthToken()
            }
            if let token = authToken {
                environment["AUTH_REQUIRED"] = "true"
                environment["AUTH_TOKEN"] = token
                addLog(.info, "🔐 Authentication enabled with token")
            }
        } else {
            environment["AUTH_REQUIRED"] = "false"
            addLog(.info, "🔓 Authentication disabled")
        }

        // Configure tunneling if enabled
        if SettingsManager.shared.enableTunnel {
            environment["ENABLE_TUNNEL"] = "true"
            environment["TUNNEL_PROVIDER"] = SettingsManager.shared.tunnelProvider

            if SettingsManager.shared.tunnelProvider == "ngrok" && !SettingsManager.shared.ngrokAuthToken.isEmpty {
                environment["NGROK_AUTH_TOKEN"] = SettingsManager.shared.ngrokAuthToken
                addLog(.info, "🌐 Tunnel enabled with ngrok")
            }
        } else {
            environment["ENABLE_TUNNEL"] = "false"
        }

        process.environment = environment

        // Setup command - use bundled server
        guard let resourcePath = Bundle.main.resourcePath else {
            addLog(.error, "Could not find app resources")
            throw ServerError.processSpawnFailed
        }
        
        let serverDir = "\(resourcePath)/server"
        
        // Verify bundled server exists
        if !FileManager.default.fileExists(atPath: serverDir) {
            addLog(.error, "Bundled server not found at: \(serverDir)")
            addLog(.error, "Please ensure the server is bundled with the app")
            throw ServerError.processSpawnFailed
        }
        
        process.currentDirectoryURL = URL(fileURLWithPath: serverDir)
        addLog(.debug, "Working directory set to bundled server: \(serverDir)")

        // Parse server command from settings
        let serverCommand = SettingsManager.shared.serverCommand
        let commandComponents = serverCommand.split(separator: " ").map(String.init)
        
        if commandComponents.isEmpty {
            addLog(.error, "Invalid server command")
            throw ServerError.processSpawnFailed
        }
        
        // Determine executable and arguments
        let executable = commandComponents[0]
        let arguments = Array(commandComponents.dropFirst())
        
        // Find the full path for the executable (npm, node, etc.)
        let executablePath: String
        if executable == "npm" {
            executablePath = await findNpmExecutable()
        } else if executable == "node" {
            executablePath = await findNodeExecutable()
        } else {
            // For other commands, try to find it in PATH or use as-is
            executablePath = executable
        }
        
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments.isEmpty && executable == "npm" ? ["start"] : arguments

        // Setup output handling
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Capture output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.handleServerOutput(output)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.handleServerError(output)
                }
            }
        }

        // Set termination handler
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleServerTermination(process)
            }
        }

        // Start the process
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
                }
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

    func findNodeExecutable() async -> String {
        // Priority 1: Use configured path from Advanced settings if set
        let configuredPath = SettingsManager.shared.nodeExecutable
        if !configuredPath.isEmpty {
            let expandedPath = NSString(string: configuredPath).expandingTildeInPath
            addLog(.debug, "Using node path from settings: \(expandedPath)")
            return expandedPath
        }
        
        // Priority 2: Check for NVM installation
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmPath = "\(homeDir)/.nvm/versions/node"
        if FileManager.default.fileExists(atPath: nvmPath) {
            do {
                let versions = try FileManager.default.contentsOfDirectory(atPath: nvmPath)
                if let latestVersion = versions.sorted().last {
                    let nvmNodePath = "\(nvmPath)/\(latestVersion)/bin/node"
                    if FileManager.default.fileExists(atPath: nvmNodePath) {
                        addLog(.debug, "Auto-detected NVM node at: \(nvmNodePath)")
                        return nvmNodePath
                    }
                }
            } catch {
                addLog(.debug, "Could not read NVM directory: \(error)")
            }
        }
        
        // Priority 3: Check common installation locations
        let commonPaths = [
            "/opt/homebrew/bin/node",    // Apple Silicon Homebrew
            "/usr/local/bin/node",       // Intel Homebrew or standard
            "/usr/bin/node"               // System
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                addLog(.debug, "Auto-detected node at: \(path)")
                return path
            }
        }
        
        // Priority 4: Try using which command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["node"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    addLog(.debug, "Found node via which: \(path)")
                    return path
                }
            }
        } catch {
            addLog(.debug, "Which command failed: \(error)")
        }
        
        // Final fallback
        addLog(.warning, "Could not auto-detect node, using default /usr/local/bin/node")
        return "/usr/local/bin/node"
    }

    func findNpmExecutable() async -> String {
        // Priority 1: Use configured path from Advanced settings if set
        let configuredPath = SettingsManager.shared.npmExecutable
        if !configuredPath.isEmpty {
            let expandedPath = NSString(string: configuredPath).expandingTildeInPath
            addLog(.debug, "Using npm path from settings: \(expandedPath)")
            return expandedPath
        }
        
        // Priority 2: Check for NVM installation
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmPath = "\(homeDir)/.nvm/versions/node"
        if FileManager.default.fileExists(atPath: nvmPath) {
            do {
                let versions = try FileManager.default.contentsOfDirectory(atPath: nvmPath)
                if let latestVersion = versions.sorted().last {
                    let nvmNpmPath = "\(nvmPath)/\(latestVersion)/bin/npm"
                    if FileManager.default.fileExists(atPath: nvmNpmPath) {
                        addLog(.debug, "Auto-detected NVM npm at: \(nvmNpmPath)")
                        return nvmNpmPath
                    }
                }
            } catch {
                addLog(.debug, "Could not read NVM directory: \(error)")
            }
        }
        
        // Priority 3: Check common installation locations
        let commonPaths = [
            "/opt/homebrew/bin/npm",     // Apple Silicon Homebrew
            "/usr/local/bin/npm",        // Intel Homebrew or standard
            "/usr/bin/npm"                // System
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                addLog(.debug, "Auto-detected npm at: \(path)")
                return path
            }
        }
        
        // Priority 4: Try using which command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["npm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    addLog(.debug, "Found npm via which: \(path)")
                    return path
                }
            }
        } catch {
            addLog(.debug, "Which command failed: \(error)")
        }
        
        // Final fallback
        addLog(.warning, "Could not auto-detect npm, using default /usr/local/bin/npm")
        return "/usr/local/bin/npm"
    }

    func handleServerOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            // Check for tunnel URL in output - look for various patterns
            if line.contains("https://") && (line.contains("ngrok") || line.contains("Tunnel")) {
                if let url = extractTunnelURL(from: line) {
                    publicURL = url
                    addLog(.info, "🌐 Tunnel established: \(url)")
                }
            }
            
            // Also check for explicit tunnel URL announcements
            if line.contains("Public URL:") || line.contains("Forwarding") {
                if let url = extractTunnelURL(from: line) {
                    publicURL = url
                    addLog(.info, "🌐 Tunnel URL detected: \(url)")
                }
            }

            // Log server output
            if line.contains("error") || line.contains("Error") {
                addLog(.error, line)
            } else if line.contains("warning") || line.contains("Warning") {
                addLog(.warning, line)
            } else {
                addLog(.info, line)
            }
        }
    }

    func handleServerError(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            addLog(.error, line)
        }
    }

    func handleServerTermination(_ process: Process) {
        let exitCode = process.terminationStatus

        if exitCode == 0 {
            addLog(.info, "Server process exited normally")
        } else {
            addLog(.error, "Server process exited with code \(exitCode)")
        }

        isRunning = false
        serverProcess = nil
        publicURL = nil
        serverHealth = .unknown
        activeSessions = []
        stopHealthChecking()
    }

    private func extractTunnelURL(from line: String) -> String? {
        // Look for ngrok URL pattern
        let pattern = #"https://[a-zA-Z0-9-]+\.ngrok[a-zA-Z0-9-]*\.[a-zA-Z]{2,}"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            return String(line[Range(match.range, in: line)!])
        }

        return nil
    }

    private func waitForTunnelURL() async {
        // Wait up to 30 seconds for tunnel URL
        for _ in 0..<30 {
            if publicURL != nil {
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }

        if publicURL == nil {
            addLog(.warning, "⚠️ Tunnel URL not detected after 30 seconds")
        }
    }
}
