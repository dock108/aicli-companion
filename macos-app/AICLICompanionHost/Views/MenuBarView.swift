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
