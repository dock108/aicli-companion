import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
public struct AutoReplySettingsView: View {
    @StateObject private var store = AutoReplySettingsStore.shared
    @State private var settings: AutoReplySettings
    @State private var showingQuickSetup = false
    @State private var showingImportExport = false
    @State private var showingDeleteConfirmation = false
    
    @Environment(\.dismiss) private var dismiss
    
    private let projectId: UUID
    private let projectName: String
    
    public init(projectId: UUID, projectName: String) {
        self.projectId = projectId
        self.projectName = projectName
        
        let initialSettings = AutoReplySettingsStore.shared.getOrCreateSettings(
            for: projectId,
            projectName: projectName
        )
        self._settings = State(initialValue: initialSettings)
    }
    
    public var body: some View {
        NavigationView {
            Form {
                mainSettingsSection
                modeSpecificSection
                aiSettingsSection
                safetySection
                advancedSection
                
                if store.syncStatus != .idle {
                    syncStatusSection
                }
            }
            .navigationTitle("Auto-Reply Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                #endif
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingQuickSetup) {
                QuickSetupView(
                    projectId: projectId,
                    projectName: projectName
                ) { quickSettings in
                    settings = quickSettings
                }
            }
            .sheet(isPresented: $showingImportExport) {
                ImportExportView()
            }
            .alert("Delete Settings", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    store.deleteSettings(for: projectId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete the auto-reply settings for this project. This action cannot be undone.")
            }
        }
        .onAppear {
            if let existingSettings = store.settings(for: projectId) {
                settings = existingSettings
            }
        }
    }
    
    // MARK: - Sections
    
    private var mainSettingsSection: some View {
        Section {
            HStack {
                Toggle("Enable Auto-Reply", isOn: $settings.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            
            if settings.isEnabled {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(AutoReplyMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                
                Text(settings.mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        } header: {
            Text("Basic Settings")
        } footer: {
            if !settings.isEnabled {
                Text("Auto-reply is disabled. Claude will not automatically respond to messages.")
            }
        }
    }
    
    @ViewBuilder
    private var modeSpecificSection: some View {
        if settings.isEnabled {
            switch settings.mode {
            case .smartStop:
                smartStopSection
            case .untilCompletion:
                untilCompletionSection
            case .timeBased:
                timeBasedSection
            case .messageBased:
                messageBasedSection
            case .hybrid:
                hybridSection
            }
        }
    }
    
    private var smartStopSection: some View {
        Section("Smart Stop Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stuck Detection Sensitivity")
                    .font(.subheadline)
                
                HStack {
                    Text("Low")
                        .font(.caption)
                    
                    Slider(
                        value: Binding(
                            get: { Double(settings.smartStopSettings.stuckDetectionSensitivity) },
                            set: { settings.smartStopSettings.stuckDetectionSensitivity = Int($0) }
                        ),
                        in: 1...5,
                        step: 1
                    )
                    
                    Text("High")
                        .font(.caption)
                }
            }
            
            Toggle("Stop on Errors", isOn: $settings.smartStopSettings.stopOnErrors)
            Toggle("Stop on Completion", isOn: $settings.smartStopSettings.stopOnCompletion)
            Toggle("Require Explicit Completion", isOn: $settings.smartStopSettings.requireExplicitCompletion)
            
            Stepper(
                "Max Loop Attempts: \(settings.smartStopSettings.maxLoopAttempts)",
                value: $settings.smartStopSettings.maxLoopAttempts,
                in: 3...20
            )
        }
    }
    
    private var untilCompletionSection: some View {
        Section("Until Completion Settings") {
            Toggle("Require Explicit Completion", isOn: $settings.smartStopSettings.requireExplicitCompletion)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Safety Time Limit")
                    Spacer()
                    Text("\(settings.timeLimits.minutes) min")
                        .foregroundColor(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(settings.timeLimits.minutes) },
                        set: { settings.timeLimits.minutes = Int($0) }
                    ),
                    in: 30...480,
                    step: 30
                ) {
                    Text("Safety Limit")
                } minimumValueLabel: {
                    Text("30m")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("8h")
                        .font(.caption)
                }
            }
            
            Text("Safety limit prevents infinite loops")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var timeBasedSection: some View {
        Section("Time-Based Settings") {
            Toggle("Enable Time Limit", isOn: $settings.timeLimits.enabled)
            
            if settings.timeLimits.enabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(settings.timeLimits.minutes) min")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(settings.timeLimits.minutes) },
                            set: { settings.timeLimits.minutes = Int($0) }
                        ),
                        in: 5...240,
                        step: 5
                    ) {
                        Text("Duration")
                    } minimumValueLabel: {
                        Text("5m")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("4h")
                            .font(.caption)
                    }
                }
                
                Toggle("Extend on Progress", isOn: $settings.timeLimits.extendOnProgress)
                
                Stepper(
                    "Warning: \(settings.timeLimits.warningMinutes) min before",
                    value: $settings.timeLimits.warningMinutes,
                    in: 1...30
                )
                
                Text("Estimated ~\(settings.timeLimits.estimatedMessages) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var messageBasedSection: some View {
        Section("Message-Based Settings") {
            Toggle("Enable Message Limit", isOn: $settings.messageLimits.enabled)
            
            if settings.messageLimits.enabled {
                Stepper(
                    "Max Messages: \(settings.messageLimits.maxMessages)",
                    value: $settings.messageLimits.maxMessages,
                    in: 1...100
                )
                
                Toggle("Count Only Successful", isOn: $settings.messageLimits.countOnlySuccessful)
                
                Stepper(
                    "Warning at: \(settings.messageLimits.warningThreshold)",
                    value: $settings.messageLimits.warningCount,
                    in: 1...20
                )
                
                Text("Warning will show \(settings.messageLimits.warningCount) messages before limit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var hybridSection: some View {
        Section("Hybrid Settings") {
            Toggle("Time Limit", isOn: $settings.hybridSettings.enableTimeLimit)
            Toggle("Message Limit", isOn: $settings.hybridSettings.enableMessageLimit)
            Toggle("Smart Stop", isOn: $settings.hybridSettings.enableSmartStop)
            
            Picker("Stop Priority", selection: $settings.hybridSettings.priority) {
                ForEach(StopPriority.allCases, id: \.self) { priority in
                    VStack(alignment: .leading) {
                        Text(priority.displayName)
                        Text(priority.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(priority)
                }
            }
            
            if settings.hybridSettings.enableTimeLimit {
                timeBasedSection
            }
            
            if settings.hybridSettings.enableMessageLimit {
                messageBasedSection
            }
            
            if settings.hybridSettings.enableSmartStop {
                smartStopSection
            }
        }
    }
    
    private var aiSettingsSection: some View {
        Section("AI Settings") {
            Toggle("Use AI Responses", isOn: $settings.useAI)
            
            if settings.useAI {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Minimum Confidence")
                        Spacer()
                        Text("\(Int(settings.minConfidence * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $settings.minConfidence, in: 0.3...0.95, step: 0.05) {
                        Text("Confidence")
                    } minimumValueLabel: {
                        Text("30%")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("95%")
                            .font(.caption)
                    }
                }
                
                Toggle("Learning Enabled", isOn: $settings.learningEnabled)
                
                Text("AI will learn from accepted responses to improve future suggestions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Using template-based responses only")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var safetySection: some View {
        Section("Safety") {
            Toggle("Allow Override", isOn: $settings.allowOverride)
            Toggle("Require Confirmation", isOn: $settings.requireConfirmation)
            Toggle("Notify on Stop", isOn: $settings.notifyOnStop)
            Toggle("Save History", isOn: $settings.saveHistory)
        } footer: {
            Text("Safety features help prevent unintended actions and provide transparency.")
        }
    }
    
    private var advancedSection: some View {
        Section("Advanced") {
            Button("Quick Setup...") {
                showingQuickSetup = true
            }
            
            Button("Import/Export...") {
                showingImportExport = true
            }
            
            Button("Reset to Defaults") {
                settings = store.getDefaultSettings(for: projectId, projectName: projectName)
            }
            
            Button("Delete Settings", role: .destructive) {
                showingDeleteConfirmation = true
            }
        }
    }
    
    private var syncStatusSection: some View {
        Section("Sync Status") {
            HStack {
                Image(systemName: syncStatusIcon)
                    .foregroundColor(store.syncStatus.color)
                
                Text(store.syncStatus.displayName)
                
                Spacer()
                
                if store.syncStatus == .syncing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if store.syncStatus == .failed, let error = store.lastError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var syncStatusIcon: String {
        switch store.syncStatus {
        case .idle: return "icloud"
        case .syncing: return "icloud.and.arrow.up"
        case .completed: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }
    
    // MARK: - Actions
    
    private func saveSettings() {
        store.updateSettings(settings)
    }
}

// MARK: - Quick Setup View

@available(iOS 16.0, macOS 13.0, *)
private struct QuickSetupView: View {
    let projectId: UUID
    let projectName: String
    let onSelect: (AutoReplySettings) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(QuickSettingsScenario.allCases, id: \.self) { scenario in
                        Button(action: {
                            let settings = AutoReplySettingsStore.shared.createQuickSettings(
                                for: projectId,
                                projectName: projectName,
                                scenario: scenario
                            )
                            onSelect(settings)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: scenario.icon)
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scenario.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(scenario.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Choose a Preset")
                } footer: {
                    Text("Select a preset configuration that matches your workflow. You can customize it further after selection.")
                }
            }
            .navigationTitle("Quick Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .confirmationAction) {
                #endif
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Import/Export View

@available(iOS 16.0, macOS 13.0, *)
private struct ImportExportView: View {
    @StateObject private var store = AutoReplySettingsStore.shared
    @State private var showingFilePicker = false
    @State private var showingShareSheet = false
    @State private var exportedData: Data?
    @State private var alertMessage: String?
    @State private var showingAlert = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Button("Export All Settings") {
                        exportSettings()
                    }
                    
                    Button("Import Settings") {
                        showingFilePicker = true
                    }
                } header: {
                    Text("Settings Management")
                } footer: {
                    Text("Export your settings to backup or share with other devices. Import to restore previous settings.")
                }
                
                Section {
                    Button("Sync with CloudKit") {
                        Task {
                            await store.syncWithCloudKit()
                        }
                    }
                    .disabled(store.syncStatus == .syncing)
                    
                    if store.syncStatus != .idle {
                        HStack {
                            Image(systemName: syncStatusIcon)
                                .foregroundColor(store.syncStatus.color)
                            Text(store.syncStatus.displayName)
                        }
                    }
                } header: {
                    Text("Cloud Sync")
                } footer: {
                    Text("Sync your settings across all your devices using iCloud.")
                }
            }
            .navigationTitle("Import/Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .confirmationAction) {
                #endif
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Settings", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            if let alertMessage = alertMessage {
                Text(alertMessage)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            #if os(iOS)
            if let data = exportedData {
                ShareSheet(items: [data])
            }
            #endif
        }
    }
    
    private var syncStatusIcon: String {
        switch store.syncStatus {
        case .idle: return "icloud"
        case .syncing: return "icloud.and.arrow.up"
        case .completed: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }
    
    private func exportSettings() {
        do {
            let data = try store.exportSettings()
            exportedData = data
            showingShareSheet = true
        } catch {
            alertMessage = "Failed to export settings: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// MARK: - Share Sheet

#if os(iOS)
@available(iOS 16.0, *)
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
#endif

// MARK: - Preview

@available(iOS 16.0, macOS 13.0, *)
struct AutoReplySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AutoReplySettingsView(
            projectId: UUID(),
            projectName: "Sample Project"
        )
    }
}
