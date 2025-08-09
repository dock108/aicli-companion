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

    private func setupProcessOutputHandling(for process: Process) {
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

    private func setupServerEnvironment() async throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        // Get the actual paths we'll be using
        let actualNodePath = await findNodeExecutable()
        let actualNpmPath = await findNpmExecutable()

        // Setup PATH
        environment["PATH"] = buildPath(nodePath: actualNodePath, npmPath: actualNpmPath,
                                       currentPath: environment["PATH"] ?? "")

        environment["PORT"] = String(port)
        environment["NODE_ENV"] = "production"

        // Configure authentication
        configureAuthentication(&environment)

        // Configure tunneling
        configureTunneling(&environment)

        return environment
    }

    private func buildPath(nodePath: String, npmPath: String, currentPath: String) -> String {
        var pathComponents: [String] = []

        // Add node and npm directories
        let nodeBinPath = URL(fileURLWithPath: nodePath).deletingLastPathComponent().path
        pathComponents.append(nodeBinPath)
        addLog(.debug, "Added to PATH: \(nodeBinPath)")

        let npmBinPath = URL(fileURLWithPath: npmPath).deletingLastPathComponent().path
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

        pathComponents.append(currentPath)
        return pathComponents.joined(separator: ":")
    }

    private func configureAuthentication(_ environment: inout [String: String]) {
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
    }

    private func configureTunneling(_ environment: inout [String: String]) {
        if SettingsManager.shared.enableTunnel {
            environment["ENABLE_TUNNEL"] = "true"
            environment["TUNNEL_PROVIDER"] = SettingsManager.shared.tunnelProvider

            if SettingsManager.shared.tunnelProvider == "ngrok" &&
               !SettingsManager.shared.ngrokAuthToken.isEmpty {
                environment["NGROK_AUTH_TOKEN"] = SettingsManager.shared.ngrokAuthToken
                addLog(.info, "🌐 Tunnel enabled with ngrok")
            }
        } else {
            environment["ENABLE_TUNNEL"] = "false"
        }
    }

    private func findServerDirectory() throws -> String {
        guard let resourcePath = Bundle.main.resourcePath else {
            addLog(.error, "Could not find app resources")
            throw ServerError.processSpawnFailed
        }

        var serverDir = "\(resourcePath)/server"

        // Check for bundled server
        if !FileManager.default.fileExists(atPath: serverDir) {
            serverDir = try findDevelopmentServer(resourcePath: resourcePath)
        }

        return serverDir
    }

    private func findDevelopmentServer(resourcePath: String) throws -> String {
        // Development fallback - check for server in project
        let devServerPath = "\(resourcePath)/../../../../../../server"
        let resolvedDevPath = URL(fileURLWithPath: devServerPath).standardizedFileURL.path

        if FileManager.default.fileExists(atPath: resolvedDevPath) {
            addLog(.warning, "Using development server at: \(resolvedDevPath)")
            return resolvedDevPath
        }

        // Last resort - check common development location
        let projectServerPath = "/Users/michaelfuscoletti/Desktop/claude-companion/server"
        if FileManager.default.fileExists(atPath: projectServerPath) {
            addLog(.warning, "Using project server at: \(projectServerPath)")
            return projectServerPath
        }

        addLog(.error, "Server not found. Please add server folder to Xcode project Resources.")
        addLog(.error, "Expected location: \(resourcePath)/server")
        addLog(.error, "See ADD_SERVER_TO_XCODE.md for instructions")
        throw ServerError.processSpawnFailed
    }

    private func parseServerCommand() async throws -> (String, [String]) {
        let serverCommand = SettingsManager.shared.serverCommand
        let commandComponents = serverCommand.split(separator: " ").map(String.init)

        if commandComponents.isEmpty {
            addLog(.error, "Invalid server command")
            throw ServerError.processSpawnFailed
        }

        let executable = commandComponents[0]
        let arguments = Array(commandComponents.dropFirst())

        // Find the full path for the executable
        let executablePath: String
        if executable == "npm" {
            executablePath = await findNpmExecutable()
        } else if executable == "node" {
            executablePath = await findNodeExecutable()
        } else {
            executablePath = executable
        }

        let finalArguments = arguments.isEmpty && executable == "npm" ? ["start"] : arguments
        return (executablePath, finalArguments)
    }

    // MARK: - Executable Discovery

    func findNodeExecutable() async -> String {
        // Priority 1: Use configured path from Advanced settings if set
        let configuredPath = SettingsManager.shared.nodeExecutable
        if !configuredPath.isEmpty {
            let expandedPath = NSString(string: configuredPath).expandingTildeInPath
            addLog(.debug, "Using node path from settings: \(expandedPath)")
            return expandedPath
        }

        // Try other detection methods
        if let nvmPath = findExecutableInNVM(executable: "node") {
            return nvmPath
        }

        if let commonPath = findExecutableInCommonPaths(executable: "node") {
            return commonPath
        }

        if let whichPath = findExecutableUsingWhich(executable: "node") {
            return whichPath
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

        // Try other detection methods
        if let nvmPath = findExecutableInNVM(executable: "npm") {
            return nvmPath
        }

        if let commonPath = findExecutableInCommonPaths(executable: "npm") {
            return commonPath
        }

        if let whichPath = findExecutableUsingWhich(executable: "npm") {
            return whichPath
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

    // MARK: - Executable Discovery Helpers

    private func findExecutableInNVM(executable: String) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmPath = "\(homeDir)/.nvm/versions/node"

        guard FileManager.default.fileExists(atPath: nvmPath) else { return nil }

        do {
            let versions = try FileManager.default.contentsOfDirectory(atPath: nvmPath)
            if let latestVersion = versions.sorted().last {
                let nvmExecutablePath = "\(nvmPath)/\(latestVersion)/bin/\(executable)"
                if FileManager.default.fileExists(atPath: nvmExecutablePath) {
                    addLog(.debug, "Auto-detected NVM \(executable) at: \(nvmExecutablePath)")
                    return nvmExecutablePath
                }
            }
        } catch {
            addLog(.debug, "Could not read NVM directory: \(error)")
        }

        return nil
    }

    private func findExecutableInCommonPaths(executable: String) -> String? {
        let commonPaths = [
            "/opt/homebrew/bin/\(executable)",    // Apple Silicon Homebrew
            "/usr/local/bin/\(executable)",       // Intel Homebrew or standard
            "/usr/bin/\(executable)"               // System
        ]

        for path in commonPaths where FileManager.default.fileExists(atPath: path) {
            addLog(.debug, "Auto-detected \(executable) at: \(path)")
            return path
        }

        return nil
    }

    private func findExecutableUsingWhich(executable: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [executable]
        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    addLog(.debug, "Found \(executable) via which: \(path)")
                    return path
                }
            }
        } catch {
            addLog(.debug, "Which command failed for \(executable): \(error)")
        }

        return nil
    }
}
