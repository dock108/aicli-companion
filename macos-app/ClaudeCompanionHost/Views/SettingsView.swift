//
//  SettingsView.swift
//  ClaudeCompanionHost
//
//  The preferences window for the app
//

import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager

    private enum Tabs: Hashable {
        case general
        case server
        case security
        case logs
        case advanced
    }

    var body: some View {
        TabView {
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
                LabeledContent("Default Directory") {
                    HStack {
                        Text(settingsManager.serverDirectory)
                            .fontDesign(.monospaced)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .leading)

                        Button("Browse...") {
                            showingDirectoryPicker = true
                        }
                    }
                }
            } header: {
                Text("Server Directory")
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
            defaultFilename: "claude-companion-settings.json"
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
        // Update launch at login status
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
                settingsManager.serverDirectory = url.path
                NotificationManager.shared.showNotification(
                    title: "Directory Updated",
                    body: "Server directory has been changed"
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

// MARK: - Security Settings
struct SecuritySettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingTokenAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("Require Authentication", isOn: $settingsManager.requireAuthentication)
                    .help("Clients must provide an authentication token to connect")

                if settingsManager.requireAuthentication {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Authentication Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            if let token = serverManager.authToken {
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
            } header: {
                Text("Authentication")
            }

            Section {
                Toggle("Enable Touch ID", isOn: $settingsManager.enableTouchID)
                    .help("Use Touch ID to authenticate admin actions")

                Text("The authentication token is securely stored in the macOS Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("macOS Security")
            }
        }
        .formStyle(.grouped)
        .alert("Generate New Token?", isPresented: $showingTokenAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Generate", role: .destructive) {
                serverManager.generateAuthToken()
            }
        } message: {
            Text("This will invalidate the current token. All connected clients will need to reconnect with the new token.")
        }
    }
}

// MARK: - Advanced Settings
struct AdvancedSettingsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingDirectoryPicker = false

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
                    TextField("", text: $settingsManager.nodeExecutable)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .font(.caption)
                        .frame(width: 200)
                }

                LabeledContent("npm Path") {
                    TextField("", text: $settingsManager.npmExecutable)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .font(.caption)
                        .frame(width: 200)
                }
            } header: {
                Text("Executables")
            }

            Section {
                Text("⚠️ Modifying these settings may prevent the server from starting correctly")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } header: {
                Text("Warning")
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    settingsManager.serverDirectory = url.path
                }
            case .failure(let error):
                print("Directory selection failed: \(error)")
            }
        }
    }
}

// MARK: - Settings Document
struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    @MainActor private let settingsData: Data

    @MainActor
    init(settingsManager: SettingsManager) {
        // Export settings data at initialization time on the main actor
        self.settingsData = settingsManager.exportSettings() ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        // This is export-only, so we don't support reading
        self.settingsData = Data()
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: settingsData)
    }
}
