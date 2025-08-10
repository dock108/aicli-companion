//
//  MenuBarIcon.swift
//  AICLICompanionHost
//
//  Menu bar icon that shows server status
//

import SwiftUI
import AppKit

struct MenuBarIcon: View {
    let isServerRunning: Bool

    var body: some View {
        if let nsImage = NSImage(named: "MenuBarIcon") {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .foregroundStyle(isServerRunning ? .primary : .secondary)
                .opacity(isServerRunning ? 1.0 : 0.6)
        } else {
            // Fallback to system icon
            Image(systemName: "server.rack")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isServerRunning ? .green : .secondary)
                .symbolEffect(.pulse, isActive: isServerRunning)
        }
    }
}
