//
//  ProcessConfiguration.swift
//  AICLICompanionHost
//
//  Process configuration and environment setup
//

import Foundation

extension ServerManager {

    // MARK: - Environment & Configuration Setup

    func setupServerEnvironment() async throws -> [String: String] {
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
}
