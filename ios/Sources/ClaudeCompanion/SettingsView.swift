import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection")) {
                    if let connection = settings.currentConnection {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Server: \(connection.address):\(connection.port)")
                                .font(.body)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        Button("Disconnect") {
                            settings.clearConnection()
                            dismiss()
                        }
                        .foregroundColor(.red)
                    } else {
                        Text("Not connected")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $settings.theme) {
                        Text("System").tag(Theme.system)
                        Text("Light").tag(Theme.light)
                        Text("Dark").tag(Theme.dark)
                    }

                    Picker("Font Size", selection: $settings.fontSize) {
                        Text("Small").tag(FontSize.small)
                        Text("Medium").tag(FontSize.medium)
                        Text("Large").tag(FontSize.large)
                    }
                }

                Section(header: Text("Behavior")) {
                    Toggle("Auto-scroll to new messages", isOn: $settings.autoScroll)
                    Toggle("Show typing indicators", isOn: $settings.showTypingIndicators)
                    Toggle("Haptic feedback", isOn: $settings.hapticFeedback)
                }

                Section(header: Text("Privacy")) {
                    Toggle("Store chat history locally", isOn: $settings.storeChatHistory)

                    if settings.storeChatHistory {
                        Button("Clear Chat History") {
                            settings.clearChatHistory()
                        }
                        .foregroundColor(.red)
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link("Setup Instructions", destination: URL(string: "https://github.com/anthropics/claude-code")!)
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                }
            }
            .navigationTitle("Settings")
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

#Preview {
    SettingsView()
        .environmentObject(SettingsManager())
}
