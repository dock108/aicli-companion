//
//  MenuBarView.swift
//  ClaudeCompanionHost
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
                .environmentObject(serverManager)

            // Start/Stop Button - Prominent
            StartStopButton()
                .environmentObject(serverManager)
                .padding(.vertical, 8)

            // Quick Actions
            QuickActionsSection(
                showingQRCode: $showingQRCode,
                copiedToClipboard: $copiedToClipboard
            )
            .environmentObject(serverManager)

            // Active Sessions
            if !serverManager.activeSessions.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                ActiveSessionsSection()
                    .environmentObject(serverManager)
            }

            Divider()
                .padding(.vertical, 8)

            // Footer Actions
            FooterSection()
        }
        .frame(width: 320)
        .padding()
        .background(VisualEffectView())
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
                Text("Claude Companion")
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
                    .environmentObject(serverManager)
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
                QRCodeView(connectionString: serverManager.connectionString)
                    .frame(width: 300, height: 350)
            }

            // Open Logs Button
            QuickActionButton(
                title: "View Activity Monitor",
                icon: "chart.line.uptrend.xyaxis"
            ) {
                NSApp.sendAction(#selector(AppCommands.openActivityMonitor), to: nil, from: nil)
            }
        }
    }

    private func copyConnectionURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serverManager.connectionString, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            copiedToClipboard = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedToClipboard = false
            }
        }

        // Show notification
        NotificationManager.shared.showNotification(
            title: "Copied!",
            body: "Connection URL copied to clipboard"
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

    var body: some View {
        Button(action: toggleServer) {
            HStack(spacing: 12) {
                Image(systemName: serverManager.isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)

                Text(serverManager.isRunning ? "Stop Server" : "Start Server")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)

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
    }

    private func toggleServer() {
        isProcessing = true
        Task {
            if serverManager.isRunning {
                await serverManager.stopServer()
            } else {
                do {
                    try await serverManager.startServer()
                } catch {
                    // Handle error if needed
                    print("Failed to start server: \(error)")
                }
            }
            isProcessing = false
        }
    }
}

// MARK: - Footer Section
struct FooterSection: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Button("Settings...") {
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
            HStack {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 20)

                Text(title)
                    .font(.body)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
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

// MARK: - Visual Effect Background
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .menu
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
