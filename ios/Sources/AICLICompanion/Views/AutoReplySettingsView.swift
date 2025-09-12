import SwiftUI
import CloudKit
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
public struct AutoReplySettingsView: View {
    @StateObject private var store = AutoReplySettingsStore.shared
    @State private var settings: AutoReplySettings
    // Removed unused state variables for simplified UI
    
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
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
                #endif
            }
            // Removed complex sheet presentations and alerts for simplified UI
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
                    .onChange(of: settings.isEnabled) {
                        // Force immediate UI update and save
                        DispatchQueue.main.async {
                            saveSettings()
                        }
                    }
            }
            
            if settings.isEnabled {
                Group {
                    Picker("Mode", selection: $settings.mode) {
                        ForEach(AutoReplyMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .onChange(of: settings.mode) {
                        saveSettings()
                    }
                    
                    Text(settings.mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .transition(.opacity.combined(with: .slide))
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
                    .onChange(of: settings.smartStopSettings.stuckDetectionSensitivity) {
                        saveSettings()
                    }
                    
                    Text("High")
                        .font(.caption)
                }
            }
            
            Toggle("Stop on Errors", isOn: $settings.smartStopSettings.stopOnErrors)
                .onChange(of: settings.smartStopSettings.stopOnErrors) {
                    saveSettings()
                }
            
            Toggle("Stop on Completion", isOn: $settings.smartStopSettings.stopOnCompletion)
                .onChange(of: settings.smartStopSettings.stopOnCompletion) {
                    saveSettings()
                }
            
            Toggle("Require Explicit Completion", isOn: $settings.smartStopSettings.requireExplicitCompletion)
                .onChange(of: settings.smartStopSettings.requireExplicitCompletion) {
                    saveSettings()
                }
            
            Stepper(
                "Max Loop Attempts: \(settings.smartStopSettings.maxLoopAttempts)",
                value: $settings.smartStopSettings.maxLoopAttempts,
                in: 3...20
            )
            .onChange(of: settings.smartStopSettings.maxLoopAttempts) {
                saveSettings()
            }
        }
    }
    
    private var untilCompletionSection: some View {
        Section("Until Completion Settings") {
            Toggle("Require Explicit Completion", isOn: $settings.smartStopSettings.requireExplicitCompletion)
                .onChange(of: settings.smartStopSettings.requireExplicitCompletion) {
                    saveSettings()
                }
            
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
                .onChange(of: settings.timeLimits.minutes) {
                    saveSettings()
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
                .onChange(of: settings.timeLimits.enabled) {
                    saveSettings()
                }
            
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
                    .onChange(of: settings.timeLimits.minutes) {
                        saveSettings()
                    }
                }
                
                Toggle("Extend on Progress", isOn: $settings.timeLimits.extendOnProgress)
                    .onChange(of: settings.timeLimits.extendOnProgress) {
                        saveSettings()
                    }
                
                Stepper(
                    "Warning: \(settings.timeLimits.warningMinutes) min before",
                    value: $settings.timeLimits.warningMinutes,
                    in: 1...30
                )
                .onChange(of: settings.timeLimits.warningMinutes) {
                    saveSettings()
                }
                
                Text("Estimated ~\(settings.timeLimits.estimatedMessages) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var messageBasedSection: some View {
        Section("Message-Based Settings") {
            Toggle("Enable Message Limit", isOn: $settings.messageLimits.enabled)
                .onChange(of: settings.messageLimits.enabled) {
                    saveSettings()
                }
            
            if settings.messageLimits.enabled {
                Stepper(
                    "Max Messages: \(settings.messageLimits.maxMessages)",
                    value: $settings.messageLimits.maxMessages,
                    in: 1...100
                )
                .onChange(of: settings.messageLimits.maxMessages) {
                    saveSettings()
                }
                
                Toggle("Count Only Successful", isOn: $settings.messageLimits.countOnlySuccessful)
                    .onChange(of: settings.messageLimits.countOnlySuccessful) {
                        saveSettings()
                    }
                
                Stepper(
                    "Warning at: \(settings.messageLimits.warningThreshold)",
                    value: $settings.messageLimits.warningCount,
                    in: 1...20
                )
                .onChange(of: settings.messageLimits.warningCount) {
                    saveSettings()
                }
                
                Text("Warning will show \(settings.messageLimits.warningCount) messages before limit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var hybridSection: some View {
        Section("Hybrid Settings") {
            Toggle("Time Limit", isOn: $settings.hybridSettings.enableTimeLimit)
                .onChange(of: settings.hybridSettings.enableTimeLimit) {
                    saveSettings()
                }
            
            Toggle("Message Limit", isOn: $settings.hybridSettings.enableMessageLimit)
                .onChange(of: settings.hybridSettings.enableMessageLimit) {
                    saveSettings()
                }
            
            Toggle("Smart Stop", isOn: $settings.hybridSettings.enableSmartStop)
                .onChange(of: settings.hybridSettings.enableSmartStop) {
                    saveSettings()
                }
            
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
            .onChange(of: settings.hybridSettings.priority) {
                saveSettings()
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
    
    // AI Settings section removed for simplicity - keeping it basic
    
    // Safety section removed for simplicity - keeping it basic
    
    // Advanced section removed for simplicity - keeping it basic
    
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
