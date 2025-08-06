import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Colors.bgBase(for: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Connection Section
                        SettingsSection(title: "Connection") {
                            if let connection = settings.currentConnection {
                                SettingsTile(
                                    title: "Server",
                                    value: "\(connection.address):\(connection.port)"
                                ) {
                                    EmptyView()
                                }
                                
                                SettingsDivider()
                                
                                SettingsTile(title: "Status") {
                                    HStack(spacing: Spacing.xs) {
                                        Circle()
                                            .fill(Colors.accentWarning)
                                            .frame(width: 8, height: 8)
                                        Text("Connected")
                                            .font(Typography.font(.caption))
                                            .foregroundColor(Colors.accentWarning)
                                    }
                                }
                                
                                SettingsDivider()
                                
                                Button(action: {
                                    settings.clearConnection()
                                    dismiss()
                                }) {
                                    SettingsTile(title: "Disconnect") {
                                        EmptyView()
                                    }
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(PlainButtonStyle())
                            } else {
                                SettingsTile(title: "Status", value: "Not connected") {
                                    EmptyView()
                                }
                            }
                        }

                        // Appearance Section
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

                        // Behavior Section
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
                            
                            Toggle(isOn: $settings.hapticFeedback) {
                                Text("Haptic feedback")
                                    .font(Typography.font(.body))
                                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                            }
                            .toggleStyle(NeumorphicToggleStyle())
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                        }

                        // Privacy Section
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
                        
                        // About Section
                        SettingsSection(title: "About") {
                            SettingsTile(title: "Version", value: "1.0.0") {
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
                            
                            SettingsDivider()
                            
                            Link(destination: URL(string: "https://example.com/privacy")!) {
                                SettingsTile(title: "Privacy Policy") {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            SettingsDivider()
                            
                            Link(destination: URL(string: "https://example.com/terms")!) {
                                SettingsTile(title: "Terms of Service") {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, Spacing.lg)
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
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
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