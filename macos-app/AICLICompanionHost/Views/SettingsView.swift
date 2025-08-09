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

// MARK: - Security Settings
struct SecuritySettingsView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var showingTokenAlert = false
    @State private var needsRestart = false
    @State private var isRestarting = false
    @State private var showingNgrokSetup = false
    @State private var ngrokInstalled = false
    @State private var checkingNgrok = false

    var body: some View {
        Form {
            // Restart notification bar at top
            if needsRestart && serverManager.isRunning {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Server Restart Required")
                                .font(.headline)
                            Text("Settings have changed that require a server restart")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: restartServer) {
                            if isRestarting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(.circular)
                            } else {
                                Text("Restart Now")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRestarting)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Require Authentication", isOn: $settingsManager.requireAuthentication)
                    .help("Clients must provide an authentication token to connect")
                    .onChange(of: settingsManager.requireAuthentication) { _, newValue in
                        Task { @MainActor in
                            // If enabling auth and we're exposed to internet, ensure we have a token
                            if newValue && settingsManager.enableTunnel && serverManager.authToken == nil {
                                serverManager.generateAuthToken()
                            }
                            // Mark that restart is needed if server is running
                            if serverManager.isRunning {
                                needsRestart = true
                            }
                        }
                    }

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

            Section {
                Toggle("Enable Internet Access", isOn: $settingsManager.enableTunnel)
                    .help("Expose your server to the internet using a secure tunnel")
                    .onChange(of: settingsManager.enableTunnel) { _, newValue in
                        Task { @MainActor in
                            if newValue {
                                // Auto-enable authentication when exposing to internet
                                settingsManager.requireAuthentication = true
                                if serverManager.authToken == nil {
                                    serverManager.generateAuthToken()
                                }
                            }
                            // Mark that restart is needed if server is running
                            if serverManager.isRunning {
                                needsRestart = true
                            }
                        }
                    }

                if settingsManager.enableTunnel {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Tunnel Provider", selection: $settingsManager.tunnelProvider) {
                            Text("ngrok").tag("ngrok")
                            Text("Cloudflare").tag("cloudflare")
                                .disabled(true)  // Future support
                        }
                        .pickerStyle(.segmented)

                        if settingsManager.tunnelProvider == "ngrok" {
                            // ngrok Setup Section
                            VStack(alignment: .leading, spacing: 12) {
                                // Auth Token Input
                                LabeledContent("Auth Token") {
                                    HStack {
                                        SecureField("", text: $settingsManager.ngrokAuthToken)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 200)
                                            .onChange(of: settingsManager.ngrokAuthToken) { _, _ in
                                                Task { @MainActor in
                                                    if serverManager.isRunning && settingsManager.enableTunnel {
                                                        needsRestart = true
                                                    }
                                                }
                                            }

                                        Button("Get Token") {
                                            NSWorkspace.shared.open(
                                                URL(string: "https://dashboard.ngrok.com/auth/your-authtoken")!
                                            )
                                        }
                                        .buttonStyle(.link)
                                    }
                                }

                                // Setup Status
                                HStack(spacing: 8) {
                                    if checkingNgrok {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .progressViewStyle(.circular)
                                        Text("Checking ngrok...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if !settingsManager.ngrokAuthToken.isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text("ngrok configured")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        Button("Setup ngrok") {
                                            showingNgrokSetup = true
                                        }
                                        .buttonStyle(.bordered)

                                        Text("Required for tunneling")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                // Quick Setup Guide
                                if settingsManager.ngrokAuthToken.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Quick Setup:")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("1. Sign up for free at ngrok.com")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("2. Copy your auth token from dashboard")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("3. Paste token above and restart server")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                            }
                        }

                        if serverManager.isRunning, let publicURL = serverManager.publicURL {
                            Divider()

                            LabeledContent("Public URL") {
                                HStack {
                                    Text(publicURL)
                                        .fontDesign(.monospaced)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .padding(6)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(4)
                                        .contextMenu {
                                            Button("Copy") {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(publicURL, forType: .string)
                                            }
                                        }
                                }
                            }
                        }
                    }
                }

                Text("⚠️ When Internet Access is enabled, authentication is mandatory for security")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .opacity(settingsManager.enableTunnel ? 1 : 0)
            } header: {
                Text("Internet Access")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            // Configuration Change Indicator
            if settingsManager.needsRestart {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Server restart required to apply settings changes")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    Button(action: restartServer) {
                        HStack {
                            if isRestarting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRestarting ? "Restarting..." : "Apply Changes")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isRestarting)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
        .alert("Generate New Token?", isPresented: $showingTokenAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Generate", role: .destructive) {
                serverManager.generateAuthToken()
            }
        } message: {
            Text("""
                This will invalidate the current token. \
                All connected clients will need to reconnect with the new token.
                """)
        }
        .sheet(isPresented: $showingNgrokSetup) {
            NgrokSetupView(
                ngrokAuthToken: $settingsManager.ngrokAuthToken,
                isPresented: $showingNgrokSetup,
                needsRestart: $needsRestart
            )
        }
        .onAppear {
            checkNgrokInstallation()
        }
    }

    private func restartServer() {
        isRestarting = true
        Task {
            do {
                try await serverManager.restartServerWithCurrentConfig()
                await MainActor.run {
                    needsRestart = false
                }
            } catch {
                await MainActor.run {
                    serverManager.addLog(.error, "Failed to restart server: \(error.localizedDescription)")
                }
                print("Failed to restart server: \(error)")
            }
            await MainActor.run {
                isRestarting = false
            }
        }
    }

    private func checkNgrokInstallation() {
        checkingNgrok = true
        Task {
            // Check if ngrok is available in common locations
            let paths = [
                "/opt/homebrew/bin/ngrok",
                "/usr/local/bin/ngrok",
                "/usr/bin/ngrok"
            ]

            for path in paths where FileManager.default.fileExists(atPath: path) {
                await MainActor.run {
                    ngrokInstalled = true
                    checkingNgrok = false
                }
                return
            }

            // Check using which command
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = ["ngrok"]

            do {
                try task.run()
                task.waitUntilExit()
                await MainActor.run {
                    ngrokInstalled = task.terminationStatus == 0
                    checkingNgrok = false
                }
            } catch {
                await MainActor.run {
                    ngrokInstalled = false
                    checkingNgrok = false
                }
            }
        }
    }
}

// MARK: - ngrok Setup View
struct NgrokSetupView: View {
    @Binding var ngrokAuthToken: String
    @Binding var isPresented: Bool
    @Binding var needsRestart: Bool
    @State private var tempToken = ""
    @State private var currentStep = 1
    @State private var ngrokInstalled = false
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading) {
                    Text("ngrok Setup Wizard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Expose your server to the internet securely")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Content
            VStack(spacing: 20) {
                // Step indicator
                HStack(spacing: 30) {
                    StepIndicator(number: 1, title: "Sign Up", isActive: currentStep >= 1)
                    StepIndicator(number: 2, title: "Get Token", isActive: currentStep >= 2)
                    StepIndicator(number: 3, title: "Configure", isActive: currentStep >= 3)
                }
                .padding(.vertical)

                // Step content
                Group {
                    switch currentStep {
                    case 1:
                        Step1View()
                    case 2:
                        Step2View(tempToken: $tempToken)
                    case 3:
                        Step3View(tempToken: tempToken, ngrokInstalled: ngrokInstalled)
                    default:
                        EmptyView()
                    }
                }
                .frame(minHeight: 200)

                Spacer()

                // Navigation buttons
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            currentStep -= 1
                        }
                    }

                    Spacer()

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)

                    if currentStep < 3 {
                        Button("Next") {
                            currentStep += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentStep == 2 && tempToken.isEmpty)
                    } else {
                        Button("Finish") {
                            ngrokAuthToken = tempToken
                            needsRestart = true
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tempToken.isEmpty)
                    }
                }
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onAppear {
            tempToken = ngrokAuthToken
            checkNgrokInstallation()
        }
    }

    private func checkNgrokInstallation() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["ngrok"]

        do {
            try task.run()
            task.waitUntilExit()
            ngrokInstalled = task.terminationStatus == 0
        } catch {
            ngrokInstalled = false
        }
    }
}

struct StepIndicator: View {
    let number: Int
    let title: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 30, height: 30)
                .overlay(
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )

            Text(title)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}

struct Step1View: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Create a free ngrok account")
                .font(.headline)

            Text("""
                ngrok provides secure tunnels to expose your local server to the internet. \
                Sign up for a free account to get started.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open ngrok.com") {
                NSWorkspace.shared.open(URL(string: "https://ngrok.com/signup")!)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct Step2View: View {
    @Binding var tempToken: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Get your authentication token")
                .font(.headline)

            Text("After signing up, copy your auth token from the ngrok dashboard")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open Dashboard") {
                NSWorkspace.shared.open(URL(string: "https://dashboard.ngrok.com/auth/your-authtoken")!)
            }
            .buttonStyle(.bordered)

            Divider()

            LabeledContent("Auth Token:") {
                SecureField("Paste your token here", text: $tempToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
        }
        .padding()
    }
}

struct Step3View: View {
    let tempToken: String
    let ngrokInstalled: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text("Ready to connect!")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label(tempToken.isEmpty ? "Token required" : "Token configured",
                      systemImage: tempToken.isEmpty ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(tempToken.isEmpty ? .red : .green)

                Label("Server will use bundled ngrok",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)

                Label("Authentication will be enforced",
                      systemImage: "lock.fill")
                    .foregroundStyle(.blue)
            }
            .font(.caption)

            Text("Click Finish to save settings. You'll need to restart the server for changes to take effect.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
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

            Section {
                Text("⚠️ Modifying these settings may prevent the server from starting correctly")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text("Leave Node.js and npm paths empty to auto-detect from NVM, Homebrew, or system installations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Warning")
            }
        }
        .formStyle(.grouped)
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
