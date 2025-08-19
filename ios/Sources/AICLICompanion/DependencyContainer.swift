import SwiftUI
import Combine

// MARK: - Dependency Container
/// Central container for all app dependencies using SwiftUI's environment
@MainActor
final class DependencyContainer: ObservableObject {
    // MARK: - Services
    @Published var aicliService: AICLIService
    @Published var messagePersistenceService: MessagePersistenceService
    @Published var projectStateManager: ProjectStateManager
    @Published var loggingManager: LoggingManager
    @Published var messageFetchService: MessageFetchService
    @Published var messageQueueManager: MessageQueueManager
    @Published var loadingStateCoordinator: LoadingStateCoordinator
    @Published var clipboardManager: ClipboardManager
    @Published var connectionReliabilityManager: ConnectionReliabilityManager
    @Published var claudeStatusManager: ClaudeStatusManager
    @Published var settingsManager: SettingsManager
    @Published var hapticManager: HapticManager
    @Published var performanceMonitor: PerformanceMonitor
    @Published var pushNotificationService: PushNotificationService
    
    // MARK: - Initialization
    init() {
        // Use existing shared instances instead of creating new ones
        self.loggingManager = LoggingManager.shared
        self.settingsManager = SettingsManager()
        self.hapticManager = HapticManager.shared
        self.performanceMonitor = PerformanceMonitor.shared
        
        // Initialize data services using shared instances
        self.messagePersistenceService = MessagePersistenceService.shared
        self.projectStateManager = ProjectStateManager.shared
        
        // Initialize network services
        self.aicliService = AICLIService()
        self.messageFetchService = MessageFetchService.shared
        self.connectionReliabilityManager = ConnectionReliabilityManager.shared
        self.claudeStatusManager = ClaudeStatusManager.shared
        self.pushNotificationService = PushNotificationService.shared
        
        // Initialize UI services
        self.messageQueueManager = MessageQueueManager.shared
        self.loadingStateCoordinator = LoadingStateCoordinator.shared
        self.clipboardManager = ClipboardManager.shared
        
        // Note: Dependencies are already wired in the singletons
        // No need to inject them again
    }
}

// MARK: - Environment Key
private struct DependencyContainerKey: EnvironmentKey {
    @MainActor static let defaultValue = DependencyContainer()
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - View Extension for Easy Access
extension View {
    func withDependencies(_ container: DependencyContainer) -> some View {
        self.environment(\.dependencies, container)
    }
}

// MARK: - Convenience Property Wrapper
@propertyWrapper
struct Injected<T> {
    private let keyPath: KeyPath<DependencyContainer, T>
    @Environment(\.dependencies) private var container
    
    init(_ keyPath: KeyPath<DependencyContainer, T>) {
        self.keyPath = keyPath
    }
    
    var wrappedValue: T {
        container[keyPath: keyPath]
    }
}

// MARK: - Migration Helper
/// Temporary helper to ease migration from singletons
/// This will be removed once all references are updated
extension DependencyContainer {
    private static var _shared: DependencyContainer?
    
    /// Temporary shared instance for migration purposes only
    /// DO NOT USE IN NEW CODE - use dependency injection instead
    @available(*, deprecated, message: "Use dependency injection instead of singleton")
    static var shared: DependencyContainer {
        if _shared == nil {
            _shared = DependencyContainer()
        }
        return _shared!
    }
}
