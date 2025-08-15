import SwiftUI
import Combine

/// Handles navigation from push notifications
@available(iOS 16.0, macOS 13.0, *)
struct NotificationHandler: ViewModifier {
    @State private var navigateToProject: Project?
    @State private var navigateToSession: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                setupNotificationHandlers()
            }
            .sheet(item: $navigateToProject) { project in
                NavigationView {
                    ChatView(
                        selectedProject: project,
                        session: nil,
                        onSwitchProject: {
                            navigateToProject = nil
                        }
                    )
                }
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
        guard let userInfo = notification.userInfo,
              let projectId = userInfo["projectId"] as? String,
              let projectName = userInfo["projectName"] as? String else {
            return
        }
        
        print("📱 Opening project from notification: \(projectName)")
        
        // Create project object
        let project = Project(
            name: projectName,
            path: projectId,
            type: "directory"
        )
        
        // Navigate to project
        DispatchQueue.main.async {
            navigateToProject = project
            navigateToSession = userInfo["sessionId"] as? String
        }
        
        // Clear badge for this project
        PushNotificationService.shared.clearProjectNotifications(projectId)
    }
}

// MARK: - View Extension

@available(iOS 13.0, macOS 10.15, *)
extension View {
    func handleNotifications() -> some View {
        self.modifier(NotificationHandler())
    }
}
