import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct ContentView: View {
    public init() {}
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @State private var isConnected = false
    @State private var backgroundOpacity: Double = 0
    @Environment(\.colorScheme) var colorScheme

    public var body: some View {
        NavigationStack {
            ZStack {
                // Pure background color with fade animation
                Colors.bgBase(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
                
                VStack(spacing: 0) {
                    // New TopBar component
                    NavigationTopBar(title: "Code Companion") {
                        SettingsView()
                    }
                    
                    // Main content with transitions
                    ZStack {
                        if isConnected {
                            ChatView()
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        } else {
                            ConnectionView(isConnected: $isConnected)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
        .onAppear {
            checkConnection()
            animateBackground()
        }
    }

    private func checkConnection() {
        // Check if we have saved connection settings
        isConnected = settings.hasValidConnection()
    }
    
    private func animateBackground() {
        // Fade in background from black
        withAnimation(.easeInOut(duration: 0.24)) {
            backgroundOpacity = 1.0
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Light Mode") {
    ContentView()
        .environmentObject(ClaudeCodeService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.light)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Dark Mode") {
    ContentView()
        .environmentObject(ClaudeCodeService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}