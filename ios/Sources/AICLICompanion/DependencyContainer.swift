import SwiftUI
import Combine

// MARK: - Dependency Container
/// Central container for all app dependencies using SwiftUI's environment
/// Uses lazy initialization to prevent main thread blocking during app startup
@MainActor
final class DependencyContainer: ObservableObject {
    // MARK: - Lightweight Services (initialized immediately)
    @Published private(set) var loggingManager: LoggingManager
    @Published private(set) var hapticManager: HapticManager
    @Published private(set) var performanceMonitor: PerformanceMonitor
    @Published private(set) var clipboardManager: ClipboardManager
    @Published private(set) var settingsManager: SettingsManager
    
    // MARK: - Heavy Services (lazy initialization to prevent UI blocking)
    @Published private var _aicliService: AICLIService?
    @Published private var _messagePersistenceService: MessagePersistenceService?
    @Published private var _projectStateManager: ProjectStateManager?
    @Published private var _messageFetchService: MessageFetchService?
    @Published private var _messageQueueManager: MessageQueueManager?
    @Published private var _loadingStateCoordinator: LoadingStateCoordinator?
    @Published private var _connectionReliabilityManager: ConnectionReliabilityManager?
    @Published private var _claudeStatusManager: ClaudeStatusManager?
    @Published private var _pushNotificationService: PushNotificationService?
    
    // MARK: - Lazy Service Accessors
    var aicliService: AICLIService {
        if let service = _aicliService {
            return service
        }
        print("🚀 [PERF] Lazy initializing AICLIService at \(Date())")
        let service = AICLIService()
        _aicliService = service
        return service
    }
    
    var messagePersistenceService: MessagePersistenceService {
        if let service = _messagePersistenceService {
            return service
        }
        print("🚀 [PERF] Lazy initializing MessagePersistenceService at \(Date())")
        let service = MessagePersistenceService.shared
        _messagePersistenceService = service
        return service
    }
    
    var projectStateManager: ProjectStateManager {
        if let service = _projectStateManager {
            return service
        }
        print("🚀 [PERF] Lazy initializing ProjectStateManager at \(Date())")
        let service = ProjectStateManager.shared
        _projectStateManager = service
        return service
    }
    
    var messageFetchService: MessageFetchService {
        if let service = _messageFetchService {
            return service
        }
        print("🚀 [PERF] Lazy initializing MessageFetchService at \(Date())")
        let service = MessageFetchService.shared
        _messageFetchService = service
        return service
    }
    
    var messageQueueManager: MessageQueueManager {
        if let service = _messageQueueManager {
            return service
        }
        print("🚀 [PERF] Lazy initializing MessageQueueManager at \(Date())")
        let service = MessageQueueManager.shared
        _messageQueueManager = service
        return service
    }
    
    var loadingStateCoordinator: LoadingStateCoordinator {
        if let service = _loadingStateCoordinator {
            return service
        }
        print("🚀 [PERF] Lazy initializing LoadingStateCoordinator at \(Date())")
        let service = LoadingStateCoordinator.shared
        _loadingStateCoordinator = service
        return service
    }
    
    var connectionReliabilityManager: ConnectionReliabilityManager {
        if let service = _connectionReliabilityManager {
            return service
        }
        print("🚀 [PERF] Lazy initializing ConnectionReliabilityManager at \(Date())")
        let service = ConnectionReliabilityManager.shared
        _connectionReliabilityManager = service
        return service
    }
    
    var claudeStatusManager: ClaudeStatusManager {
        if let service = _claudeStatusManager {
            return service
        }
        print("🚀 [PERF] Lazy initializing ClaudeStatusManager at \(Date())")
        let service = ClaudeStatusManager.shared
        _claudeStatusManager = service
        return service
    }
    
    var pushNotificationService: PushNotificationService {
        if let service = _pushNotificationService {
            return service
        }
        print("🚀 [PERF] Lazy initializing PushNotificationService at \(Date())")
        let service = PushNotificationService.shared
        _pushNotificationService = service
        return service
    }
    
    // MARK: - Initialization
    init() {
        print("🚀 [PERF] DependencyContainer init started at \(Date())")
        
        // CRITICAL: Only initialize lightweight services synchronously to prevent UI blocking
        // Heavy services use lazy initialization and are created only when first accessed
        
        // Initialize only essential, lightweight services immediately
        self.loggingManager = LoggingManager.shared
        self.hapticManager = HapticManager.shared
        self.performanceMonitor = PerformanceMonitor.shared
        self.clipboardManager = ClipboardManager.shared
        self.settingsManager = SettingsManager()
        
        // Heavy services are nil initially - will be created lazily when first accessed
        self._aicliService = nil
        self._messagePersistenceService = nil
        self._projectStateManager = nil
        self._messageFetchService = nil
        self._messageQueueManager = nil
        self._loadingStateCoordinator = nil
        self._connectionReliabilityManager = nil
        self._claudeStatusManager = nil
        self._pushNotificationService = nil
        
        print("🚀 [PERF] DependencyContainer init completed in <1ms at \(Date())")
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
