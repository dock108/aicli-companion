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
}
