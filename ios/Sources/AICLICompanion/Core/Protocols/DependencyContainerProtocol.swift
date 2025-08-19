import Foundation
import Combine

// MARK: - Dependency Container Protocol
/// Protocol defining all app dependencies for testability and modularity
@MainActor
public protocol DependencyContainerProtocol {
    // Core Services
    var aicliService: AICLIServiceProtocol { get }
    var messagePersistenceService: MessagePersistenceServiceProtocol { get }
    var projectStateManager: ProjectStateManagerProtocol { get }
    
    // Infrastructure Services
    var loggingManager: LoggingManagerProtocol { get }
    var settingsManager: SettingsManagerProtocol { get }
    var performanceMonitor: PerformanceMonitorProtocol { get }
    
    // Network Services
    var messageFetchService: MessageFetchServiceProtocol { get }
    var connectionReliabilityManager: ConnectionReliabilityManagerProtocol { get }
    var claudeStatusManager: ClaudeStatusManagerProtocol { get }
    var pushNotificationService: PushNotificationServiceProtocol { get }
    
    // UI Services
    var messageQueueManager: MessageQueueManagerProtocol { get }
    var loadingStateCoordinator: LoadingStateCoordinatorProtocol { get }
    var clipboardManager: ClipboardManagerProtocol { get }
    var hapticManager: HapticManagerProtocol { get }
}

// MARK: - Mock Dependency Container for Testing
@MainActor
public final class MockDependencyContainer: DependencyContainerProtocol {
    public var aicliService: AICLIServiceProtocol
    public var messagePersistenceService: MessagePersistenceServiceProtocol
    public var projectStateManager: ProjectStateManagerProtocol
    public var loggingManager: LoggingManagerProtocol
    public var settingsManager: SettingsManagerProtocol
    public var performanceMonitor: PerformanceMonitorProtocol
    public var messageFetchService: MessageFetchServiceProtocol
    public var connectionReliabilityManager: ConnectionReliabilityManagerProtocol
    public var claudeStatusManager: ClaudeStatusManagerProtocol
    public var pushNotificationService: PushNotificationServiceProtocol
    public var messageQueueManager: MessageQueueManagerProtocol
    public var loadingStateCoordinator: LoadingStateCoordinatorProtocol
    public var clipboardManager: ClipboardManagerProtocol
    public var hapticManager: HapticManagerProtocol
    
    public init(
        aicliService: AICLIServiceProtocol? = nil,
        messagePersistenceService: MessagePersistenceServiceProtocol? = nil,
        projectStateManager: ProjectStateManagerProtocol? = nil,
        loggingManager: LoggingManagerProtocol? = nil,
        settingsManager: SettingsManagerProtocol? = nil,
        performanceMonitor: PerformanceMonitorProtocol? = nil,
        messageFetchService: MessageFetchServiceProtocol? = nil,
        connectionReliabilityManager: ConnectionReliabilityManagerProtocol? = nil,
        claudeStatusManager: ClaudeStatusManagerProtocol? = nil,
        pushNotificationService: PushNotificationServiceProtocol? = nil,
        messageQueueManager: MessageQueueManagerProtocol? = nil,
        loadingStateCoordinator: LoadingStateCoordinatorProtocol? = nil,
        clipboardManager: ClipboardManagerProtocol? = nil,
        hapticManager: HapticManagerProtocol? = nil
    ) {
        self.aicliService = aicliService ?? MockAICLIService()
        self.messagePersistenceService = messagePersistenceService ?? MockMessagePersistenceService()
        self.projectStateManager = projectStateManager ?? MockProjectStateManager()
        self.loggingManager = loggingManager ?? MockLoggingManager()
        self.settingsManager = settingsManager ?? MockSettingsManager()
        self.performanceMonitor = performanceMonitor ?? MockPerformanceMonitor()
        self.messageFetchService = messageFetchService ?? MockMessageFetchService()
        self.connectionReliabilityManager = connectionReliabilityManager ?? MockConnectionReliabilityManager()
        self.claudeStatusManager = claudeStatusManager ?? MockClaudeStatusManager()
        self.pushNotificationService = pushNotificationService ?? MockPushNotificationService()
        self.messageQueueManager = messageQueueManager ?? MockMessageQueueManager()
        self.loadingStateCoordinator = loadingStateCoordinator ?? MockLoadingStateCoordinator()
        self.clipboardManager = clipboardManager ?? MockClipboardManager()
        self.hapticManager = hapticManager ?? MockHapticManager()
    }
}
