//
//  SecuritySettingsViewModel.swift
//  AICLICompanionHost
//
//  ViewModel for Security Settings functionality
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SecuritySettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var blockedCommands: [String] = []
    @Published var safeDirectories: [String] = []
    @Published var allowedTools: [String] = []
    @Published var securityPreset: String = "standard"
    @Published var requireConfirmation: Bool = false
    @Published var readOnlyMode: Bool = false
    @Published var blockDestructiveCommands: Bool = true
    @Published var allowedCLITools: Set<String> = []
    @Published var skipPermissions: Bool = false
    
    @Published var newBlockedCommand: String = ""
    @Published var newSafeDirectory: String = ""
    @Published var isValidatingCommand: Bool = false
    @Published var commandValidationResult: CommandValidationResult?
    @Published var hasUnsavedChanges: Bool = false
    
    // MARK: - Properties
    private let settingsManager = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var originalSettings: SecuritySettingsSnapshot?
    
    // MARK: - Security Presets
    let availablePresets = [
        "unrestricted": "Unrestricted - No limitations",
        "standard": "Standard - Block destructive commands",
        "restricted": "Restricted - Read-only with confirmations",
        "custom": "Custom - User defined rules"
    ]
    
    let dangerousCommands = [
        "rm -rf /",
        "rm -rf /*",
        "format",
        "diskutil eraseDisk",
        "dd if=/dev/zero of=/dev/",
        "mkfs",
        ":(){ :|:& };:",  // Fork bomb
        "chmod -R 777 /",
        "chown -R",
        "> /dev/sda"
    ]
    
    let availableTools = [
        "Read",
        "Write",
        "Edit",
        "MultiEdit",
        "Bash",
        "Grep",
        "List",
        "Task",
        "WebSearch",
        "WebFetch"
    ]
    
    // MARK: - Initialization
    init() {
        loadCurrentSettings()
        setupBindings()
    }
    
    // MARK: - Setup
    private func loadCurrentSettings() {
        // Load from environment variables/settings
        if let blockedStr = settingsManager.getEnvironmentVariable("BLOCKED_COMMANDS") {
            blockedCommands = blockedStr.split(separator: ",").map(String.init)
        }
        
        if let dirsStr = settingsManager.getEnvironmentVariable("SAFE_DIRECTORIES") {
            safeDirectories = dirsStr.split(separator: ",").map(String.init)
        }
        
        if let toolsStr = settingsManager.getEnvironmentVariable("ALLOWED_TOOLS") {
            allowedTools = toolsStr.split(separator: ",").map(String.init)
            allowedCLITools = Set(allowedTools)
        }
        
        if let confirmStr = settingsManager.getEnvironmentVariable("REQUIRE_CONFIRMATION") {
            requireConfirmation = confirmStr == "true"
        }
        
        if let readOnlyStr = settingsManager.getEnvironmentVariable("READ_ONLY_MODE") {
            readOnlyMode = readOnlyStr == "true"
        }
        
        if let skipStr = settingsManager.getEnvironmentVariable("CLAUDE_SKIP_PERMISSIONS") {
            skipPermissions = skipStr == "true"
        }
        
        if let preset = settingsManager.getEnvironmentVariable("SECURITY_PRESET") {
            securityPreset = preset
        }
        
        captureOriginalSettings()
    }
    
    private func setupBindings() {
        // Watch for changes
        $blockedCommands
            .combineLatest($safeDirectories, $allowedTools, $securityPreset)
            .sink { [weak self] _ in
                self?.checkForChanges()
            }
            .store(in: &cancellables)
        
        $requireConfirmation
            .combineLatest($readOnlyMode, $blockDestructiveCommands)
            .sink { [weak self] _ in
                self?.checkForChanges()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func applyPreset(_ preset: String) {
        securityPreset = preset
        
        switch preset {
        case "unrestricted":
            blockedCommands = []
            requireConfirmation = false
            readOnlyMode = false
            blockDestructiveCommands = false
            allowedCLITools = Set(availableTools)
            skipPermissions = true
            
        case "standard":
            blockedCommands = dangerousCommands
            requireConfirmation = true
            readOnlyMode = false
            blockDestructiveCommands = true
            allowedCLITools = Set(availableTools)
            skipPermissions = false
            
        case "restricted":
            blockedCommands = ["*"]  // Block all commands
            requireConfirmation = true
            readOnlyMode = true
            blockDestructiveCommands = true
            allowedCLITools = Set(["Read", "List", "Grep"])
            skipPermissions = false
            
        default:
            // Custom - don't change settings
            break
        }
        
        hasUnsavedChanges = true
    }
    
    func validateCommand(_ command: String) -> CommandValidationResult {
        isValidatingCommand = true
        defer { isValidatingCommand = false }
        
        // Check if command is blocked
        for blocked in blockedCommands {
            if blocked == "*" {
                return CommandValidationResult(
                    isAllowed: false,
                    reason: "All commands are blocked in current security mode"
                )
            }
            
            if command.hasPrefix(blocked) || command == blocked {
                return CommandValidationResult(
                    isAllowed: false,
                    reason: "Command matches blocked pattern: \(blocked)"
                )
            }
        }
        
        // Check for dangerous patterns
        let dangerousPatterns = [
            "rm -rf",
            "format",
            "dd if=",
            "> /dev/",
            "chmod 777"
        ]
        
        for pattern in dangerousPatterns {
            if command.contains(pattern) && blockDestructiveCommands {
                return CommandValidationResult(
                    isAllowed: false,
                    reason: "Command contains dangerous pattern: \(pattern)"
                )
            }
        }
        
        // Check read-only mode
        if readOnlyMode {
            let writeCommands = ["touch", "mkdir", "echo >", "cat >", "cp", "mv", "rm"]
            for writeCmd in writeCommands {
                if command.hasPrefix(writeCmd) {
                    return CommandValidationResult(
                        isAllowed: false,
                        reason: "Write operations not allowed in read-only mode"
                    )
                }
            }
        }
        
        return CommandValidationResult(
            isAllowed: true,
            reason: "Command is allowed"
        )
    }
    
    func addBlockedCommand() {
        let trimmed = newBlockedCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if !blockedCommands.contains(trimmed) {
            blockedCommands.append(trimmed)
            hasUnsavedChanges = true
        }
        
        newBlockedCommand = ""
    }
    
    func removeBlockedCommand(_ command: String) {
        blockedCommands.removeAll { $0 == command }
        hasUnsavedChanges = true
    }
    
    func addSafeDirectory() {
        var trimmed = newSafeDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Expand tilde if present
        if trimmed.hasPrefix("~") {
            trimmed = NSString(string: trimmed).expandingTildeInPath
        }
        
        // Verify directory exists
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: trimmed, isDirectory: &isDirectory) && isDirectory.boolValue {
            if !safeDirectories.contains(trimmed) {
                safeDirectories.append(trimmed)
                hasUnsavedChanges = true
            }
        }
        
        newSafeDirectory = ""
    }
    
    func removeSafeDirectory(_ directory: String) {
        safeDirectories.removeAll { $0 == directory }
        hasUnsavedChanges = true
    }
    
    func toggleTool(_ tool: String) {
        if allowedCLITools.contains(tool) {
            allowedCLITools.remove(tool)
        } else {
            allowedCLITools.insert(tool)
        }
        allowedTools = Array(allowedCLITools)
        hasUnsavedChanges = true
    }
    
    func saveSettings() {
        // Save to environment variables
        settingsManager.setEnvironmentVariable("BLOCKED_COMMANDS", value: blockedCommands.joined(separator: ","))
        settingsManager.setEnvironmentVariable("SAFE_DIRECTORIES", value: safeDirectories.joined(separator: ","))
        settingsManager.setEnvironmentVariable("ALLOWED_TOOLS", value: allowedTools.joined(separator: ","))
        settingsManager.setEnvironmentVariable("CLAUDE_ALLOWED_TOOLS", value: allowedTools.joined(separator: ","))
        settingsManager.setEnvironmentVariable("REQUIRE_CONFIRMATION", value: requireConfirmation ? "true" : "false")
        settingsManager.setEnvironmentVariable("READ_ONLY_MODE", value: readOnlyMode ? "true" : "false")
        settingsManager.setEnvironmentVariable("CLAUDE_SKIP_PERMISSIONS", value: skipPermissions ? "true" : "false")
        settingsManager.setEnvironmentVariable("SECURITY_PRESET", value: securityPreset)
        
        captureOriginalSettings()
        hasUnsavedChanges = false
    }
    
    func revertChanges() {
        guard let original = originalSettings else { return }
        
        blockedCommands = original.blockedCommands
        safeDirectories = original.safeDirectories
        allowedTools = original.allowedTools
        allowedCLITools = Set(original.allowedTools)
        securityPreset = original.securityPreset
        requireConfirmation = original.requireConfirmation
        readOnlyMode = original.readOnlyMode
        blockDestructiveCommands = original.blockDestructiveCommands
        skipPermissions = original.skipPermissions
        
        hasUnsavedChanges = false
    }
    
    func selectDirectory(completion: @escaping (String?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Select Safe Directory"
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                completion(url.path)
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: - Private Methods
    private func captureOriginalSettings() {
        originalSettings = SecuritySettingsSnapshot(
            blockedCommands: blockedCommands,
            safeDirectories: safeDirectories,
            allowedTools: allowedTools,
            securityPreset: securityPreset,
            requireConfirmation: requireConfirmation,
            readOnlyMode: readOnlyMode,
            blockDestructiveCommands: blockDestructiveCommands,
            skipPermissions: skipPermissions
        )
    }
    
    private func checkForChanges() {
        guard let original = originalSettings else {
            hasUnsavedChanges = false
            return
        }
        
        hasUnsavedChanges =
            blockedCommands != original.blockedCommands ||
            safeDirectories != original.safeDirectories ||
            allowedTools != original.allowedTools ||
            securityPreset != original.securityPreset ||
            requireConfirmation != original.requireConfirmation ||
            readOnlyMode != original.readOnlyMode ||
            blockDestructiveCommands != original.blockDestructiveCommands ||
            skipPermissions != original.skipPermissions
    }
}

// MARK: - Supporting Types
struct CommandValidationResult {
    let isAllowed: Bool
    let reason: String
}

private struct SecuritySettingsSnapshot {
    let blockedCommands: [String]
    let safeDirectories: [String]
    let allowedTools: [String]
    let securityPreset: String
    let requireConfirmation: Bool
    let readOnlyMode: Bool
    let blockDestructiveCommands: Bool
    let skipPermissions: Bool
}