import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct AdaptiveContentView: View {
    public init() {}
    @EnvironmentObject var aicliService: AICLIService
    @EnvironmentObject var settings: SettingsManager
    @State private var isConnected = false
    @State private var selectedProject: Project?
    @State private var isProjectSelected = false
    @State private var currentSession: ProjectSession?
    @State private var backgroundOpacity: Double = 0
    @State private var navigationSplitViewVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showSettings = false
    @State private var isInteractionEnabled = true
    @State private var appBecameActiveTime: Date = .distantPast
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) var scenePhase
    
    private var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
    
    public var body: some View {
        Group {
            if isIPad && horizontalSizeClass == .regular {
                // iPad layout with NavigationSplitView
                iPadLayout
            } else {
                // iPhone/compact layout with NavigationStack
                iPhoneLayout
            }
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
        .handleNotifications()
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                print("🌟 App became active")
                appBecameActiveTime = Date()
                // Briefly disable interactions to prevent double-taps during app activation
                isInteractionEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isInteractionEnabled = true
                    print("🌟 Interactions re-enabled after app activation")
                }
            case .inactive:
                print("🌙 App became inactive")
            case .background:
                print("🌙 App entered background")
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - iPad Layout with NavigationSplitView
    @ViewBuilder
    private var iPadLayout: some View {
        NavigationSplitView(
            columnVisibility: $navigationSplitViewVisibility
        ) {
            // Sidebar: Project list and settings
            ZStack {
                Colors.bgBase(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
                
                if !isConnected {
                    // Connection setup in sidebar
                    ConnectionView(isConnected: $isConnected)
                        .navigationTitle("Connect to Server")
                } else {
                    // Project list in sidebar
                    ProjectSelectionView(
                        selectedProject: $selectedProject,
                        isProjectSelected: $isProjectSelected,
                        onDisconnect: disconnectFromServer
                    )
                    .allowsHitTesting(isInteractionEnabled)
                    .navigationTitle("Projects")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gear")
                                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 450)
        } detail: {
            // Detail: Chat view or placeholder
            ZStack {
                Colors.bgBase(for: colorScheme)
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
                
                if let project = selectedProject, isProjectSelected {
                    ChatView(
                        selectedProject: project,
                        session: currentSession,
                        onSwitchProject: switchProject
                    )
                } else {
                    // Placeholder when no project is selected
                    VStack(spacing: 24) {
                        Image(systemName: "message.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: Colors.accentPrimary(for: colorScheme),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Select a Project")
                            .font(Typography.font(.heading2))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                        
                        Text("Choose a project from the sidebar to start chatting with AICLI")
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    // MARK: - iPhone Layout with NavigationStack
    @ViewBuilder
    private var iPhoneLayout: some View {
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
                                onDisconnect: disconnectFromServer
                            )
                            .allowsHitTesting(isInteractionEnabled)
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
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }
    
    // MARK: - Helper Methods
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
#Preview("iPad Light") {
    AdaptiveContentView()
        .environmentObject(AICLIService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.light)
        .previewDevice(PreviewDevice(rawValue: "iPad Pro (12.9-inch) (6th generation)"))
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("iPad Dark") {
    AdaptiveContentView()
        .environmentObject(AICLIService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
        .previewDevice(PreviewDevice(rawValue: "iPad Pro (12.9-inch) (6th generation)"))
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("iPhone Light") {
    AdaptiveContentView()
        .environmentObject(AICLIService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.light)
        .previewDevice(PreviewDevice(rawValue: "iPhone 15 Pro"))
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("iPhone Dark") {
    AdaptiveContentView()
        .environmentObject(AICLIService())
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
        .previewDevice(PreviewDevice(rawValue: "iPhone 15 Pro"))
}
