import SwiftUI
import Combine

// MARK: - Project Models for Server API

struct Project: Identifiable, Codable, Equatable {
    var id: String { path } // Use path as stable identifier
    let name: String
    let path: String
    let type: String
    
    private enum CodingKeys: String, CodingKey {
        case name, path, type
    }
    
    static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.name == rhs.name && lhs.path == rhs.path && lhs.type == rhs.type
    }
}

struct ProjectsResponse: Codable {
    let basePath: String
    let projects: [Project]
}

struct ProjectSession: Codable {
    let sessionId: String
    let projectName: String
    let projectPath: String
    let status: String
    let startedAt: String
}

struct ProjectStartResponse: Codable {
    let success: Bool
    let session: ProjectSession
    let message: String
}

// MARK: - Project Selection View

@available(iOS 14.0, macOS 11.0, *)
struct ProjectSelectionView: View {
    @Binding var selectedProject: Project?
    @Binding var isProjectSelected: Bool
    let onDisconnect: (() -> Void)?
    let onSessionStarted: ((ProjectSession) -> Void)?
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isStartingProject = false
    @State private var showingContinuationSheet = false
    @State private var pendingProject: Project?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var lastSelectionTime: Date = .distantPast
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var persistenceService = MessagePersistenceService.shared
    
    init(selectedProject: Binding<Project?>, isProjectSelected: Binding<Bool>, onDisconnect: (() -> Void)? = nil, onSessionStarted: ((ProjectSession) -> Void)? = nil) {
        self._selectedProject = selectedProject
        self._isProjectSelected = isProjectSelected
        self.onDisconnect = onDisconnect
        self.onSessionStarted = onSessionStarted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            NavigationTopBar(title: "Select Project") {
                Button("Disconnect") {
                    disconnectFromServer()
                }
                .foregroundColor(Colors.accentPrimaryEnd)
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
                    
                    SecondaryButton("Retry") {
                        loadProjects()
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
                        ForEach(projects) { project in
                            ProjectRowView(
                                project: project,
                                hasSession: persistenceService.hasSession(for: project.path),
                                sessionMetadata: persistenceService.getSessionMetadata(for: project.path)
                            ) {
                                selectProject(project)
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.bgBase(for: colorScheme))
        .onAppear {
            loadProjects()
            // No need to observe persistence service changes here as we manually
            // check session state when needed via hasSession() and getSessionMetadata()
        }
        .disabled(isStartingProject)
        .overlay(
            // Loading overlay when starting project
            Group {
                if isStartingProject {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: Spacing.md) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Starting AICLI...")
                                .font(Typography.font(.body))
                                .foregroundColor(.white)
                        }
                        .padding(Spacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.8))
                        )
                    }
                }
            }
        )
        .sheet(isPresented: $showingContinuationSheet, onDismiss: {
            // Clear pending project if sheet is dismissed without action
            if pendingProject != nil {
                print("🔵 ProjectSelection: Continuation sheet dismissed, clearing pending project")
                pendingProject = nil
            }
        }) {
            if let project = pendingProject,
               let metadata = persistenceService.getSessionMetadata(for: project.path) {
                SessionContinuationSheet(
                    project: project,
                    sessionMetadata: metadata,
                    onContinue: {
                        print("🟢 ProjectSelection: Sheet onContinue called for '\(project.name)'")
                        // Dismiss sheet first, then start session after a small delay
                        showingContinuationSheet = false
                        pendingProject = nil // Clear pending project
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            continueExistingSession(project, metadata: metadata)
                        }
                    },
                    onStartFresh: {
                        print("🟢 ProjectSelection: Sheet onStartFresh called for '\(project.name)'")
                        // Dismiss sheet first, then start session after a small delay
                        showingContinuationSheet = false
                        pendingProject = nil // Clear pending project
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            startFreshSession(project)
                        }
                    },
                    onViewHistory: {
                        // TODO: Implement history view
                        print("View history for \(project.name)")
                        showingContinuationSheet = false
                        pendingProject = nil // Clear pending project
                    }
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadProjects() {
        isLoading = true
        errorMessage = nil
        
        guard let serverURL = settings.serverURL else {
            errorMessage = "Server connection not configured"
            isLoading = false
            return
        }
        
        let url = serverURL.appendingPathComponent("api/projects")
        var request = URLRequest(url: url)
        
        print("Loading projects from: \(url.absoluteString)")
        
        // Add auth token if available
        if let token = settings.authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
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
                    projects = response.projects
                    errorMessage = nil  // Clear any previous error
                    print("Successfully loaded \(projects.count) projects")
                } catch let decodingError {
                    print("Decoding error: \(decodingError)")
                    errorMessage = "Failed to parse server response: \(decodingError.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func selectProject(_ project: Project) {
        print("🔵 ProjectSelection: Selecting project '\(project.name)' at path: \(project.path)")
        
        // Debounce rapid selections (500ms)
        let now = Date()
        let timeSinceLastSelection = now.timeIntervalSince(lastSelectionTime)
        if timeSinceLastSelection < 0.5 {
            print("⚠️ ProjectSelection: Ignoring rapid selection for '\(project.name)' (only \(Int(timeSinceLastSelection * 1000))ms since last selection)")
            return
        }
        lastSelectionTime = now
        
        // Check if there's an existing session for this project
        let hasSession = persistenceService.hasSession(for: project.path)
        print("🔵 ProjectSelection: Project '\(project.name)' hasSession: \(hasSession)")
        
        if hasSession {
            if let metadata = persistenceService.getSessionMetadata(for: project.path) {
                print("🔵 ProjectSelection: Session metadata for '\(project.name)':")
                print("   - Session ID: \(metadata.sessionId)")
                print("   - AICLI Session ID: \(metadata.aicliSessionId ?? "nil")")
                print("   - Message Count: \(metadata.messageCount)")
                print("   - Last Used: \(metadata.formattedLastUsed)")
            } else {
                print("⚠️ ProjectSelection: No metadata found for '\(project.name)' despite hasSession = true")
            }
            
            // IMPORTANT: Do not set selectedProject here - only pendingProject
            pendingProject = project
            print("🟢 ProjectSelection: Showing continuation sheet for '\(project.name)'")
            // Ensure UI updates before showing sheet
            DispatchQueue.main.async {
                self.showingContinuationSheet = true
            }
        } else {
            print("🔵 ProjectSelection: Starting fresh session for '\(project.name)'")
            startProjectSession(project, continueExisting: false)
        }
    }
    
    private func startProjectSession(_ project: Project, continueExisting: Bool) {
        isStartingProject = true
        
        guard let serverURL = settings.serverURL else {
            isStartingProject = false
            errorMessage = "Server connection not configured"
            return
        }
        
        let url = serverURL.appendingPathComponent("api/projects/\(project.name)/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth token if available
        if let token = settings.authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add continue session info if applicable
        if continueExisting,
           let metadata = persistenceService.getSessionMetadata(for: project.path),
           let sessionId = metadata.aicliSessionId {
            let body = [
                "continueSession": true,
                "sessionId": sessionId
            ] as [String : Any]
            
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isStartingProject = false
                
                if let error = error {
                    errorMessage = "Failed to start project: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No response from server"
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(ProjectStartResponse.self, from: data)
                    print("🟢 ProjectSelection: Server response for '\(project.name)': success=\(response.success)")
                    
                    if response.success {
                        print("🟢 ProjectSelection: Successfully started session for '\(project.name)'")
                        print("   - Session ID: \(response.session.sessionId)")
                        print("   - Status: \(response.session.status)")
                        
                        // Success! Store the selected project and session info
                        selectedProject = project
                        
                        // Pass session info to parent
                        if let onSessionStarted = onSessionStarted {
                            onSessionStarted(response.session)
                        }
                        
                        print("🟢 ProjectSelection: Transitioning to chat view for '\(project.name)'")
                        // Add a small delay to ensure state propagates properly
                        DispatchQueue.main.async {
                            print("🟢 ProjectSelection: Setting isProjectSelected = true for '\(project.name)'")
                            isProjectSelected = true
                        }
                    } else {
                        print("❌ ProjectSelection: Server failed to start project '\(project.name)': \(response.message)")
                        errorMessage = "Failed to start project: \(response.message)"
                    }
                } catch {
                    // Check if we got an error response
                    if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let serverError = errorResponse["error"] as? String,
                       let serverMessage = errorResponse["message"] as? String {
                        errorMessage = "\(serverError): \(serverMessage)"
                    } else {
                        errorMessage = "Failed to parse server response"
                    }
                }
            }
        }.resume()
    }
    
    private func continueExistingSession(_ project: Project, metadata: SessionMetadata) {
        print("🟢 ProjectSelection: Continuing existing session for '\(project.name)'")
        print("   - Session ID: \(metadata.sessionId)")
        print("   - AICLI Session ID: \(metadata.aicliSessionId ?? "nil")")
        print("   - Project Path: \(project.path)")
        
        // TODO: Add server endpoint to continue with existing session ID
        startProjectSession(project, continueExisting: true)
    }
    
    private func startFreshSession(_ project: Project) {
        // Archive the old session
        persistenceService.archiveCurrentSession(for: project.path)
        // Clear current messages
        persistenceService.clearMessages(for: project.path)
        // Start new session
        startProjectSession(project, continueExisting: false)
    }
    
    private func disconnectFromServer() {
        if let onDisconnect = onDisconnect {
            onDisconnect()
        } else {
            settings.clearConnection()
        }
    }
}

// MARK: - Project Row View

@available(iOS 14.0, macOS 11.0, *)
struct ProjectRowView: View {
    let project: Project
    let hasSession: Bool
    let sessionMetadata: SessionMetadata?
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isProcessing = false
    
    var body: some View {
        Button(action: {
            guard !isProcessing else { return }
            isProcessing = true
            onTap()
            // Reset after a delay to allow for the view transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isProcessing = false
            }
        }) {
            HStack(spacing: Spacing.md) {
                // Project icon with session indicator
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundColor(Colors.accentPrimaryEnd)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Colors.accentPrimaryEnd.opacity(0.1))
                        )
                    
                    // Session indicator dot
                    if hasSession {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Colors.bgCard(for: colorScheme), lineWidth: 2)
                            )
                            .offset(x: 4, y: -4)
                    }
                }
                
                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name)
                            .font(Typography.font(.heading3))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                            .lineLimit(1)
                        
                        if hasSession {
                            Text("• Active")
                                .font(Typography.font(.caption))
                                .foregroundColor(.green)
                        }
                    }
                    
                    if let metadata = sessionMetadata {
                        Text("\(metadata.messageCount) messages • \(metadata.formattedLastUsed)")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .lineLimit(1)
                    } else {
                        Text("Tap to start AICLI in this project")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .lineLimit(2)
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
        .opacity(isProcessing ? 0.6 : 1.0)
        .disabled(isProcessing)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
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
    .preferredColorScheme(.dark)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Project Row") {
    ProjectRowView(
        project: Project(name: "my-awesome-app", path: "/path/to/project", type: "folder"),
        hasSession: true,
        sessionMetadata: SessionMetadata(
            sessionId: "test-session",
            projectId: "my-awesome-app",
            projectName: "my-awesome-app",
            projectPath: "/path/to/project",
            lastMessageDate: Date().addingTimeInterval(-3600),
            messageCount: 42,
            aicliSessionId: "aicli-123",
            createdAt: Date().addingTimeInterval(-86400)
        )
    ) {
        print("Project tapped")
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}