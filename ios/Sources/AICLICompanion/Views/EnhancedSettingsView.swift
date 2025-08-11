import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct EnhancedSettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var autoResponseManager = AutoResponseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @State private var showingDisconnectConfirmation = false
    @State private var isDisconnecting = false
    @State private var disconnectSuccess = false
    @State private var selectedTab: SettingsTab = .connection
    @State private var stopPhrasesText = ""
    @State private var showingResetConfirmation = false
    
    private var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    enum SettingsTab: String, CaseIterable {
        case connection = "Connection"
        case autoResponse = "Auto Mode"
        case appearance = "Appearance"
        case behavior = "Behavior"
        case notifications = "Notifications"
        case privacy = "Privacy"
        case advanced = "Advanced"
        case about = "About"
        
        var icon: String {
            switch self {
            case .connection: return "network"
            case .autoResponse: return "play.circle"
            case .appearance: return "paintbrush"
            case .behavior: return "gearshape"
            case .notifications: return "bell"
            case .privacy: return "lock"
            case .advanced: return "wrench"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isIPad && horizontalSizeClass == .regular {
                    // iPad layout with sidebar
                    iPadLayout
                } else {
                    // iPhone layout with tabs or list
                    iPhoneLayout
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.accentPrimaryEnd)
                }
            }
            .alert("Disconnect from Server?", isPresented: $showingDisconnectConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    performDisconnect()
                }
            } message: {
                Text("This will end your current session. You can reconnect at any time.")
            }
            .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetAllSettings()
                }
            } message: {
                Text("This will reset all settings to their default values. This action cannot be undone.")
            }
        }
        .onAppear {
            loadAutoResponseSettings()
        }
    }
    
    // MARK: - iPad Layout
    private var iPadLayout: some View {
        HSplitView {
            // Sidebar with tabs
            List(SettingsTab.allCases, id: \.self, selection: Binding(
                get: { selectedTab },
                set: { selectedTab = $0 }
            )) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            
            // Content area
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    contentForTab(selectedTab)
                }
                .padding()
                .frame(maxWidth: 800)
            }
            .background(Colors.bgBase(for: colorScheme))
        }
    }
    
    // MARK: - iPhone Layout
    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    contentForTab(tab)
                }
            }
            .padding(.vertical, Spacing.lg)
        }
        .background(Colors.bgBase(for: colorScheme))
    }
    
    // MARK: - Content Sections
    @ViewBuilder
    private func contentForTab(_ tab: SettingsTab) -> some View {
        switch tab {
        case .connection:
            connectionSection
        case .autoResponse:
            autoResponseSection
        case .appearance:
            appearanceSection
        case .behavior:
            behaviorSection
        case .notifications:
            notificationSection
        case .privacy:
            privacySection
        case .advanced:
            advancedSection
        case .about:
            aboutSection
        }
    }
    
    // MARK: - Connection Section
    private var connectionSection: some View {
        SettingsSection(title: "Connection") {
            if let connection = settings.currentConnection {
                // Connection status with live indicator
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                        
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(settings.isConnected ? Color.green : Colors.accentWarning)
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: settings.isConnected)
                            
                            Text(settings.isConnected ? "Connected" : "Connecting...")
                                .font(Typography.font(.body))
                                .foregroundColor(Colors.textPrimary(for: colorScheme))
                        }
                    }
                    
                    Spacer()
                    
                    if !settings.isConnected {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                // Server details
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    DetailRow(label: "Server", value: "\(connection.address):\(connection.port)")
                    DetailRow(label: "Protocol", value: connection.isSecure ? "HTTPS" : "HTTP")
                    if connection.requiresAuth {
                        DetailRow(label: "Authentication", value: "Required ✓")
                    }
                    if let sessionId = settings.currentSessionId {
                        DetailRow(label: "Session", value: String(sessionId.prefix(8)) + "...")
                            .font(Typography.font(.caption))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                // Actions
                VStack(spacing: Spacing.sm) {
                    // Reconnect button
                    if !settings.isConnected {
                        Button(action: reconnect) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Reconnect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(Colors.accentPrimary(for: colorScheme).first?.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Disconnect button with feedback
                    Button(action: {
                        showingDisconnectConfirmation = true
                    }) {
                        HStack {
                            if isDisconnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                            } else if disconnectSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle")
                            }
                            Text(disconnectSuccess ? "Disconnected" : "Disconnect")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .foregroundColor(disconnectSuccess ? .green : .red)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isDisconnecting || disconnectSuccess)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
            } else {
                // Not connected state
                VStack(spacing: Spacing.md) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    
                    Text("Not Connected")
                        .font(Typography.font(.headline))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("Connect to a server to start chatting")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Auto Response Section
    private var autoResponseSection: some View {
        SettingsSection(title: "Auto-Response Mode") {
            // Enable toggle with description
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle(isOn: $autoResponseManager.config.enabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Auto Mode")
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                        Text("Claude will automatically continue working")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                }
                .toggleStyle(NeumorphicToggleStyle())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            if autoResponseManager.config.enabled {
                SettingsDivider()
                
                // Default prompt
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Default Response")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    
                    TextEditor(text: $autoResponseManager.config.defaultPrompt)
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Colors.bgBase(for: colorScheme))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Colors.strokeLight, lineWidth: 1)
                        )
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                // Max iterations
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Max Iterations")
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                        Spacer()
                        Text("\(Int(autoResponseManager.config.maxIterations))")
                            .font(Typography.font(.headline))
                            .foregroundColor(Colors.accentPrimaryEnd)
                    }
                    
                    Slider(value: Binding(
                        get: { Double(autoResponseManager.config.maxIterations) },
                        set: { autoResponseManager.config.maxIterations = Int($0) }
                    ), in: 1...20, step: 1)
                    .accentColor(Colors.accentPrimaryEnd)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                // Stop phrases
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Stop Phrases (comma-separated)")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    
                    TextField("TASK_COMPLETE, FINISHED, STOP", text: $stopPhrasesText)
                        .font(Typography.font(.body))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: stopPhrasesText) { newValue in
                            autoResponseManager.config.stopPhrases = newValue
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                // Safety settings
                VStack(spacing: Spacing.sm) {
                    Toggle("Require Confirmation", isOn: $autoResponseManager.config.requireConfirmation)
                    Toggle("Safe Mode", isOn: $autoResponseManager.config.enableSafeMode)
                    Toggle("Show Notifications", isOn: $autoResponseManager.config.showNotifications)
                }
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                // Auto mode status
                if autoResponseManager.isActive {
                    SettingsDivider()
                    
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Auto Mode Active")
                                .font(Typography.font(.headline))
                                .foregroundColor(Colors.textPrimary(for: colorScheme))
                        }
                        
                        Text("Iteration \(autoResponseManager.currentIteration) of \(autoResponseManager.config.maxIterations)")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                        
                        Button(action: {
                            autoResponseManager.deactivate()
                        }) {
                            Text("Stop Auto Mode")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }
    
    // MARK: - Appearance Section
    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            SettingsPickerRow(
                title: "Theme",
                selection: $settings.theme,
                options: [
                    (Theme.system, "System"),
                    (Theme.light, "Light"),
                    (Theme.dark, "Dark")
                ]
            )
            
            SettingsDivider()
            
            SettingsPickerRow(
                title: "Font Size",
                selection: $settings.fontSize,
                options: [
                    (FontSize.small, "Small"),
                    (FontSize.medium, "Medium"),
                    (FontSize.large, "Large")
                ]
            )
            
            SettingsDivider()
            
            Toggle("Show Markdown Preview", isOn: $settings.showMarkdownPreview)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
        }
    }
    
    // MARK: - Behavior Section
    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            Toggle("Auto-scroll to new messages", isOn: $settings.autoScroll)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle("Show typing indicators", isOn: $settings.showTypingIndicators)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle("Haptic feedback", isOn: $settings.hapticFeedback)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle("Show thinking indicator", isOn: $settings.showThinkingIndicator)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
        }
    }
    
    // MARK: - Notification Section
    private var notificationSection: some View {
        SettingsSection(title: "Notifications") {
            Toggle("Enable Push Notifications", isOn: $settings.enableNotifications)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            
            if settings.enableNotifications {
                SettingsDivider()
                
                Toggle("Sound", isOn: $settings.notificationSound)
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                Toggle("Vibration", isOn: $settings.notificationVibration)
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                Toggle("Show Preview", isOn: $settings.notificationPreview)
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
            }
        }
    }
    
    // MARK: - Privacy Section
    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            Toggle("Store chat history locally", isOn: $settings.storeChatHistory)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

            if settings.storeChatHistory {
                SettingsDivider()
                
                Button(action: {
                    settings.clearChatHistory()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Chat History")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .foregroundColor(.red)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
        }
    }
    
    // MARK: - Advanced Section
    private var advancedSection: some View {
        SettingsSection(title: "Advanced") {
            Toggle("Debug Mode", isOn: $settings.debugMode)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle("Show Network Activity", isOn: $settings.showNetworkActivity)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            // Cache management
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Cache Size")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    Spacer()
                    Text(formatCacheSize())
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Button(action: clearCache) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Cache")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Colors.bgCard(for: colorScheme))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            // Reset all settings
            Button(action: {
                showingResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset All Settings")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .foregroundColor(.red)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        SettingsSection(title: "About") {
            DetailRow(label: "Version", value: getAppVersion())
            
            SettingsDivider()
            
            DetailRow(label: "Build", value: getBuildNumber())
            
            SettingsDivider()
            
            Link(destination: URL(string: "https://github.com/aicli/companion")!) {
                HStack {
                    Text("GitHub Repository")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Link(destination: URL(string: "https://example.com/privacy")!) {
                HStack {
                    Text("Privacy Policy")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    
    // MARK: - Helper Methods
    
    private func performDisconnect() {
        isDisconnecting = true
        disconnectSuccess = false
        
        // Perform disconnection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            settings.clearConnection()
            isDisconnecting = false
            disconnectSuccess = true
            
            // Reset success indicator after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                disconnectSuccess = false
                dismiss()
            }
        }
    }
    
    private func reconnect() {
        settings.reconnect()
    }
    
    private func loadAutoResponseSettings() {
        stopPhrasesText = autoResponseManager.config.stopPhrases.joined(separator: ", ")
    }
    
    private func clearCache() {
        // Clear cache implementation
        settings.clearCache()
    }
    
    private func formatCacheSize() -> String {
        let cacheSize = settings.getCacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(cacheSize))
    }
    
    private func resetAllSettings() {
        settings.resetToDefaults()
        autoResponseManager.resetConfig()
    }
    
    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Supporting Views

@available(iOS 16.0, macOS 13.0, *)
struct DetailRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Text(label)
                .font(Typography.font(.caption))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
            Spacer()
            Text(value)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Enhanced Settings") {
    EnhancedSettingsView()
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}