//
//  ActivityMonitorView.swift
//  AICLICompanionHost
//
//  Real-time activity monitoring and log viewer
//

import SwiftUI
import Charts

struct ActivityMonitorView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var selectedLogLevel: LogLevel?
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Tab Selection
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Sessions").tag(1)
                Text("Logs").tag(2)
                Text("Performance").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab Content
            switch selectedTab {
            case 0:
                OverviewTab()
            case 1:
                SessionsTab()
            case 2:
                LogsTab(
                    searchText: $searchText,
                    selectedLogLevel: $selectedLogLevel,
                    autoScroll: $autoScroll
                )
            case 3:
                PerformanceTab()
            default:
                EmptyView()
            }
        }
        .frame(width: 800, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
