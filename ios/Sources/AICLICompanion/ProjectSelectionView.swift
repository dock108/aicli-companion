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
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lastSelectionTime: Date = .distantPast
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var persistenceService = MessagePersistenceService.shared
    
    init(selectedProject: Binding<Project?>, isProjectSelected: Binding<Bool>, onDisconnect: (() -> Void)? = nil) {
        self._selectedProject = selectedProject
        self._isProjectSelected = isProjectSelected
        self.onDisconnect = onDisconnect
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
        request.timeoutInterval = 10.0 // Add timeout to prevent hanging
        
        print("Loading projects from: \(url.absoluteString)")
        
        // Add auth token if available
        if let token = settings.authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // Use weak self to prevent retain cycles
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    // Handle specific network errors more gracefully
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorNotConnectedToInternet:
                            self.errorMessage = "No internet connection available"
                        case NSURLErrorTimedOut:
                            self.errorMessage = "Request timed out. Please try again."
                        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                            self.errorMessage = "Cannot connect to server. Please check your connection."
                        case NSURLErrorNetworkConnectionLost:
                            self.errorMessage = "Network connection was lost. Please try again."
                        default:
                            self.errorMessage = "Network error: \(error.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Network error: \(error.localizedDescription)"
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
        
        // Simply select the project - no server notification needed
        selectedProject = project
        print("🟢 ProjectSelection: Selected project '\(project.name)', navigating to chat")
        isProjectSelected = true
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

@available(iOS 17.0, macOS 14.0, *)
struct ProjectRowView: View {
    let project: Project
    let hasSession: Bool
    let sessionMetadata: PersistedSessionMetadata?
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
                // Project icon
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(Colors.accentPrimaryEnd)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Colors.accentPrimaryEnd.opacity(0.1))
                    )
                
                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    
                    if let metadata = sessionMetadata {
                        Text(metadata.formattedLastUsed)
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .lineLimit(1)
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
    .preferredColorScheme(ColorScheme.dark)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Project Row") {
    ProjectRowView(
        project: Project(name: "my-awesome-app", path: "/path/to/project", type: "folder"),
        hasSession: true,
        sessionMetadata: PersistedSessionMetadata(
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
    .preferredColorScheme(ColorScheme.dark)
}
