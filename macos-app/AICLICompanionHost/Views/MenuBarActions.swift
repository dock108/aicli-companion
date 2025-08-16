//
//  MenuBarActions.swift
//  AICLICompanionHost
//
//  Action components for the menu bar dropdown
//

import SwiftUI

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
                // Always use connectionString which includes WebSocket path and auth token
                QRCodeView(connectionString: serverManager.connectionString)
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
        // Always use connectionString which includes WebSocket path and auth token
        let urlToCopy = serverManager.connectionString

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
