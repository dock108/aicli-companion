//
//  MenuBarSections.swift
//  AICLICompanionHost
//
//  Main sections for the menu bar dropdown
//

import SwiftUI

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

// MARK: - Active Sessions Section
struct ActiveSessionsSection: View {
    @EnvironmentObject private var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Active Sessions", systemImage: "person.2.fill")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(serverManager.activeSessions.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            VStack(spacing: 4) {
                ForEach(serverManager.activeSessions.prefix(3)) { session in
                    SessionRow(session: session)
                }

                if serverManager.activeSessions.count > 3 {
                    HStack {
                        Spacer()
                        Text("and \(serverManager.activeSessions.count - 3) more...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Footer Section
struct FooterSection: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            Button("Activity Monitor") {
                openWindow(id: "activity-monitor")
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Spacer()

            Button("Settings") {
                // Open Settings window using Settings scene
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
        }
    }
}
