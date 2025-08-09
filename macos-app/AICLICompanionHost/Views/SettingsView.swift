//
//  SettingsView.swift
//  AICLICompanionHost
//
//  The preferences window for the app
//

import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var selectedTab: Tabs = .general

    private enum Tabs: Hashable {
        case general
        case server
        case security
        case logs
        case advanced
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tabs.general)

            ServerSettingsView()
                .tabItem {
                    Label("Server", systemImage: "server.rack")
                }
                .tag(Tabs.server)

            SecuritySettingsView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
                .tag(Tabs.security)

            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
                .tag(Tabs.logs)

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
                .tag(Tabs.advanced)
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 550)
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingImportPicker = false
    @State private var showingExportPicker = false
    @State private var showingDirectoryPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settingsManager.launchAtLogin)
                    .onChange(of: settingsManager.launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }

                Toggle("Show Dock Icon", isOn: $settingsManager.showDockIcon)
                    .onChange(of: settingsManager.showDockIcon) { _, newValue in
                        updateDockIconVisibility(newValue)
                    }

                Toggle("Auto-start Server", isOn: $settingsManager.autoStartServer)
            } header: {
                Text("General")
            }

            Section {
                LabeledContent("Default Project Directory") {
                    HStack {
                        Text(settingsManager.defaultProjectDirectory.isEmpty
                             ? "Not Set"
                             : settingsManager.defaultProjectDirectory)
                            .fontDesign(.monospaced)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .leading)
                            .foregroundStyle(settingsManager.defaultProjectDirectory.isEmpty ? .secondary : .primary)

                        Button("Browse...") {
                            showingDirectoryPicker = true
                        }
                    }
                }
                .help("The default directory for your Claude projects")
            } header: {
                Text("Project Settings")
            }
            Section {
                Toggle("Enable Notifications", isOn: $settingsManager.enableNotifications)
                    .onChange(of: settingsManager.enableNotifications) { _, newValue in
                        if newValue {
                            Task {
                                await NotificationManager.shared.requestAuthorization()
                            }
                        }
                    }
                Toggle("Enable Sounds", isOn: $settingsManager.enableSounds)
                    .disabled(!settingsManager.enableNotifications)
            } header: {
                Text("Notifications")
            }
            Section {
                Picker("Theme", selection: $settingsManager.theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }
            Section {
                HStack {
                    Button("Export Settings...") {
                        showingExportPicker = true
                    }

                    Button("Import Settings...") {
                        showingImportPicker = true
                    }

                    Spacer()

                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text("Settings Management")
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: SettingsDocument(settingsManager: settingsManager),
            contentType: .json,
            defaultFilename: "aicli-companion-settings.json"
        ) { result in
            handleExport(result)
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDirectorySelection(result)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }

    private func updateDockIconVisibility(_ showIcon: Bool) {
        NSApp.setActivationPolicy(showIcon ? .regular : .accessory)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try Data(contentsOf: url)
                try settingsManager.importSettings(from: data)
                NotificationManager.shared.showNotification(
                    title: "Settings Imported",
                    body: "Your settings have been successfully imported"
                )
            } catch {
                NotificationManager.shared.showNotification(
                    title: "Import Failed",
                    body: error.localizedDescription
                )
            }
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            NotificationManager.shared.showNotification(
                title: "Settings Exported",
                body: "Your settings have been successfully exported"
            )
        case .failure(let error):
            print("Export failed: \(error)")
        }
    }

    private func resetToDefaults() {
        settingsManager.resetToDefaults()
        NotificationManager.shared.showNotification(
            title: "Settings Reset",
            body: "All settings have been reset to defaults"
        )
    }

    private func handleDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                settingsManager.defaultProjectDirectory = url.path
                NotificationManager.shared.showNotification(
                    title: "Directory Updated",
                    body: "Default project directory has been changed"
                )
            }
        case .failure(let error):
            print("Directory selection failed: \(error)")
            NotificationManager.shared.showNotification(
                title: "Directory Selection Failed",
                body: error.localizedDescription
            )
        }
    }
}

// MARK: - Server Settings
struct ServerSettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var selectedInterface: NetworkInterface?

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Port", value: $settingsManager.serverPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("(1024-65535)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Picker("Network Interface", selection: $selectedInterface) {
                    Text("All Interfaces (0.0.0.0)").tag(nil as NetworkInterface?)

                    ForEach(NetworkMonitor.shared.availableInterfaces) { interface in
                        Label {
                            Text("\(interface.displayName) - \(interface.address)")
                        } icon: {
                            Image(systemName: interface.icon)
                        }
                        .tag(interface as NetworkInterface?)
                    }
                }

                Toggle("Enable Bonjour Discovery", isOn: $settingsManager.enableBonjour)
                    .help("Allows devices on the local network to discover this server")
            } header: {
                Text("Server Configuration")
            }

            Section {
                Picker("Log Level", selection: $settingsManager.logLevel) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warning").tag("warning")
                    Text("Error").tag("error")
                }

                HStack {
                    TextField("Max Log Entries", value: $settingsManager.maxLogEntries, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("entries")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Logging")
            }
            Section {
                LabeledContent("Current Status") {
                    HStack {
                        Circle()
                            .fill(serverManager.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(serverManager.isRunning ? "Running" : "Stopped")
                            .font(.caption)
                    }
                }

                if serverManager.isRunning {
                    LabeledContent("Local IP") {
                        Text(serverManager.localIP)
                            .fontDesign(.monospaced)
                            .font(.caption)
                    }

                    LabeledContent("Active Sessions") {
                        Text(String(serverManager.activeSessions.count))
                            .font(.caption)
                    }
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedInterface = NetworkMonitor.shared.availableInterfaces.first
        }
    }
}

// MARK: - Advanced Settings
struct AdvancedSettingsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                LabeledContent("Server Command") {
                    TextField("", text: $settingsManager.serverCommand)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .font(.caption)
                        .frame(width: 200)
                }
                .help("Command to start the server (e.g., 'npm start')")
            } header: {
                Text("Server Configuration")
            }

            Section {
                LabeledContent("Node.js Path") {
                    TextField("Auto-detect", text: $settingsManager.nodeExecutable)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .font(.caption)
                        .frame(width: 300)
                }
                .help("Leave empty for auto-detection")

                LabeledContent("npm Path") {
                    TextField("Auto-detect", text: $settingsManager.npmExecutable)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .font(.caption)
                        .frame(width: 300)
                }
                .help("Leave empty for auto-detection")
            } header: {
                Text("Executables")
            }

            Section("Warning") {
                Text("⚠️ Modifying these settings may prevent the server from starting correctly")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Leave Node.js and npm paths empty to auto-detect from NVM, Homebrew, or system installations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
