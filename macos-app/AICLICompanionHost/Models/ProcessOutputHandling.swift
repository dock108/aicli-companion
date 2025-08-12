//
//  ProcessOutputHandling.swift
//  AICLICompanionHost
//
//  Server process output and error handling
//

import Foundation

extension ServerManager {
    // MARK: - Process Output Handling

    func setupProcessOutputHandling(for process: Process) {
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

    func handleServerOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            processOutputLine(line)
        }
    }

    private func processOutputLine(_ line: String) {
        processAuthTokenFromLine(line)
        processTunnelURLFromLine(line)
        logServerOutputLine(line)
    }

    private func processAuthTokenFromLine(_ line: String) {
        if line.contains("🔑 Generated auth token:") {
            if let token = extractTokenFromGeneratedLine(line) {
                authToken = token
                addLog(.info, "🔐 Captured generated auth token")
            }
        } else if line.contains("📱 Mobile app connection:") {
            updateAuthTokenIfNeeded(from: line, source: "connection URL")
        } else if line.contains("iOS Connection URL:") ||
                  (line.contains("https://") && line.contains(".ngrok") && line.contains("token=")) {
            updateAuthTokenIfNeeded(from: line, source: "iOS connection URL")
        }
    }

    private func updateAuthTokenIfNeeded(from line: String, source: String) {
        guard authToken == nil, let token = extractAuthToken(from: line) else { return }
        authToken = token
        addLog(.info, "🔐 Captured auth token from \(source)")
    }

    private func processTunnelURLFromLine(_ line: String) {
        let hasTunnelPattern = line.contains("https://") && (line.contains("ngrok") || line.contains("Tunnel"))
        let hasExplicitPattern = line.contains("Public URL:") || line.contains("Forwarding")

        if hasTunnelPattern || hasExplicitPattern {
            if let url = extractTunnelURL(from: line) {
                publicURL = url
                let message = hasTunnelPattern ? "🌐 Tunnel established: \(url)" : "🌐 Tunnel URL detected: \(url)"
                addLog(.info, message)
                logConnectionStringUpdate()
            }
        }
    }

    private func logConnectionStringUpdate() {
        Task { @MainActor in
            addLog(.debug, "Updated connection string: \(connectionString)")
        }
    }

    private func logServerOutputLine(_ line: String) {
        if line.contains("error") || line.contains("Error") {
            addLog(.error, line)
        } else if line.contains("warning") || line.contains("Warning") {
            addLog(.warning, line)
        } else {
            addLog(.info, line)
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

    private func extractAuthToken(from line: String) -> String? {
        // Look for token in URL query parameter: ?token=<token>
        // The token format is typically a long hex string or similar
        let pattern = #"[?&]token=([a-zA-Z0-9_\-=+/]+)"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            // Extract the capture group (the token value)
            if match.numberOfRanges > 1 {
                let tokenRange = match.range(at: 1)
                if let range = Range(tokenRange, in: line) {
                    let token = String(line[range])
                    // Only return if it looks like a real token (not masked)
                    if !token.contains("****") && token.count > 10 {
                        return token
                    }
                }
            }
        }

        return nil
    }

    private func extractTokenFromGeneratedLine(_ line: String) -> String? {
        // Look for pattern: "🔑 Generated auth token: <token>...****"
        // We want to extract the first part of the token before it's masked
        let pattern = #"Generated auth token:\s*([a-fA-F0-9]{8,})"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if match.numberOfRanges > 1 {
                let tokenRange = match.range(at: 1)
                if let range = Range(tokenRange, in: line) {
                    _ = String(line[range])
                    // This is only a partial token, we need the full one
                    // Store it temporarily and look for the full token in subsequent lines
                    return nil  // Don't use partial token
                }
            }
        }

        return nil
    }

    func waitForTunnelURL() async {
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
