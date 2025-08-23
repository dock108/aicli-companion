import Foundation
import SwiftUI
import Combine

// MARK: - Project Status Information

extension Project {
    /// Status information for a project showing Claude processing state
    @MainActor
    class StatusInfo: ObservableObject {
        @Published var isProcessing: Bool = false
        @Published var lastActivity: String?
        @Published var processingStartTime: Date?
        @Published var elapsedSeconds: Int = 0
        
        func updateFromHeartbeat(_ data: [AnyHashable: Any]) {
            isProcessing = data["isProcessing"] as? Bool ?? false
            lastActivity = data["activity"] as? String
            elapsedSeconds = data["elapsedSeconds"] as? Int ?? 0
            
            if isProcessing && processingStartTime == nil {
                processingStartTime = Date()
            } else if !isProcessing {
                processingStartTime = nil
                elapsedSeconds = 0
                lastActivity = nil
            }
        }
        
        func reset() {
            isProcessing = false
            lastActivity = nil
            processingStartTime = nil
            elapsedSeconds = 0
        }
        
        var formattedElapsedTime: String {
            if elapsedSeconds < 60 {
                return "\(elapsedSeconds)s"
            } else {
                let minutes = elapsedSeconds / 60
                let seconds = elapsedSeconds % 60
                return "\(minutes)m \(seconds)s"
            }
        }
    }
}

// MARK: - Project Status Manager

/// Manages status information for all projects
@MainActor
@available(iOS 16.0, macOS 13.0, *)
final class ProjectStatusManager: ObservableObject {
    static let shared = ProjectStatusManager()
    
    @Published private(set) var projectStatuses: [String: Project.StatusInfo] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupHeartbeatObserver()
    }
    
    private func setupHeartbeatObserver() {
        NotificationCenter.default.publisher(for: .claudeHeartbeatReceived)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleHeartbeat(notification)
            }
            .store(in: &cancellables)
    }
    
    func statusFor(_ project: Project) -> Project.StatusInfo {
        statusFor(projectPath: project.path)
    }
    
    func statusFor(projectPath: String) -> Project.StatusInfo {
        if let status = projectStatuses[projectPath] {
            return status
        }
        let newStatus = Project.StatusInfo()
        projectStatuses[projectPath] = newStatus
        return newStatus
    }
    
    private func handleHeartbeat(_ notification: Notification) {
        print("📡 ProjectStatusManager: Received heartbeat notification")
        print("   UserInfo: \(notification.userInfo ?? [:])")
        
        guard let data = notification.userInfo,
              let projectPath = data["projectPath"] as? String else {
            print("⚠️ ProjectStatusManager: Missing projectPath in heartbeat data")
            print("   Available keys: \(notification.userInfo?.keys.map(String.init(describing:)) ?? [])")
            return
        }
        
        print("📡 ProjectStatusManager: Processing heartbeat for project: \(projectPath)")
        
        let status = statusFor(projectPath: projectPath)
        status.updateFromHeartbeat(data)
        
        // Enhanced logging for debugging
        print("📡 Project status update: \(projectPath)")
        print("   Processing: \(status.isProcessing)")
        print("   Activity: \(status.lastActivity ?? "none")")
        print("   Elapsed: \(status.elapsedSeconds)s")
        
        // Trigger UI update by updating published property
        objectWillChange.send()
    }
    
    /// Clear all project statuses
    func clearAll() {
        projectStatuses.values.forEach { $0.reset() }
        projectStatuses.removeAll()
    }
    
    /// Clear status for a specific project
    func clearStatus(for project: Project) {
        if let status = projectStatuses[project.path] {
            status.reset()
        }
    }
}