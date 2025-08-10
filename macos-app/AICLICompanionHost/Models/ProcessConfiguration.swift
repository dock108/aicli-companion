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
        // Use development/sandbox APNS for iOS app compatibility
        environment["APNS_PRODUCTION"] = "false"

        // Set project directory for the server
        if !SettingsManager.shared.defaultProjectDirectory.isEmpty {
            environment["CONFIG_PATH"] = SettingsManager.shared.defaultProjectDirectory
            addLog(.debug, "CONFIG_PATH set to: \(SettingsManager.shared.defaultProjectDirectory)")
        } else {
            // Default to user's home directory if not set
            environment["CONFIG_PATH"] = FileManager.default.homeDirectoryForCurrentUser.path
            addLog(.debug, "CONFIG_PATH defaulted to home directory: \(FileManager.default.homeDirectoryForCurrentUser.path)")
        }

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
                // Generate a secure random token
                authToken = generateSecureToken()
                addLog(.info, "🔑 Generated new auth token: \(authToken?.prefix(8) ?? "")...")
            }
            if let token = authToken {
                environment["AUTH_REQUIRED"] = "true"
                environment["AUTH_TOKEN"] = token
                addLog(.info, "🔐 Authentication enabled with token: \(token.prefix(8))...")
                addLog(.debug, "Full auth token set in environment")
            }
        } else {
            environment["AUTH_REQUIRED"] = "false"
            authToken = nil
            addLog(.info, "🔓 Authentication disabled")
        }
    }

    private func generateSecureToken() -> String {
        // Generate a cryptographically secure random token
        let tokenLength = 32
        var bytes = [UInt8](repeating: 0, count: tokenLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, tokenLength, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
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
