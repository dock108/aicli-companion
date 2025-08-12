//
//  SecuritySettingsHelper.swift
//  AICLICompanionHost
//
//  Helper methods for SecuritySettingsView
//

import Foundation
import SwiftUI

// MARK: - Security Settings Helper Methods
extension SecuritySettingsView {
    // MARK: - Command Control Methods

    func applySecurityPreset(_ preset: String) {
        settingsManager.setEnvironmentVariable("AICLI_SECURITY_PRESET", value: preset)

        switch preset {
        case "unrestricted":
            blockedCommands = []
            requireConfirmation = false
            readOnlyMode = false

        case "standard":
            blockedCommands = [
                "rm -rf /",
                "rm -rf /*",
                "format",
                "diskutil eraseDisk",
                "dd if=/dev/zero of=/dev/",
                "mkfs"
            ]
            requireConfirmation = true
            readOnlyMode = false

        case "restricted":
            blockedCommands = ["*"]
            requireConfirmation = true
            readOnlyMode = true

        default:
            // Custom - keep current settings
            break
        }

        updateEnvironmentVariables()
    }

    func addSafeDirectory(_ directory: String) {
        let path = directory.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        if !safeDirectories.contains(path) {
            safeDirectories.append(path)
            updateEnvironmentVariables()
            needsRestart = true
        }
    }

    func removeSafeDirectory(_ directory: String) {
        safeDirectories.removeAll { $0 == directory }
        updateEnvironmentVariables()
        needsRestart = true
    }

    func addBlockedCommand(_ command: String) {
        if !blockedCommands.contains(command) {
            blockedCommands.append(command)
            updateEnvironmentVariables()
            needsRestart = true
        }
    }

    func removeBlockedCommand(_ command: String) {
        blockedCommands.removeAll { $0 == command }
        updateEnvironmentVariables()
        needsRestart = true
    }

    func updateEnvironmentVariables() {
        // Update safe directories
        let dirsString = safeDirectories.joined(separator: ",")
        settingsManager.setEnvironmentVariable("AICLI_SAFE_DIRECTORIES", value: dirsString)

        // Update blocked commands
        let commandsString = blockedCommands.joined(separator: ",")
        settingsManager.setEnvironmentVariable("AICLI_BLOCKED_COMMANDS", value: commandsString)
    }

    func loadSecuritySettings() {
        // Load from environment variables
        if let preset = settingsManager.getEnvironmentVariable("AICLI_SECURITY_PRESET") {
            securityPreset = preset
        }

        if let dirs = settingsManager.getEnvironmentVariable("AICLI_SAFE_DIRECTORIES") {
            safeDirectories = dirs.split(separator: ",").map(String.init)
        }

        if let commands = settingsManager.getEnvironmentVariable("AICLI_BLOCKED_COMMANDS") {
            blockedCommands = commands.split(separator: ",").map(String.init)
        }

        readOnlyMode = settingsManager.getEnvironmentVariable("AICLI_READONLY_MODE") == "true"
        requireConfirmation = settingsManager
            .getEnvironmentVariable("AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION") == "true"
        enableAudit = settingsManager.getEnvironmentVariable("AICLI_ENABLE_AUDIT") != "false" // Default true
    }

    // MARK: - Restart Method

    func restartServer() {
        isRestarting = true
        Task {
            do {
                try await serverManager.restartServerWithCurrentConfig()
                await MainActor.run {
                    needsRestart = false
                }
            } catch {
                await MainActor.run {
                    serverManager.addLog(.error, "Failed to restart server: \(error.localizedDescription)")
                }
                print("Failed to restart server: \(error)")
            }
            await MainActor.run {
                isRestarting = false
            }
        }
    }
}
