import Foundation
import Combine

/// Unified project state management - single source of truth for current project
/// Eliminates duplication between currentProject, selectedProject, currentActiveProject
@available(iOS 16.0, macOS 13.0, *)
public class ProjectStateManager: ObservableObject {
    // MARK: - Singleton
    public static let shared = ProjectStateManager()
    
    // MARK: - Published State
    @Published public private(set) var currentProject: Project?
    
    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupDebugLogging()
    }
    
    // MARK: - Public API
    
    /// Set the current project - all services will be notified
    public func setCurrentProject(_ project: Project?) {
        guard currentProject?.path != project?.path else { return }
        
        let oldProject = currentProject
        currentProject = project
        
        if let project = project {
            print("🎯 ProjectStateManager: Setting current project to \(project.name) (\(project.path))")
        } else {
            print("🎯 ProjectStateManager: Clearing current project")
        }
        
        // Notify all subscribers immediately
        objectWillChange.send()
        
        // Log the change for debugging
        logProjectChange(from: oldProject, to: project)
    }
    
    /// Check if a specific project is currently active
    public func isProjectActive(_ project: Project) -> Bool {
        return currentProject?.path == project.path
    }
    
    /// Check if any project is currently active
    public var hasActiveProject: Bool {
        return currentProject != nil
    }
    
    /// Get current project path (convenience)
    public var currentProjectPath: String? {
        return currentProject?.path
    }
    
    /// Get current project name (convenience)
    public var currentProjectName: String? {
        return currentProject?.name
    }
    
    // MARK: - Conversion Utilities
    
    /// Convert Project to ProjectContext
    internal func projectContext(for project: Project) -> ProjectContext? {
        // Create a minimal ProjectContext from Project
        return ProjectContext(
            type: .unknown,
            language: nil,
            framework: nil,
            buildSystem: nil,
            packageManager: nil,
            configFiles: [],
            suggestions: [],
            workingDirectory: project.path,
            detectedFiles: []
        )
    }
    
    // MARK: - Debug Support
    
    private func setupDebugLogging() {
        $currentProject
            .sink { project in
                if let project = project {
                    print("📍 ProjectStateManager: Current project updated to \(project.name)")
                } else {
                    print("📍 ProjectStateManager: Current project cleared")
                }
            }
            .store(in: &cancellables)
    }
    
    private func logProjectChange(from oldProject: Project?, to newProject: Project?) {
        if let old = oldProject, let new = newProject {
            print("🔄 Project changed: \(old.name) → \(new.name)")
        } else if let new = newProject {
            print("🆕 Project selected: \(new.name)")
        } else if let old = oldProject {
            print("❌ Project cleared: \(old.name)")
        }
    }
}

// MARK: - Migration Helpers

@available(iOS 16.0, macOS 13.0, *)
extension ProjectStateManager {
    /// Temporary helper for services migrating from their own project state
    public func migrateFromLegacyState(_ project: Project?) {
        if let project = project, currentProject == nil {
            print("🔄 Migrating legacy project state: \(project.name)")
            setCurrentProject(project)
        }
    }
}
