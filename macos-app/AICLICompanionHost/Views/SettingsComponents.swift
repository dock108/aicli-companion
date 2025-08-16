//
//  SettingsComponents.swift
//  AICLICompanionHost
//
//  Reusable components for settings views
//

import SwiftUI

// MARK: - Restart Components

struct RestartNotificationBar: View {
    @Binding var isRestarting: Bool
    let restartAction: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Server Restart Required")
                    .font(.headline)
                Text("Settings have changed that require a server restart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: restartAction) {
                if isRestarting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(.circular)
                } else {
                    Text("Restart Now")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRestarting)
        }
        .padding(.vertical, 4)
    }
}

struct RestartIndicatorView: View {
    @Binding var isRestarting: Bool
    let restartAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Server restart required to apply settings changes")
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
            }

            Button(action: restartAction) {
                HStack {
                    if isRestarting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRestarting ? "Restarting..." : "Apply Changes")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(isRestarting)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Authentication Components

struct AuthenticationTokenView: View {
    let authToken: String?
    @Binding var showingTokenAlert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication Token")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if let token = authToken {
                    Text(token)
                        .fontDesign(.monospaced)
                        .font(.caption)
                        .textSelection(.enabled)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(token, forType: .string)
                            }
                        }
                } else {
                    Text("No token generated")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Spacer()

                Button("Generate New") {
                    showingTokenAlert = true
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Tunnel Components

struct NgrokConfigurationView: View {
    @Binding var ngrokAuthToken: String
    @Binding var checkingNgrok: Bool
    @Binding var showingNgrokSetup: Bool
    @Binding var needsRestart: Bool
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auth Token Input
            LabeledContent("Auth Token") {
                HStack {
                    SecureField("", text: $ngrokAuthToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onChange(of: ngrokAuthToken) { _, _ in
                            Task { @MainActor in
                                if serverManager.isRunning && settingsManager.enableTunnel {
                                    needsRestart = true
                                }
                            }
                        }

                    Button("Get Token") {
                        NSWorkspace.shared.open(
                            URL(string: "https://dashboard.ngrok.com/auth/your-authtoken")!
                        )
                    }
                    .buttonStyle(.link)
                }
            }

            // Setup Status
            HStack(spacing: 8) {
                if checkingNgrok {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(.circular)
                    Text("Checking ngrok...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !ngrokAuthToken.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("ngrok configured")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Setup ngrok") {
                        showingNgrokSetup = true
                    }
                    .buttonStyle(.bordered)

                    Text("Required for tunneling")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Quick Setup Guide
            if ngrokAuthToken.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Setup:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("1. Sign up for free at ngrok.com")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("2. Copy your auth token from dashboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("3. Paste token above and restart server")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }
}

struct PublicURLView: View {
    let publicURL: String

    var body: some View {
        Divider()

        LabeledContent("Public URL") {
            HStack {
                Text(publicURL)
                    .fontDesign(.monospaced)
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(publicURL, forType: .string)
                        }
                    }
            }
        }
    }
}
