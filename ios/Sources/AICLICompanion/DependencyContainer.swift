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
    @Published var sessionStatePersistence: SessionStatePersistenceService
    @Published var claudeStatusManager: ClaudeStatusManager
    @Published var settingsManager: SettingsManager
    @Published var hapticManager: HapticManager
    @Published var performanceMonitor: PerformanceMonitor
    @Published var pushNotificationService: PushNotificationService
    
    // MARK: - Initialization
    init() {
        // Initialize core services first
        self.loggingManager = LoggingManager()
        self.settingsManager = SettingsManager()
        self.hapticManager = HapticManager()
        self.performanceMonitor = PerformanceMonitor()
        
        // Initialize data services
        self.messagePersistenceService = MessagePersistenceService()
        self.projectStateManager = ProjectStateManager()
        self.sessionStatePersistence = SessionStatePersistenceService()
        
        // Initialize network services
        self.aicliService = AICLIService()
        self.messageFetchService = MessageFetchService()
        self.connectionReliabilityManager = ConnectionReliabilityManager()
        self.claudeStatusManager = ClaudeStatusManager()
        self.pushNotificationService = PushNotificationService()
        
        // Initialize UI services
        self.messageQueueManager = MessageQueueManager()
        self.loadingStateCoordinator = LoadingStateCoordinator()
        self.clipboardManager = ClipboardManager()
        
        // Inject dependencies where needed
        injectDependencies()
    }
    
    // MARK: - Dependency Injection
    private func injectDependencies() {
        // Inject logger into services that need it
        messagePersistenceService.logger = loggingManager
        aicliService.logger = loggingManager
        projectStateManager.logger = loggingManager
        
        // Inject persistence into services that need it
        aicliService.persistenceService = messagePersistenceService
        messageFetchService.aicliService = aicliService
        
        // Inject haptics
        clipboardManager.hapticManager = hapticManager
        
        // Inject performance monitoring
        aicliService.performanceMonitor = performanceMonitor
        messagePersistenceService.performanceMonitor = performanceMonitor
    }
}

// MARK: - Environment Key
private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainer()
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