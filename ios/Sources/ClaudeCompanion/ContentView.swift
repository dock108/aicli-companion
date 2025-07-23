import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
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

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    ContentView()
        .environmentObject(ClaudeCodeService())
        .environmentObject(SettingsManager())
}
