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
        
        // Listen for open chat session notifications
        NotificationCenter.default.publisher(for: .openChatSession)
            .sink { notification in
                handleOpenChatSession(notification)
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
        EnhancedPushNotificationService.shared.clearProjectNotifications(projectId)
    }
    
    private func handleOpenChatSession(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionId = userInfo["sessionId"] as? String else {
            return
        }
        
        print("📱 Opening chat session from notification: \(sessionId)")
        
        // For now, just store the session ID
        // The actual navigation would depend on your app's structure
        DispatchQueue.main.async {
            navigateToSession = sessionId
        }
    }
}

// MARK: - View Extension

@available(iOS 13.0, macOS 10.15, *)
extension View {
    func handleNotifications() -> some View {
        self.modifier(NotificationHandler())
    }
}

// MARK: - Badge Management View

@available(iOS 16.0, macOS 13.0, *)
struct BadgeCountView: View {
    @StateObject private var notificationService = EnhancedPushNotificationService.shared
    
    var body: some View {
        Group {
            if notificationService.badgeCount > 0 {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 20, height: 20)
                    
                    Text("\(notificationService.badgeCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Project List Badge Extension

@available(iOS 16.0, macOS 13.0, *)
struct ProjectBadgeModifier: ViewModifier {
    let projectId: String
    @StateObject private var notificationService = EnhancedPushNotificationService.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                // swiftlint:disable:next empty_count
                if let count = notificationService.pendingNotifications[projectId], count > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 18, height: 18)
                        
                        Text("\(count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 8, y: -8)
                }
            }
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension View {
    func projectBadge(for projectId: String) -> some View {
        self.modifier(ProjectBadgeModifier(projectId: projectId))
    }
}
