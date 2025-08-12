import SwiftUI

// MARK: - Enhanced Settings View (Main Implementation)

@available(iOS 16.0, macOS 13.0, *)
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var autoResponseManager = AutoResponseManager.shared
    @StateObject private var httpService = HTTPAICLIService.shared
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
        case security = "Security"
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
            case .security: return "shield"
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
                    // iPhone layout with sections
                    iPhoneLayout
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        HStack(spacing: 0) {
            // Sidebar with tabs
            List {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .foregroundColor(selectedTab == tab ? Colors.accentPrimaryEnd : Colors.textPrimary(for: colorScheme))
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(
                        selectedTab == tab ?
                        Colors.accentPrimary(for: colorScheme).first?.opacity(0.1) :
                        Color.clear
                    )
                }
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
        case .security:
            SecuritySettingsView()
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
                                .fill(httpService.isConnected ? Color.green : Colors.accentWarning)
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: httpService.isConnected)
                            
                            Text(httpService.isConnected ? "Connected" : "Connecting...")
                                .font(Typography.font(.body))
                                .foregroundColor(Colors.textPrimary(for: colorScheme))
                        }
                    }
                    
                    Spacer()
                    
                    if !httpService.isConnected {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                
                SettingsDivider()
                
                // Server details
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsTile(title: "Server", value: "\(connection.address):\(connection.port)") {
                        EmptyView()
                    }
                    SettingsDivider()
                    SettingsTile(title: "Protocol", value: connection.isSecure ? "HTTPS" : "HTTP") {
                        EmptyView()
                    }
                    if connection.authToken != nil && !connection.authToken!.isEmpty {
                        SettingsDivider()
                        SettingsTile(title: "Authentication", value: "Required ✓") {
                            EmptyView()
                        }
                    }
                    if let sessionId = settings.currentSessionId {
                        SettingsDivider()
                        SettingsTile(title: "Session", value: String(sessionId.prefix(8)) + "...") {
                            EmptyView()
                        }
                    }
                }
                
                SettingsDivider()
                
                // Actions
                VStack(spacing: Spacing.sm) {
                    // Reconnect button
                    if !httpService.isConnected {
                        Button(action: { reconnect() }) {
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
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("Connect to a server to start chatting")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                    
                    // Setup Connection button
                    Button(action: {
                        // Dismiss settings and navigate to ConnectionView
                        dismiss()
                        // Clear the connection to trigger showing ConnectionView
                        settings.clearConnection()
                    }) {
                        HStack {
                            Image(systemName: "qrcode")
                            Text("Setup Connection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Colors.accentPrimary(for: colorScheme).first?.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.vertical, Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // Use existing sections from the original SettingsView but simplified
    private var autoResponseSection: some View {
        SettingsSection(title: "Auto-Response Mode") {
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
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    
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
        }
    }
    
    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            Toggle(isOn: $settings.autoScroll) {
                Text("Auto-scroll to new messages")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle(isOn: $settings.showTypingIndicators) {
                Text("Show typing indicators")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle(isOn: $settings.showThinkingIndicator) {
                Text("Show thinking indicator")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    
    private var notificationSection: some View {
        SettingsSection(title: "Notifications") {
            Toggle(isOn: $settings.enableNotifications) {
                Text("Enable Push Notifications")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    
    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            Toggle(isOn: $settings.storeChatHistory) {
                Text("Store chat history locally")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            if settings.storeChatHistory {
                SettingsDivider()
                
                Button(action: {
                    settings.clearChatHistory()
                }) {
                    SettingsTile(title: "Clear Chat History") {
                        EmptyView()
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var advancedSection: some View {
        SettingsSection(title: "Advanced") {
            Toggle(isOn: $settings.debugMode) {
                Text("Debug Mode")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Button(action: {
                showingResetConfirmation = true
            }) {
                SettingsTile(title: "Reset All Settings") {
                    EmptyView()
                }
                .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsTile(title: "Version", value: getAppVersion()) {
                EmptyView()
            }
            
            SettingsDivider()
            
            Link(destination: URL(string: "https://github.com/aicli/aicli")!) {
                SettingsTile(title: "Setup Instructions") {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Helper Methods
    
    private func performDisconnect() {
        isDisconnecting = true
        disconnectSuccess = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Disconnect the HTTP service first
            httpService.disconnect()
            // Then clear the connection settings
            settings.clearConnection()
            isDisconnecting = false
            disconnectSuccess = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                disconnectSuccess = false
                dismiss()
            }
        }
    }
    
    private func loadAutoResponseSettings() {
        stopPhrasesText = autoResponseManager.config.stopPhrases.joined(separator: ", ")
    }
    
    private func resetAllSettings() {
        settings.resetToDefaults()
        autoResponseManager.resetConfig()
    }
    
    private func reconnect() {
        // Disconnect first
        httpService.disconnect()
        
        // Try to reconnect using saved settings
        if let connection = settings.currentConnection {
            httpService.connect(
                to: connection.address,
                port: connection.port,
                authToken: connection.authToken
            ) { result in
                switch result {
                case .success:
                    print("✅ Reconnected successfully")
                case .failure(let error):
                    print("❌ Reconnection failed: \(error)")
                }
            }
        }
    }
    
    private func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Settings - Light") {
    SettingsView()
        .environmentObject(SettingsManager())
        .preferredColorScheme(.light)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Settings - Dark") {
    SettingsView()
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}
