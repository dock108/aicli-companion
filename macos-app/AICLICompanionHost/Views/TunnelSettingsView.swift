//
//  TunnelSettingsView.swift
//  AICLICompanionHost
//
//  Internet access and tunnel configuration settings
//

import SwiftUI

struct TunnelSettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @Binding var needsRestart: Bool
    @Binding var showingNgrokSetup: Bool
    @Binding var checkingNgrok: Bool
    @State private var ngrokInstalled = false

    var body: some View {
        Section {
            Toggle("Enable Internet Access", isOn: $settingsManager.enableTunnel)
                .help("Expose your server to the internet using a secure tunnel")
                .onChange(of: settingsManager.enableTunnel) { _, newValue in
                    Task { @MainActor in
                        if newValue {
                            // Auto-enable authentication when exposing to internet
                            settingsManager.requireAuthentication = true
                            if serverManager.authToken == nil {
                                serverManager.generateAuthToken()
                            }
                        }
                        // Mark that restart is needed if server is running
                        if serverManager.isRunning {
                            needsRestart = true
                        }
                    }
                }

            if settingsManager.enableTunnel {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Tunnel Provider", selection: $settingsManager.tunnelProvider) {
                        Text("ngrok").tag("ngrok")
                        Text("Cloudflare").tag("cloudflare")
                            .disabled(true)  // Future support
                    }
                    .pickerStyle(.segmented)

                    if settingsManager.tunnelProvider == "ngrok" {
                        NgrokConfigurationView(
                            ngrokAuthToken: $settingsManager.ngrokAuthToken,
                            checkingNgrok: $checkingNgrok,
                            showingNgrokSetup: $showingNgrokSetup,
                            needsRestart: $needsRestart
                        )
                    }

                    if serverManager.isRunning, let publicURL = serverManager.publicURL {
                        PublicURLView(publicURL: publicURL)
                    }
                }
            }

            Text("⚠️ When Internet Access is enabled, authentication is mandatory for security")
                .font(.caption)
                .foregroundStyle(.orange)
                .opacity(settingsManager.enableTunnel ? 1 : 0)
        } header: {
            Text("Internet Access")
        }
        .onAppear {
            checkNgrokInstallation()
        }
    }

    private func checkNgrokInstallation() {
        checkingNgrok = true
        Task {
            // Check if ngrok is available in common locations
            let paths = [
                "/opt/homebrew/bin/ngrok",
                "/usr/local/bin/ngrok",
                "/usr/bin/ngrok"
            ]

            for path in paths where FileManager.default.fileExists(atPath: path) {
                await MainActor.run {
                    ngrokInstalled = true
                    checkingNgrok = false
                }
                return
            }

            // Check using which command
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = ["ngrok"]

            do {
                try task.run()
                task.waitUntilExit()
                await MainActor.run {
                    ngrokInstalled = task.terminationStatus == 0
                    checkingNgrok = false
                }
            } catch {
                await MainActor.run {
                    ngrokInstalled = false
                    checkingNgrok = false
                }
            }
        }
    }
}
