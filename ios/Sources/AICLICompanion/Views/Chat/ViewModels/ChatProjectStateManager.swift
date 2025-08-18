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
        print("🏗️ ProjectStateManager: Setting current project to: \(project?.name ?? "nil")")
        currentProject = project
    }
    
    func getOrCreateProjectState(for project: Project) -> ProjectState {
        if let existingState = projectStates[project.path] {
            return existingState
        }
        
        let newState = ProjectState(projectPath: project.path)
        projectStates[project.path] = newState
        print("🏗️ ProjectStateManager: Created new state for project: \(project.name)")
        return newState
    }
    
    func updateProjectState(for project: Project, update: (ProjectState) -> Void) {
        let state = getOrCreateProjectState(for: project)
    func updateProjectState(for project: Project, update: (inout ProjectState) -> Void) {
        if projectStates[project.path] == nil {
            projectStates[project.path] = ProjectState(projectPath: project.path)
            print("🏗️ ProjectStateManager: Created new state for project: \(project.name)")
        }
        update(&projectStates[project.path]!)
        print("🏗️ ProjectStateManager: Updated state for project: \(project.name)")
    }
    
    func clearProjectState(for projectPath: String) {
        projectStates.removeValue(forKey: projectPath)
        print("🏗️ ProjectStateManager: Cleared state for project: \(projectPath)")
    }
    
    // MARK: - State Queries
    
    func isLoadingForProject(_ projectPath: String) -> Bool {
        return projectStates[projectPath]?.isLoading ?? false
    }
    
    func shouldBlockSending(for project: Project) -> Bool {
        let state = projectStates[project.path]
        return state?.isLoading == true || state?.isWaitingForResponse == true
    }
}