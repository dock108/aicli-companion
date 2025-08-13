//
//  ServerDiscovery.swift
//  AICLICompanionHost
//
//  Server directory and command discovery functionality
//

import Foundation

extension ServerManager {
    // MARK: - Server Discovery

    func findServerDirectory() throws -> String {
        // Check for custom server directory first
        if !SettingsManager.shared.serverDirectory.isEmpty,
           FileManager.default.fileExists(atPath: SettingsManager.shared.serverDirectory) {
            return SettingsManager.shared.serverDirectory
        }
        
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

    func parseServerCommand() async throws -> (String, [String]) {
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
}
