//
//  SecuritySettingsView.swift
//  AICLICompanionHost
//
//  Authentication and macOS security settings
//

import SwiftUI

struct SecuritySettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingTokenAlert = false
    @State private var needsRestart = false
    @State private var isRestarting = false
    @State private var showingNgrokSetup = false
    @State private var checkingNgrok = false

    // Command Controls State
    @State private var securityPreset: String = "standard"
    @State private var safeDirectories: [String] = []
    @State private var blockedCommands: [String] = []
    @State private var readOnlyMode: Bool = false
    @State private var requireConfirmation: Bool = true
    @State private var enableAudit: Bool = true
    @State private var newDirectory: String = ""
    @State private var newCommand: String = ""

    var body: some View {
        Form {
            // Restart notification bar at top
            if needsRestart && serverManager.isRunning {
                Section {
                    RestartNotificationBar(isRestarting: $isRestarting, restartAction: restartServer)
                }
            }

            Section {
                Toggle("Require Authentication", isOn: $settingsManager.requireAuthentication)
                    .help("Clients must provide an authentication token to connect")
                    .onChange(of: settingsManager.requireAuthentication) { _, newValue in
                        Task { @MainActor in
                            // If enabling auth and we're exposed to internet, ensure we have a token
                            if newValue && settingsManager.enableTunnel && serverManager.authToken == nil {
                                serverManager.generateAuthToken()
                            }
                            // Mark that restart is needed if server is running
                            if serverManager.isRunning {
                                needsRestart = true
                            }
                        }
                    }

                if settingsManager.requireAuthentication {
                    AuthenticationTokenView(
                        authToken: serverManager.authToken,
                        showingTokenAlert: $showingTokenAlert
                    )
                }
            } header: {
                Text("Authentication")
            }

            Section {
                Toggle("Enable Touch ID", isOn: $settingsManager.enableTouchID)
                    .help("Use Touch ID to authenticate admin actions")

                Text("The authentication token is securely stored in the macOS Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("macOS Security")
            }

            // Command Controls Section
            Section {
                Picker("Security Preset", selection: $securityPreset) {
                    Text("Unrestricted").tag("unrestricted")
                    Text("Standard").tag("standard")
                    Text("Restricted").tag("restricted")
                    Text("Custom").tag("custom")
                }
                .help("Choose a security preset or customize your own")
                .onChange(of: securityPreset) { _, newValue in
                    applySecurityPreset(newValue)
                    needsRestart = true
                }

                Toggle("Read-Only Mode", isOn: $readOnlyMode)
                    .help("Block all write operations")
                    .onChange(of: readOnlyMode) { _, _ in
                        settingsManager.setEnvironmentVariable(
                            "AICLI_READONLY_MODE",
                            value: readOnlyMode ? "true" : "false"
                        )
                        needsRestart = true
                    }

                Toggle("Require Confirmation for Destructive Commands", isOn: $requireConfirmation)
                    .help("Ask for confirmation before running potentially destructive commands")
                    .onChange(of: requireConfirmation) { _, _ in
                        settingsManager.setEnvironmentVariable("AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION",
                                                              value: requireConfirmation ? "true" : "false")
                        needsRestart = true
                    }

                Toggle("Enable Security Audit", isOn: $enableAudit)
                    .help("Log all security validations for review")
                    .onChange(of: enableAudit) { _, _ in
                        settingsManager.setEnvironmentVariable(
                            "AICLI_ENABLE_AUDIT",
                            value: enableAudit ? "true" : "false"
                        )
                        needsRestart = true
                    }
            } header: {
                Text("Command Controls")
            } footer: {
                Text("Configure which commands Claude can execute and set security restrictions")
            }

            // Safe Directories Section
            Section {
                ForEach(safeDirectories, id: \.self) { directory in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                        Text(directory)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            removeSafeDirectory(directory)
                        }, label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        })
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add directory path...", text: $newDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if !newDirectory.isEmpty {
                            addSafeDirectory(newDirectory)
                            newDirectory = ""
                        }
                    }
                    .disabled(newDirectory.isEmpty)
                }
            } header: {
                Text("Safe Directories")
            } footer: {
                Text("Claude can only operate within these directories when restrictions are enabled")
            }

            // Blocked Commands Section
            Section {
                ForEach(blockedCommands, id: \.self) { command in
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            removeBlockedCommand(command)
                        }, label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        })
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add command pattern...", text: $newCommand)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if !newCommand.isEmpty {
                            addBlockedCommand(newCommand)
                            newCommand = ""
                        }
                    }
                    .disabled(newCommand.isEmpty)
                }
            } header: {
                Text("Blocked Commands")
            } footer: {
                Text("Commands matching these patterns will be blocked")
            }

            // Internet Access settings moved to TunnelSettingsView
            TunnelSettingsView(
                needsRestart: $needsRestart,
                showingNgrokSetup: $showingNgrokSetup,
                checkingNgrok: $checkingNgrok
            )
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            // Configuration Change Indicator
            if settingsManager.needsRestart {
                RestartIndicatorView(isRestarting: $isRestarting, restartAction: restartServer)
            }
        }
        .alert("Generate New Token?", isPresented: $showingTokenAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Generate", role: .destructive) {
                serverManager.generateAuthToken()
            }
        } message: {
            Text("""
                This will invalidate the current token. \
                All connected clients will need to reconnect with the new token.
                """)
        }
        .sheet(isPresented: $showingNgrokSetup) {
            NgrokSetupView(
                ngrokAuthToken: $settingsManager.ngrokAuthToken,
                isPresented: $showingNgrokSetup,
                needsRestart: $needsRestart
            )
        }
        .onAppear {
            loadSecuritySettings()
        }
    }

    private func restartServer() {
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

    // MARK: - Command Control Methods

    private func applySecurityPreset(_ preset: String) {
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

    private func addSafeDirectory(_ directory: String) {
        let path = directory.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        if !safeDirectories.contains(path) {
            safeDirectories.append(path)
            updateEnvironmentVariables()
            needsRestart = true
        }
    }

    private func removeSafeDirectory(_ directory: String) {
        safeDirectories.removeAll { $0 == directory }
        updateEnvironmentVariables()
        needsRestart = true
    }

    private func addBlockedCommand(_ command: String) {
        if !blockedCommands.contains(command) {
            blockedCommands.append(command)
            updateEnvironmentVariables()
            needsRestart = true
        }
    }

    private func removeBlockedCommand(_ command: String) {
        blockedCommands.removeAll { $0 == command }
        updateEnvironmentVariables()
        needsRestart = true
    }

    private func updateEnvironmentVariables() {
        // Update safe directories
        let dirsString = safeDirectories.joined(separator: ",")
        settingsManager.setEnvironmentVariable("AICLI_SAFE_DIRECTORIES", value: dirsString)

        // Update blocked commands
        let commandsString = blockedCommands.joined(separator: ",")
        settingsManager.setEnvironmentVariable("AICLI_BLOCKED_COMMANDS", value: commandsString)
    }

    private func loadSecuritySettings() {
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
}
