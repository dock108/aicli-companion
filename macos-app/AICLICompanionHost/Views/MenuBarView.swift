//
//  MenuBarView.swift
//  AICLICompanionHost
//
//  The main menu bar dropdown interface
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingQRCode = false
    @State private var copiedToClipboard = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderSection()

            Divider()
                .padding(.vertical, 8)

            // Server Status
            ServerStatusSection()

            // Start/Stop Button - Prominent
            StartStopButton()
                .padding(.vertical, 8)

            Divider()
                .padding(.vertical, 8)

            // Active Sessions
            if !serverManager.activeSessions.isEmpty {
                ActiveSessionsSection()

                Divider()
                    .padding(.vertical, 8)
            }

            // Quick Actions
            QuickActionsSection(
                showingQRCode: $showingQRCode,
                copiedToClipboard: $copiedToClipboard
            )

            Divider()
                .padding(.vertical, 8)

            // Footer Actions
            FooterSection()
        }
        .frame(width: 320)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Header Section
struct HeaderSection: View {
    var body: some View {
        HStack {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AICLI Companion")
                    .font(.headline)
                Text("Server Manager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Activity Indicator
            ActivityIndicator()
        }
    }
}

// MARK: - Server Status Section
struct ServerStatusSection: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Row
            HStack {
                StatusIndicator(isRunning: serverManager.isRunning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)

                    if serverManager.isRunning {
                        Text("Port \(String(serverManager.port))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            // Connection Info
            if serverManager.isRunning {
                ConnectionInfoView()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Quick Actions Section
struct QuickActionsSection: View {
    @EnvironmentObject private var serverManager: ServerManager
    @Binding var showingQRCode: Bool
    @Binding var copiedToClipboard: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Copy URL Button
            QuickActionButton(
                title: "Copy Connection URL",
                icon: "doc.on.doc",
                isDisabled: !serverManager.isRunning
            ) {
                copyConnectionURL()
            }

            // Show QR Code Button
            QuickActionButton(
                title: "Show QR Code",
                icon: "qrcode",
                isDisabled: !serverManager.isRunning
            ) {
                showingQRCode = true
            }
            .popover(isPresented: $showingQRCode) {
                // Use public URL if tunneling is enabled, otherwise use local connection
                QRCodeView(connectionString: serverManager.publicURL ?? serverManager.connectionString)
            }

            // Open Logs Button
            QuickActionButton(
                title: "View Logs",
                icon: "doc.text"
            ) {
                NSApp.sendAction(#selector(AppCommands.openLogs), to: nil, from: nil)
            }
        }
    }

    private func copyConnectionURL() {
        // Use public URL if available, otherwise use local connection
        let urlToCopy = serverManager.publicURL ?? serverManager.connectionString

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlToCopy, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            copiedToClipboard = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedToClipboard = false
            }
        }

        // Show notification
        let notificationBody = serverManager.publicURL != nil
            ? "Public URL copied to clipboard"
            : "Connection URL copied to clipboard"
        NotificationManager.shared.showNotification(
            title: "Copied!",
            body: notificationBody
        )
    }
}

// MARK: - Active Sessions Section
struct ActiveSessionsSection: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Active Sessions", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(String(serverManager.activeSessions.count))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(10)
            }

            VStack(spacing: 4) {
                ForEach(serverManager.activeSessions) { session in
                    SessionRow(session: session)
                }
            }
        }
    }
}

// MARK: - Start/Stop Button
struct StartStopButton: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var isProcessing = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var currentOperation = ""

    var body: some View {
        Button(action: toggleServer) {
            HStack(spacing: 12) {
                Image(systemName: serverManager.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(serverManager.isRunning ? "Stop Server" : "Start Server")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)

                    if isProcessing && !currentOperation.isEmpty {
                        Text(currentOperation)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(.circular)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(serverManager.isRunning ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .alert("Server Operation Failed", isPresented: $showingAlert) {
            Button("OK") { }
            Button("View Logs") {
                NSApp.sendAction(#selector(AppCommands.openLogs), to: nil, from: nil)
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func toggleServer() {
        isProcessing = true
        currentOperation = ""

        Task {
            do {
                if serverManager.isRunning {
                    await MainActor.run { currentOperation = "Stopping server..." }
                    await serverManager.stopServer()
                } else {
                    await MainActor.run { currentOperation = "Starting server..." }
                    try await serverManager.startServer()
                }
                await MainActor.run { currentOperation = "" }
            } catch {
                await MainActor.run {
                    serverManager.addLog(.error, "Server operation failed: \(error.localizedDescription)")
                    alertMessage = error.localizedDescription
                    showingAlert = true
                    currentOperation = ""
                }
                print("Failed server operation: \(error)")
            }
            await MainActor.run {
                isProcessing = false
                currentOperation = ""
            }
        }
    }
}

// MARK: - Footer Section
struct FooterSection: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .font(.caption)
    }
}

// MARK: - Supporting Views
struct StatusIndicator: View {
    let isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.red.opacity(0.5))
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(isRunning ? Color.green.opacity(0.3) : Color.clear, lineWidth: isRunning ? 8 : 0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: isRunning)
            )
    }
}

struct ConnectionInfoView: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            InfoRow(label: "Local IP:", value: serverManager.localIP)
            InfoRow(label: "Port:", value: String(serverManager.port))
            if serverManager.authToken != nil {
                InfoRow(label: "Auth:", value: "Enabled")
            }
            if let publicURL = serverManager.publicURL {
                // Add subtle divider before tunnel info
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    // Status row using consistent InfoRow format
                    InfoRow(label: "Tunnel:", value: "🌐 Active")
                        .foregroundStyle(.green)

                    // URL display with proper formatting and improved contrast
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Public URL:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)

                        Text(publicURL)
                            .fontDesign(.monospaced)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(4)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .contextMenu {
                                Button("Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(publicURL, forType: .string)
                                }
                                Button("Open in Browser") {
                                    if let url = URL(string: publicURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    struct InfoRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .fontDesign(.monospaced)
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceName)
                    .font(.caption)
                    .lineLimit(1)

                Text(session.sessionId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Connection strength indicator
            Image(systemName: "wifi", variableValue: session.signalStrength)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }
}

struct ActivityIndicator: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "circle.dotted")
            .font(.body)
            .foregroundStyle(serverManager.isProcessing ? .blue : .clear)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
    }
}
