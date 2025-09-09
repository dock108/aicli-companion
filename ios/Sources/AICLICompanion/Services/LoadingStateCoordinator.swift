import Foundation
import Combine

/// Unified loading state management - single source of truth for all loading states
/// Eliminates duplication between isLoading, isLoadingQR, project loading states
@available(iOS 16.0, macOS 13.0, *)
public class LoadingStateCoordinator: ObservableObject {
    // MARK: - Singleton
    public static let shared = LoadingStateCoordinator()
    
    // MARK: - Loading State Types
    
    public enum LoadingType: String, CaseIterable {
        case chatMessage = "chat_message"
        case projectSelection = "project_selection"
        case qrScanning = "qr_scanning"
        case connection = "connection"
        case fileOperation = "file_operation"
        case cloudKitSync = "cloudkit_sync"
        case authentication = "authentication"
        case projectAnalysis = "project_analysis"
    }
    
    // MARK: - Published State
    
    @Published public private(set) var activeLoadingStates: Set<String> = []
    @Published public private(set) var projectLoadingStates: [String: Bool] = [:]
    @Published public private(set) var loadingTimeouts: [String: Timer] = [:]
    
    // MARK: - Computed Properties
    
    /// Check if any loading operation is active
    public var isAnyLoading: Bool {
        return !activeLoadingStates.isEmpty || projectLoadingStates.values.contains(true)
    }
    
    /// Check if a specific loading type is active
    public func isLoading(_ type: LoadingType) -> Bool {
        return activeLoadingStates.contains(type.rawValue)
    }
    
    /// Check if a specific project is loading
    public func isProjectLoading(_ projectPath: String) -> Bool {
        return projectLoadingStates[projectPath] ?? false
    }
    
    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupDebugLogging()
    }
    
    // MARK: - Public API
    
    /// Start loading for a specific type
    public func startLoading(_ type: LoadingType, timeout: TimeInterval? = nil) {
        let identifier = type.rawValue
        
        guard !activeLoadingStates.contains(identifier) else {
            return
        }
        
        activeLoadingStates.insert(identifier)
        
        if let timeout = timeout {
            startTimeout(for: identifier, duration: timeout)
        }
        
        objectWillChange.send()
    }
    
    /// Stop loading for a specific type
    public func stopLoading(_ type: LoadingType) {
        let identifier = type.rawValue
        
        guard activeLoadingStates.contains(identifier) else {
            return
        }
        
        activeLoadingStates.remove(identifier)
        clearTimeout(for: identifier)
        objectWillChange.send()
    }
    
    /// Start loading for a specific project
    public func startProjectLoading(_ projectPath: String, timeout: TimeInterval? = nil) {
        let identifier = "project_\(projectPath)"
        
        projectLoadingStates[projectPath] = true
        
        if let timeout = timeout {
            startTimeout(for: identifier, duration: timeout)
        }
        
        objectWillChange.send()
    }
    
    /// Stop loading for a specific project
    public func stopProjectLoading(_ projectPath: String) {
        let identifier = "project_\(projectPath)"
        
        guard projectLoadingStates[projectPath] == true else {
            return
        }
        
        projectLoadingStates[projectPath] = false
        clearTimeout(for: identifier)
        objectWillChange.send()
    }
    
    /// Clear all loading states
    public func clearAllLoading() {
        let hadLoading = isAnyLoading
        
        activeLoadingStates.removeAll()
        projectLoadingStates.removeAll()
        clearAllTimeouts()
        
        if hadLoading {
            print("🧹 LoadingStateCoordinator: Cleared all loading states")
            objectWillChange.send()
        }
    }
    
    /// Get loading message for a specific type
    public func getLoadingMessage(for type: LoadingType) -> String {
        switch type {
        case .chatMessage:
            return "Sending message to Claude..."
        case .projectSelection:
            return "Loading projects..."
        case .qrScanning:
            return "Scanning QR code..."
        case .connection:
            return "Connecting to server..."
        case .fileOperation:
            return "Processing files..."
        case .cloudKitSync:
            return "Syncing to iCloud..."
        case .authentication:
            return "Authenticating..."
        case .projectAnalysis:
            return "Analyzing project..."
        }
    }
    
    // MARK: - Timeout Management
    
    private func startTimeout(for identifier: String, duration: TimeInterval) {
        clearTimeout(for: identifier)
        
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            print("⏰ LoadingStateCoordinator: Timeout for \(identifier) after \(duration) seconds")
            self?.forceStop(identifier: identifier)
        }
        
        loadingTimeouts[identifier] = timer
    }
    
    private func clearTimeout(for identifier: String) {
        loadingTimeouts[identifier]?.invalidate()
        loadingTimeouts.removeValue(forKey: identifier)
    }
    
    private func clearAllTimeouts() {
        loadingTimeouts.values.forEach { $0.invalidate() }
        loadingTimeouts.removeAll()
    }
    
    private func forceStop(identifier: String) {
        if identifier.hasPrefix("project_") {
            let projectPath = String(identifier.dropFirst("project_".count))
            projectLoadingStates[projectPath] = false
        } else {
            activeLoadingStates.remove(identifier)
        }
        
        clearTimeout(for: identifier)
        objectWillChange.send()
    }
    
    // MARK: - Debug Support
    
    private func setupDebugLogging() {
        // Removed verbose debug logging
    }
}

// MARK: - Convenience Extensions

@available(iOS 16.0, macOS 13.0, *)
extension LoadingStateCoordinator {
    /// Convenience method for chat loading
    public func startChatLoading(for projectPath: String, timeout: TimeInterval = 300.0) {
        startProjectLoading(projectPath, timeout: timeout)
    }
    
    /// Convenience method for chat loading
    public func stopChatLoading(for projectPath: String) {
        stopProjectLoading(projectPath)
    }
    
    /// Check if chat is loading for specific project
    public func isChatLoading(for projectPath: String) -> Bool {
        return isProjectLoading(projectPath)
    }
}

// MARK: - Migration Helpers

@available(iOS 16.0, macOS 13.0, *)
extension LoadingStateCoordinator {
    /// Temporary helper for components migrating from their own loading state
    public func migrateFromLegacyState(_ isLoading: Bool, type: LoadingType) {
        if isLoading && !self.isLoading(type) {
            print("🔄 Migrating legacy loading state: \(type.rawValue)")
            startLoading(type)
        } else if !isLoading && self.isLoading(type) {
            print("🔄 Migrating legacy loading stop: \(type.rawValue)")
            stopLoading(type)
        }
    }
}
