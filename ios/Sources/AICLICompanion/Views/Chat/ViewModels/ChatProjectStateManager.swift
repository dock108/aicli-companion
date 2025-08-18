import SwiftUI
import Combine

/// Simple project state for tracking per-project information
struct ProjectState {
    var isLoading: Bool = false
    var isWaitingForResponse: Bool = false
    var progressInfo: ProgressInfo?
    var messageQueue: [String] = []
    var persistentThinkingInfo: String?
    var messageTimeout: Timer?
    
    init(projectPath: String) {
        // Initialize with project-specific defaults
    }
    
    mutating func cancelTimers() {
        messageTimeout?.invalidate()
        messageTimeout = nil
    }
}

/// Manages project-specific state and context
@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatProjectStateManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentProject: Project?
    @Published var projectStates: [String: ProjectState] = [:]
    
    // MARK: - Project Operations
    
    func setCurrentProject(_ project: Project?) {
        currentProject = project
        
        // Ensure state exists for new project
        if let project = project, projectStates[project.path] == nil {
            projectStates[project.path] = ProjectState(projectPath: project.path)
        }
    }
    
    func updateProjectState(for path: String, update: (inout ProjectState) -> Void) {
        if projectStates[path] == nil {
            projectStates[path] = ProjectState(projectPath: path)
        }
        
        if var state = projectStates[path] {
            update(&state)
            projectStates[path] = state
        }
    }
    
    func clearAllProjects() {
        // Cancel any active timers
        for (_, var state) in projectStates {
            state.cancelTimers()
        }
        
        projectStates.removeAll()
        currentProject = nil
    }
    
    // MARK: - Convenience Getters
    
    var currentProjectState: ProjectState? {
        guard let project = currentProject else { return nil }
        return projectStates[project.path]
    }
    
    func state(for project: Project) -> ProjectState? {
        return projectStates[project.path]
    }
    
    func shouldBlockSending(for project: Project) -> Bool {
        let state = projectStates[project.path]
        return state?.isLoading == true || state?.isWaitingForResponse == true
    }
}
