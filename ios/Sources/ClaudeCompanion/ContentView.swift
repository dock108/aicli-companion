import SwiftUI

public struct ContentView: View {
    public init() {}
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @State private var isConnected = false

    public var body: some View {
        NavigationStack {
            Group {
                if isConnected {
                    ChatView()
                } else {
                    ConnectionView(isConnected: $isConnected)
                }
            }
            .navigationTitle("Claude Companion")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .onAppear {
            checkConnection()
        }
    }

    private func checkConnection() {
        // Check if we have saved connection settings
        isConnected = settings.hasValidConnection()
    }
}

#Preview {
    ContentView()
        .environmentObject(ClaudeCodeService())
        .environmentObject(SettingsManager())
}
