//
//  ExecutableDiscovery.swift
//  AICLICompanionHost
//
//  Node.js and npm executable discovery functionality
//

import Foundation

extension ServerManager {

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
