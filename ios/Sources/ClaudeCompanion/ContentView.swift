import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct ContentView: View {
    public init() {}
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @State private var isConnected = false
    @Environment(\.colorScheme) var colorScheme

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: colorScheme == .dark 
                        ? [Color.black, Color(white: 0.1)]
                        : [Color(red: 0.95, green: 0.95, blue: 0.98), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // NavBar with design system styling
                    HStack(spacing: Spacing.sm) {
                        // Terminal bubble icon
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Colors.brandBlue500)
                            .frame(width: 24, height: 24)
                        
                        Text("Code Companion")
                            .font(Typography.font(.navTitle))
                            .foregroundColor(Colors.adaptivePrimaryText(colorScheme: colorScheme))
                        
                        Spacer()
                        
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 24))
                                .foregroundColor(Colors.adaptiveSecondaryText(colorScheme: colorScheme))
                                .frame(width: 44, height: 44)
                                .background(Colors.surface10)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, Spacing.Component.navBarPadding)
                    .padding(.vertical, Spacing.Component.navBarVerticalPadding)
                    .background(.ultraThinMaterial)
                    
                    // Main content
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
            }
            .navigationBarHidden(true)
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
