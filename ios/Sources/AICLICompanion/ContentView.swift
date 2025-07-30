import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct ContentView: View {
    public init() {}
    @EnvironmentObject var aicliService: AICLIService
    @EnvironmentObject var settings: SettingsManager
    @State private var isConnected = false
    @State private var selectedProject: Project?
    @State private var isProjectSelected = false
    @State private var currentSession: ProjectSession?
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
                    // Main content with three-state flow
                    ZStack {
                        if !isConnected {
                            // Step 1: Connection screen
                            ConnectionView(isConnected: $isConnected)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        } else if !isProjectSelected || selectedProject == nil {
                            // Step 2: Project selection screen
                            ProjectSelectionView(
                                selectedProject: $selectedProject,
                                isProjectSelected: $isProjectSelected,
                                onDisconnect: disconnectFromServer,
                                onSessionStarted: { session in
                                    currentSession = session
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        } else if let project = selectedProject {
                            // Step 3: Chat screen with selected project
                            ChatView(
                                selectedProject: project,
                                session: currentSession,
                                onSwitchProject: switchProject
                            )
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
        .onChange(of: isConnected) { _, connected in
            if !connected {
                // Reset project selection when disconnected
                selectedProject = nil
                isProjectSelected = false
            }
        }
        .onChange(of: isProjectSelected) { _, selected in
            print("🎯 ContentView: isProjectSelected changed to: \(selected)")
            if selected, let project = selectedProject {
                print("🎯 ContentView: Navigation should show ChatView for project: \(project.name)")
            }
        }
        .onChange(of: selectedProject) { _, project in
            if let project = project {
                print("🎯 ContentView: selectedProject changed to: \(project.name)")
            } else {
                print("🎯 ContentView: selectedProject changed to: nil")
            }
        }
    }

    private func checkConnection() {
        // Check if we have saved connection settings
        isConnected = settings.hasValidConnection()
    }
    
    private func disconnectFromServer() {
        settings.clearConnection()
        withAnimation(.easeInOut(duration: 0.3)) {
            isConnected = false
            selectedProject = nil
            isProjectSelected = false
            currentSession = nil
        }
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
            currentSession = nil
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Light Mode") {
    ContentView()
        .environmentObject(AICLIService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.light)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Dark Mode") {
    ContentView()
        .environmentObject(AICLIService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}