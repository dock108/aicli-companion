import SwiftUI

// MARK: - Project Models for Server API

struct Project: Identifiable, Codable {
    let id = UUID()
    let name: String
    let path: String
    let type: String
    
    private enum CodingKeys: String, CodingKey {
        case name, path, type
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
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settings: SettingsManager
    
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
                            ProjectRowView(project: project) {
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
                            
                            Text("Starting Claude CLI...")
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
                    if response.success {
                        // Success! Store the selected project and session info
                        selectedProject = project
                        
                        // Pass session info to parent
                        if let onSessionStarted = onSessionStarted {
                            onSessionStarted(response.session)
                        }
                        
                        isProjectSelected = true
                    } else {
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
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
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
                    
                    Text("Tap to start Claude CLI in this project")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .lineLimit(2)
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
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
        project: Project(name: "my-awesome-app", path: "/path/to/project", type: "folder")
    ) {
        print("Project tapped")
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}