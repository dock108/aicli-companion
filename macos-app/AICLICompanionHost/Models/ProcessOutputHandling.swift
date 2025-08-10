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
