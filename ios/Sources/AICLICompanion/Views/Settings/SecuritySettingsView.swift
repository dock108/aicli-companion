import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct SecuritySettingsView: View {
    @StateObject private var securityManager = SecurityManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddDirectory = false
    @State private var showingAddCommand = false
    @State private var showingTestCommand = false
    @State private var newDirectory = ""
    @State private var newCommand = ""
    @State private var testCommand = ""
    @State private var testResult: TestCommandResponse?
    
    var body: some View {
        NavigationStack {
            Form {
                // Security Preset Section
                Section {
                    Picker("Security Preset", selection: $securityManager.configuration.preset) {
                        ForEach(SecurityPreset.allCases, id: \.self) { preset in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(preset.displayName)
                                    Text(preset.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: preset.icon)
                            }
                            .tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: securityManager.configuration.preset) { _, newPreset in
                        securityManager.applyPreset(newPreset)
                    }
                } header: {
                    Text("Security Level")
                } footer: {
                    Text("Choose a preset security configuration or customize your own")
                }
                
                // Quick Controls
                Section("Quick Controls") {
                    Toggle("Enable Command Filtering", isOn: $securityManager.filterCommands)
                        .onChange(of: securityManager.filterCommands) { _, enabled in
                            if !enabled {
                                securityManager.configuration.preset = .unrestricted
                            }
                        }
                    
                    Toggle("Block Destructive Commands", isOn: $securityManager.blockDestructive)
                        .onChange(of: securityManager.blockDestructive) { _, enabled in
                            securityManager.configuration.requireConfirmation = enabled
                        }
                    
                    Toggle("Read-Only Mode", isOn: $securityManager.readOnlyMode)
                        .onChange(of: securityManager.readOnlyMode) { _, enabled in
                            securityManager.configuration.readOnlyMode = enabled
                            if enabled {
                                securityManager.configuration.preset = .custom
                            }
                        }
                    
                    Toggle("Enable Audit Logging", isOn: $securityManager.configuration.enableAudit)
                }
                
                // Safe Directories
                Section {
                    if securityManager.configuration.safeDirectories.isEmpty {
                        Text("No directories configured")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(securityManager.configuration.safeDirectories, id: \.self) { directory in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.accentColor)
                                Text(directory)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    securityManager.removeSafeDirectory(directory)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    Button {
                        showingAddDirectory = true
                    } label: {
                        Label("Add Directory", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Safe Directories")
                } footer: {
                    Text("Claude can only operate within these directories when restrictions are enabled")
                }
                
                // Blocked Commands
                Section {
                    if securityManager.configuration.blockedCommands.isEmpty {
                        Text("No commands blocked")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(securityManager.configuration.blockedCommands, id: \.self) { command in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                Text(command)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    securityManager.removeBlockedCommand(command)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    Button {
                        showingAddCommand = true
                    } label: {
                        Label("Add Pattern", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Blocked Commands")
                } footer: {
                    Text("Commands matching these patterns will be blocked")
                }
                
                // Advanced Settings
                Section("Advanced") {
                    HStack {
                        Text("Max File Size")
                        Spacer()
                        Text(formatBytes(securityManager.configuration.maxFileSize))
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink {
                        AuditLogView()
                    } label: {
                        Label("View Audit Log", systemImage: "doc.text.magnifyingglass")
                    }
                    
                    Button {
                        showingTestCommand = true
                    } label: {
                        Label("Test Command", systemImage: "terminal")
                    }
                }
                
                // Server Sync
                Section {
                    Button {
                        Task {
                            await securityManager.updateServerConfiguration()
                        }
                    } label: {
                        Label("Push to Server", systemImage: "arrow.up.circle")
                    }
                    .disabled(securityManager.isLoading)
                    
                    Button {
                        Task {
                            await securityManager.fetchCurrentConfiguration()
                        }
                    } label: {
                        Label("Pull from Server", systemImage: "arrow.down.circle")
                    }
                    .disabled(securityManager.isLoading)
                } header: {
                    Text("Synchronization")
                } footer: {
                    if let error = securityManager.lastError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Security")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddDirectory) {
                AddItemSheet(
                    title: "Add Safe Directory",
                    placeholder: "/path/to/directory",
                    value: $newDirectory
                ) {
                    if !newDirectory.isEmpty {
                        securityManager.addSafeDirectory(newDirectory)
                        newDirectory = ""
                    }
                }
            }
            .sheet(isPresented: $showingAddCommand) {
                AddItemSheet(
                    title: "Add Blocked Pattern",
                    placeholder: "rm -rf",
                    value: $newCommand
                ) {
                    if !newCommand.isEmpty {
                        securityManager.addBlockedCommand(newCommand)
                        newCommand = ""
                    }
                }
            }
            .sheet(isPresented: $showingTestCommand) {
                TestCommandSheet(
                    command: $testCommand,
                    result: $testResult
                )
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Add Item Sheet
@available(iOS 16.0, macOS 13.0, *)
struct AddItemSheet: View {
    let title: String
    let placeholder: String
    @Binding var value: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $value)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter the full path or pattern")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd()
                        dismiss()
                    }
                    .disabled(value.isEmpty)
                }
            }
        }
    }
}

// MARK: - Test Command Sheet
@available(iOS 16.0, macOS 13.0, *)
struct TestCommandSheet: View {
    @Binding var command: String
    @Binding var result: TestCommandResponse?
    @State private var workingDirectory = "/tmp"
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Test Command") {
                    TextField("Command", text: $command)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    TextField("Working Directory", text: $workingDirectory)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                
                if let result = result {
                    Section("Result") {
                        HStack {
                            Image(systemName: result.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.allowed ? .green : .red)
                            Text(result.allowed ? "Allowed" : "Blocked")
                                .fontWeight(.semibold)
                        }
                        
                        if let reason = result.reason {
                            Label(reason, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if result.requiresConfirmation {
                            Label("Requires confirmation", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Section {
                    Button {
                        Task {
                            isLoading = true
                            result = await SecurityManager.shared.testCommand(command, workingDirectory: workingDirectory)
                            isLoading = false
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Test Command")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(command.isEmpty || isLoading)
                }
            }
            .navigationTitle("Test Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Audit Log View
@available(iOS 16.0, macOS 13.0, *)
struct AuditLogView: View {
    @StateObject private var securityManager = SecurityManager.shared
    @State private var isRefreshing = false
    
    var body: some View {
        List {
            if securityManager.auditLog.isEmpty {
                ContentUnavailableView(
                    "No Audit Entries",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Security audit log is empty")
                )
            } else {
                ForEach(securityManager.auditLog) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: entry.statusIcon)
                                .foregroundColor(entry.allowed ? .green : .red)
                            Text(entry.command)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        HStack {
                            Text(entry.formattedTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let dir = entry.workingDirectory {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(dir)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        
                        if let reason = entry.reason {
                            Text(reason)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await securityManager.fetchAuditLog()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await securityManager.clearAuditLog()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(securityManager.auditLog.isEmpty)
            }
        }
        .task {
            await securityManager.fetchAuditLog()
        }
    }
}
