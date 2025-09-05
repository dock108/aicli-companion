import SwiftUI
import Combine

// MARK: - Project Models for Server API

public struct Project: Identifiable, Codable, Equatable {
    public var id: String { path } // Use path as stable identifier
    public let name: String
    public let path: String
    public let type: String
    
    public init(name: String, path: String, type: String) {
        self.name = name
        self.path = path
        self.type = type
    }
    
    private enum CodingKeys: String, CodingKey {
        case name, path, type
    }
    
    public static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.name == rhs.name && lhs.path == rhs.path && lhs.type == rhs.type
    }
}

struct ProjectsResponse: Codable {
    let basePath: String
    let projects: [Project]
}

// MARK: - Local Session Models

/// Minimal local session representation for iOS state management only
/// No longer tied to server session creation - just tracks local state
struct ProjectSession: Codable {
    let sessionId: String
    let projectName: String
    let projectPath: String
    let status: String
    let startedAt: String
}


// MARK: - Project Selection View

@available(iOS 17.0, macOS 14.0, *)
struct ProjectSelectionView: View {
    @Binding var selectedProject: Project?
    @Binding var isProjectSelected: Bool
    let onDisconnect: (() -> Void)?
    @State private var projects: [Project] = []
    @StateObject private var loadingStateCoordinator = LoadingStateCoordinator.shared
    
    private var isLoading: Bool {
        loadingStateCoordinator.isLoading(.projectSelection)
    }
    @State private var errorMessage: String?
    @State private var lastSelectionTime: Date = .distantPast
    @State private var hasMessagesCache: [String: Bool] = [:]
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var persistenceService = MessagePersistenceService.shared
    @StateObject private var aicliService = AICLIService.shared
    @ObservedObject private var statusManager = ProjectStatusManager.shared
    @StateObject private var webSocketManager = WebSocketManager()
    
    init(selectedProject: Binding<Project?>, isProjectSelected: Binding<Bool>, onDisconnect: (() -> Void)? = nil) {
        self._selectedProject = selectedProject
        self._isProjectSelected = isProjectSelected
        self.onDisconnect = onDisconnect
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            NavigationTopBar(title: "Select Project") {
                SettingsView()
            }
            
            if isLoading {
                // Loading state
                VStack(spacing: Spacing.lg) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Colors.accentPrimaryEnd))
                        .scaleEffect(1.2)
                    
                    Text("Loading projects...")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                // Error state
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(Colors.accentDanger)
                    
                    Text("Error Loading Projects")
                        .font(Typography.font(.heading2))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text(errorMessage)
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Show different buttons based on error type
                    if errorMessage.contains("not configured") || errorMessage.contains("No server") {
                        PrimaryButton("Setup Connection") {
                            // Trigger navigation back to ConnectionView
                            settings.clearConnection()
                            if let onDisconnect = onDisconnect {
                                onDisconnect()
                            }
                        }
                    } else {
                        SecondaryButton("Retry") {
                            loadProjects()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.isEmpty {
                // Empty state
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    
                    Text("No Projects Found")
                        .font(Typography.font(.heading2))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("No project folders were found in the configured directory.")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    SecondaryButton("Refresh") {
                        loadProjects()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Projects list
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        // Add Workspace Mode option at the top
                        Button(action: {
                            selectWorkspaceMode()
                        }) {
                            HStack(spacing: Spacing.md) {
                                // Workspace icon
                                ZStack {
                                    Image(systemName: "folder.badge.gearshape")
                                        .font(.title2)
                                        .foregroundColor(Color.purple)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            Circle()
                                                .fill(Color.purple.opacity(0.1))
                                        )
                                }
                                
                                // Workspace info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Workspace Mode")
                                        .font(Typography.font(.heading3))
                                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                                    
                                    Text("Operate across all projects")
                                        .font(Typography.font(.caption))
                                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                                }
                                
                                Spacer()
                                
                                // Chevron
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                            }
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Colors.bgCard(for: colorScheme))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.bottom, Spacing.sm)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Colors.strokeLight)
                                .frame(height: 1)
                            Text("Projects")
                                .font(Typography.font(.caption))
                                .foregroundColor(Colors.textSecondary(for: colorScheme))
                                .padding(.horizontal, Spacing.sm)
                            Rectangle()
                                .fill(Colors.strokeLight)
                                .frame(height: 1)
                        }
                        .padding(.vertical, Spacing.sm)
                        
                        // Regular projects
                        ForEach(projects) { project in
                            ProjectRowView(
                                project: project,
                                hasSession: false, // Don't check messages upfront for performance
                                status: statusManager.statusFor(project),
                                onSelect: {
                                    selectProject(project)
                                }
                            )
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.bgBase(for: colorScheme))
        .onAppear {
            // Load projects asynchronously to prevent UI freeze
            Task {
                await loadProjectsAsync()
            }
            connectWebSocket()
        }
        // Monitor when settings view disappears to check for connection changes
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SettingsViewDismissed"))) { _ in
            // Check if connection was cleared
            if settings.currentConnection == nil {
                // Connection was cleared - reset projects list
                Task { @MainActor in
                    projects = []
                    errorMessage = nil
                    hasMessagesCache.removeAll()
                    loadingStateCoordinator.stopLoading(.projectSelection)
                }
            } else if projects.isEmpty {
                // Connection exists but no projects - reload
                Task {
                    await loadProjectsAsync()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectMessagesCleared)) { notification in
            guard let projectPath = notification.userInfo?["projectPath"] as? String else { return }
            
            // Update the hasMessagesCache asynchronously to avoid publishing changes warning
            Task {
                let persistenceService = MessagePersistenceService.shared
                let messages = persistenceService.loadMessages(for: projectPath)
                await MainActor.run {
                    hasMessagesCache[projectPath] = !messages.isEmpty
                    print("📊 Updated hasMessagesCache: project \(projectPath) has \(messages.count) messages, indicator: \(hasMessagesCache[projectPath] ?? false)")
                }
            }
        }
        .onDisappear {
            webSocketManager.disconnect()
        }
    }
    
    // MARK: - Private Methods
    
    private func checkProjectHasMessages(_ projectPath: String) async -> Bool {
        // Load messages on background queue to avoid blocking UI
        return await Task.detached {
            let messages = MessagePersistenceService.shared.loadMessages(for: projectPath)
            let hasMessages = !messages.isEmpty
            if hasMessages {
                print("📊 Found \(messages.count) messages for project")
            }
            return hasMessages
        }.value
    }
    
    private func loadProjectsAsync() async {
        // Show loading state immediately
        await MainActor.run {
            loadingStateCoordinator.startLoading(.projectSelection, timeout: 10.0)
            errorMessage = nil
        }
        
        // Small delay to let UI update
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        // Load projects
        await MainActor.run {
            loadProjects()
        }
    }
    
    private func loadProjects() {
        loadingStateCoordinator.startLoading(.projectSelection, timeout: 10.0)
        errorMessage = nil
        
        guard let serverURL = settings.serverURL else {
            errorMessage = "Server connection not configured"
            loadingStateCoordinator.stopLoading(.projectSelection)
            return
        }
        
        let url = serverURL.appendingPathComponent("api/projects")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0 // Add timeout to prevent hanging
        
        print("Loading projects from: \(url.absoluteString)")
        
        // Add auth token if available
        if let token = settings.authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // First stop loading on main thread
            Task { @MainActor in
                loadingStateCoordinator.stopLoading(.projectSelection)
            }
            
            DispatchQueue.main.async {
                if let error = error {
                    // Handle specific network errors more gracefully
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorNotConnectedToInternet:
                            errorMessage = "No internet connection available"
                        case NSURLErrorTimedOut:
                            errorMessage = "Request timed out. Please try again."
                        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                            errorMessage = "Cannot connect to server. Please check your connection."
                        case NSURLErrorNetworkConnectionLost:
                            errorMessage = "Network connection was lost. Please try again."
                        default:
                            errorMessage = "Network error: \(error.localizedDescription)"
                        }
                    } else {
                        errorMessage = "Network error: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No data received from server"
                    return
                }
                
                // Log raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw server response: \(responseString)")
                }
                
                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode != 200 {
                        // Try to parse error response
                        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = errorDict["error"] as? String {
                            errorMessage = "Server error: \(error)"
                            return
                        }
                        errorMessage = "Server returned error: \(httpResponse.statusCode)"
                        return
                    }
                }
                
                do {
                    let response = try JSONDecoder().decode(ProjectsResponse.self, from: data)
                    
                    // Update state on main thread to avoid publishing changes warning
                    Task { @MainActor in
                        projects = response.projects
                        errorMessage = nil  // Clear any previous error
                        print("Successfully loaded \(projects.count) projects")
                        
                        // Don't check messages upfront - too expensive
                        // Message indicators will be loaded lazily if needed
                        hasMessagesCache.removeAll()
                    }
                } catch let decodingError {
                    print("Decoding error: \(decodingError)")
                    Task { @MainActor in
                        errorMessage = "Failed to parse server response: \(decodingError.localizedDescription)"
                    }
                }
            }
        }.resume()
    }
    
    private func selectProject(_ project: Project) {
        print("🔵 ProjectSelection: Selecting project '\(project.name)' at path: \(project.path)")
        
        // Reduce debounce to 100ms to prevent accidental double-clicks only
        let now = Date()
        let timeSinceLastSelection = now.timeIntervalSince(lastSelectionTime)
        if timeSinceLastSelection < 0.1 {
            print("⚠️ ProjectSelection: Ignoring rapid selection for '\(project.name)' (only \(Int(timeSinceLastSelection * 1000))ms since last selection)")
            return
        }
        lastSelectionTime = now
        
        // Set both values atomically to avoid race conditions
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedProject = project
            isProjectSelected = true
        }
        print("🟢 ProjectSelection: Selected project '\(project.name)', navigating to chat")
    }
    
    private func selectWorkspaceMode() {
        print("🔵 ProjectSelection: Entering Workspace Mode")
        
        // Create a special workspace project
        let workspaceProject = Project(
            name: "Workspace Mode",
            path: "__workspace__",
            type: "workspace"
        )
        
        // Set both values atomically to avoid race conditions
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedProject = workspaceProject
            isProjectSelected = true
        }
        print("🟢 ProjectSelection: Workspace mode selected, navigating to chat")
    }
    
    private func disconnectFromServer() {
        if let onDisconnect = onDisconnect {
            onDisconnect()
        } else {
            settings.clearConnection()
        }
    }
    
    private func connectWebSocket() {
        guard let serverURL = settings.serverURL else { return }
        
        let wsURL = serverURL.absoluteString
        webSocketManager.connect(to: wsURL, token: settings.authToken)
    }
}

// MARK: - Project Row View

@available(iOS 17.0, macOS 14.0, *)
struct ProjectRowView: View {
    let project: Project
    let hasSession: Bool
    @ObservedObject var status: Project.StatusInfo
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isProcessing = false
    @StateObject private var persistenceService = MessagePersistenceService.shared
    @State private var timeRemaining: String = ""
    @State private var hasUnreadMessages: Bool = false
    @State private var timer: Timer?
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                guard !isProcessing else { return }
                
                // Brief visual feedback
                withAnimation(.easeInOut(duration: 0.1)) {
                    isProcessing = true
                }
                
                onSelect()
                
                // Reset immediately after the action
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isProcessing = false
                    }
                }
            }) {
                HStack(spacing: Spacing.md) {
                // Project icon with unread indicator
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundColor(Colors.accentPrimaryEnd)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Colors.accentPrimaryEnd.opacity(0.1))
                        )
                    
                    // Commented out - Unread indicator not working correctly for beta
                    /*
                    // Unread indicator dot
                    if hasUnreadMessages {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .offset(x: 5, y: -5)
                    }
                    */
                }
                
                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name)
                            .font(Typography.font(.heading3))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                            .lineLimit(1)
                        
                        // Processing indicators moved to chat thread as typing bubbles
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Colors.bgCard(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(hasSession ? Color.green.opacity(0.3) : Colors.strokeLight, lineWidth: 1)
                    )
            )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .opacity(isProcessing ? 0.6 : 1.0)
        .disabled(isProcessing)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
        // Commented out - Timer functionality not working correctly for beta
        /*
        .onAppear {
            updateTimeRemaining()
            checkUnreadMessages()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        */
    }
    
    private func updateTimeRemaining() {
        let messages = persistenceService.loadMessages(for: project.path)
        guard let lastMessage = messages.last else {
            timeRemaining = ""
            return
        }
        
        let lastMessageDate = lastMessage.timestamp
        let resetDate = lastMessageDate.addingTimeInterval(24 * 60 * 60) // 24 hours
        let now = Date()
        
        if now >= resetDate {
            timeRemaining = "Session expired"
        } else {
            let remaining = resetDate.timeIntervalSince(now)
            timeRemaining = formatTimeRemaining(remaining)
        }
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m until reset"
        } else if minutes > 0 {
            return "\(minutes)m until reset"
        } else {
            return "Less than 1m until reset"
        }
    }
    
    private func checkUnreadMessages() {
        // Check if there are unread messages
        // For now, we'll check if the last message is from assistant and was recent
        let messages = persistenceService.loadMessages(for: project.path)
        if let lastMessage = messages.last,
           lastMessage.sender == .assistant {
            // Consider it unread if it's less than 5 minutes old
            let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
            hasUnreadMessages = lastMessage.timestamp > fiveMinutesAgo
        } else {
            hasUnreadMessages = false
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Project Selection") {
    ProjectSelectionView(
        selectedProject: .constant(nil),
        isProjectSelected: .constant(false)
    )
    .environmentObject(SettingsManager())
    .preferredColorScheme(ColorScheme.dark)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Project Row") {
    let status = Project.StatusInfo()
    status.isProcessing = true
    status.lastActivity = "Using Edit tool"
    status.elapsedSeconds = 45
    
    return ProjectRowView(
        project: Project(name: "my-awesome-app", path: "/path/to/project", type: "folder"),
        hasSession: true,
        status: status,
        onSelect: {
            print("Project selected")
        }
    )
    .padding()
    .background(Color.black)
    .preferredColorScheme(ColorScheme.dark)
}
