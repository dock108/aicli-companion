import SwiftUI
import Combine

/// Manages loading states and progress tracking
@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatLoadingStateManager: ObservableObject {
    
    // MARK: - Dependencies
    private let loadingStateCoordinator: LoadingStateCoordinator
    
    // MARK: - Published Properties
    @Published var isLoading: Bool = false
    @Published var isWaitingForClaudeResponse: Bool = false
    @Published var progressInfo: ProgressInfo?
    
    // MARK: - Initialization
    init(loadingStateCoordinator: LoadingStateCoordinator = .shared) {
        self.loadingStateCoordinator = loadingStateCoordinator
    }
    
    // MARK: - Loading State Operations
    
    func setLoading(_ loading: Bool, for projectPath: String? = nil) {
        print("⏳ LoadingStateManager: Setting loading to \(loading)")
        isLoading = loading
        
        if let projectPath = projectPath {
            if loading {
                loadingStateCoordinator.startProjectLoading(projectPath)
            } else {
                loadingStateCoordinator.stopProjectLoading(projectPath)
            }
        }
    }
    
    func setWaitingForResponse(_ waiting: Bool) {
        print("⏳ LoadingStateManager: Setting waiting for response to \(waiting)")
        isWaitingForClaudeResponse = waiting
    }
    
    func updateProgressInfo(_ progress: ProgressInfo?) {
        print("⏳ LoadingStateManager: Updating progress info")
        progressInfo = progress
    }
    
    func clearLoadingState(for projectPath: String) {
        print("⏳ LoadingStateManager: Clearing loading state for: \(projectPath)")
        isLoading = false
        isWaitingForClaudeResponse = false
        progressInfo = nil
        loadingStateCoordinator.stopProjectLoading(projectPath)
    }
    
    func clearAllLoadingStates() {
        print("⏳ LoadingStateManager: Clearing all loading states")
        isLoading = false
        isWaitingForClaudeResponse = false
        progressInfo = nil
    }
}