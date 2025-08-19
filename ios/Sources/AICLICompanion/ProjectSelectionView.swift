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
    @State private var showingFolderCreation = false
    @State private var selectedProjectForFolder: Project?
    @State private var newFolderName = ""
    @State private var folderCreationError: String?
    
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
                        ForEach(projects) { project in
                            ProjectRowView(
                                project: project,
                                hasSession: hasMessagesCache[project.path] ?? false,
                                onSelect: {
                                    selectProject(project)
                                },
                                onCreateFolder: {
                                    selectedProjectForFolder = project
                                    newFolderName = ""
                                    folderCreationError = nil
                                    showingFolderCreation = true
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
            loadProjects()
        }
        .sheet(isPresented: $showingFolderCreation) {
            FolderCreationSheet(
                project: selectedProjectForFolder,
                folderName: $newFolderName,
                errorMessage: $folderCreationError,
                isPresented: $showingFolderCreation,
                onCreateFolder: createFolder
            )
        }
    }
    
    // MARK: - Private Methods
    
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
            DispatchQueue.main.async {
                loadingStateCoordinator.stopLoading(.projectSelection)
                
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
                    projects = response.projects
                    errorMessage = nil  // Clear any previous error
                    print("Successfully loaded \(projects.count) projects")
                    
                    // Check which projects have messages
                    hasMessagesCache.removeAll()
                    for project in projects {
                        let messages = persistenceService.loadMessages(for: project.path)
                        hasMessagesCache[project.path] = !messages.isEmpty
                        if !messages.isEmpty {
                            print("📊 Found \(messages.count) messages for \(project.name)")
                        } else {
                            print("📊 No messages found for \(project.name)")
                        }
                    }
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
    
    private func createFolder() {
        guard let project = selectedProjectForFolder,
              !newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            folderCreationError = "Please enter a folder name"
            return
        }
        
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use the shared AICLIService which already has connection setup
        aicliService.createFolder(in: project.name, folderName: trimmedName) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("✅ Successfully created folder: \(response.folder.name)")
                    showingFolderCreation = false
                    // Optionally reload projects to show the new folder
                    loadProjects()
                case .failure(let error):
                    folderCreationError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Project Row View

@available(iOS 17.0, macOS 14.0, *)
struct ProjectRowView: View {
    let project: Project
    let hasSession: Bool
    let onSelect: () -> Void
    let onCreateFolder: () -> Void
    
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
                        
                        // Commented out - New badges not working correctly for beta
                        /*
                        if hasUnreadMessages {
                            Text("New")
                                .font(Typography.font(.caption))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.blue)
                                )
                        }
                        */
                    }
                    
                    // Commented out - Countdown timers not working correctly for beta
                    /*
                    // Show time remaining instead of path
                    if !timeRemaining.isEmpty {
                        Text(timeRemaining)
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .lineLimit(1)
                    }
                    */
                }
                
                Spacer()
                
                // Folder button
                Button(action: onCreateFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(Colors.accentPrimaryEnd)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Colors.accentPrimaryEnd.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, Spacing.sm)
                
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

// MARK: - Folder Creation Sheet

@available(iOS 17.0, macOS 14.0, *)
struct FolderCreationSheet: View {
    let project: Project?
    @Binding var folderName: String
    @Binding var errorMessage: String?
    @Binding var isPresented: Bool
    let onCreateFolder: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.lg) {
                // Project info
                if let project = project {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .foregroundColor(Colors.accentPrimaryEnd)
                        
                        VStack(alignment: .leading) {
                            Text("Creating folder in:")
                                .font(Typography.font(.caption))
                                .foregroundColor(Colors.textSecondary(for: colorScheme))
                            Text(project.name)
                                .font(Typography.font(.body))
                                .foregroundColor(Colors.textPrimary(for: colorScheme))
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Colors.bgCard(for: colorScheme))
                    )
                }
                
                // Folder name input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Folder Name")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    
                    TextField("Enter folder name", text: $folderName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Colors.bgCard(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(errorMessage != nil ? Colors.accentDanger : Colors.strokeLight, lineWidth: 1)
                        )
                        .focused($isFocused)
                }
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(Colors.accentDanger)
                        Text(error)
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.accentDanger)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Colors.accentDanger.opacity(0.1))
                    )
                }
                
                Spacer()
            }
            .padding()
            .background(Colors.bgBase(for: colorScheme))
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onCreateFolder()
                    }
                    .foregroundColor(Colors.accentPrimaryEnd)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            isFocused = true
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
    ProjectRowView(
        project: Project(name: "my-awesome-app", path: "/path/to/project", type: "folder"),
        hasSession: true,
        onSelect: {
            print("Project selected")
        },
        onCreateFolder: {
            print("Create folder tapped")
        }
    )
    .padding()
    .background(Color.black)
    .preferredColorScheme(ColorScheme.dark)
}
