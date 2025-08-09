//
//  MenuBarComponents.swift
//  AICLICompanionHost
//
//  Small UI components for the menu bar dropdown
//

import SwiftUI

// MARK: - Status Indicator
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

// MARK: - Connection Info View
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

// MARK: - Quick Action Button
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

// MARK: - Session Row
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

// MARK: - Activity Indicator
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
