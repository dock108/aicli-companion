import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct ContentView: View {
    public init() {}
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @State private var isConnected = false
    @State private var selectedProject: Project?
    @State private var isProjectSelected = false
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
                    // Dynamic TopBar title based on current screen
                    NavigationTopBar(title: currentScreenTitle) {
                        SettingsView()
                    }
                    
                    // Main content with three-state flow
                    ZStack {
                        if !isConnected {
                            // Step 1: Connection screen
                            ConnectionView(isConnected: $isConnected)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        } else if !isProjectSelected {
                            // Step 2: Project selection screen
                            ProjectSelectionView(
                                selectedProject: $selectedProject,
                                isProjectSelected: $isProjectSelected
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        } else {
                            // Step 3: Chat screen with selected project
                            ChatView(selectedProject: selectedProject, onSwitchProject: switchProject)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
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
        .onChange(of: isConnected) { connected in
            if !connected {
                // Reset project selection when disconnected
                selectedProject = nil
                isProjectSelected = false
            }
        }
    }
    
    private var currentScreenTitle: String {
        if !isConnected {
            return "Code Companion"
        } else if !isProjectSelected {
            return "Select Project"
        } else {
            return selectedProject?.name ?? "Code Companion"
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
    
    private func switchProject() {
        // Reset to project selection screen
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedProject = nil
            isProjectSelected = false
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