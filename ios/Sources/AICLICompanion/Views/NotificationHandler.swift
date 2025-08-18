import SwiftUI
import Combine

/// Handles navigation from push notifications
@available(iOS 16.0, macOS 13.0, *)
struct NotificationHandler: ViewModifier {
    @State private var cancellables = Set<AnyCancellable>()
    @StateObject private var projectStateManager = ProjectStateManager.shared
    
    // Bindings to parent view state
    @Binding var isConnected: Bool
    @Binding var selectedProject: Project?
    @Binding var isProjectSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                setupNotificationHandlers()
            }
    }
    
    private func setupNotificationHandlers() {
        // Listen for open project notifications
        NotificationCenter.default.publisher(for: .openProject)
            .sink { notification in
                handleOpenProject(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleOpenProject(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            print("⚠️ No userInfo in openProject notification")
            return
        }
        
        // Handle both old format (projectId/projectName) and new format (project/projectPath)
        var project: Project?
        
        if let projectObj = userInfo["project"] as? Project {
            // New format with Project object
            project = projectObj
        } else if let projectPath = userInfo["projectPath"] as? String {
            // New format with projectPath
            let projectName = userInfo["projectName"] as? String ?? projectPath.split(separator: "/").last.map(String.init) ?? "Project"
            project = Project(
                name: projectName,
                path: projectPath,
                type: "directory"
            )
        } else if let projectId = userInfo["projectId"] as? String {
            // Old format with projectId
            let projectName = userInfo["projectName"] as? String ?? "Project"
            project = Project(
                name: projectName,
                path: projectId,
                type: "directory"
            )
        }
        
        guard let finalProject = project else {
            print("⚠️ Could not extract project from notification")
            return
        }
        
        print("📱 Opening project from notification: \(finalProject.name) at \(finalProject.path)")
        
        // Navigate to project within existing navigation
        DispatchQueue.main.async {
            // Ensure we're connected first
            if !self.isConnected {
                print("⚠️ Not connected to server, cannot navigate to project")
                return
            }
            
            // Set the project in both places to ensure navigation
            self.projectStateManager.setCurrentProject(finalProject)
            self.selectedProject = finalProject
            self.isProjectSelected = true
            
            // Session IDs are now managed internally by the server
            // No need to track them in the iOS app
        }
        
        // Clear badge for this project
        PushNotificationService.shared.clearProjectNotifications(finalProject.path)
    }
}

// MARK: - View Extension

@available(iOS 16.0, macOS 13.0, *)
extension View {
    func handleNotifications(
        isConnected: Binding<Bool>,
        selectedProject: Binding<Project?>,
        isProjectSelected: Binding<Bool>
    ) -> some View {
        self.modifier(NotificationHandler(
            isConnected: isConnected,
            selectedProject: selectedProject,
            isProjectSelected: isProjectSelected
        ))
    }
}
