import Foundation
import Combine
import SwiftUI

// MARK: - Type Aliases for Existing Types
// Using the actual types from the codebase
public typealias MessageAttachment = AttachmentData
public typealias ProjectItem = Project
public typealias ArchivedSession = [Message] // Simplified for now

// MARK: - Core Service Protocols

@MainActor
public protocol AICLIServiceProtocol: AnyObject {
    var isConnected: Bool { get }
    var connectionPublisher: AnyPublisher<Bool, Never> { get }
    
    func connect(to url: URL, authToken: String?) async throws
    func disconnect()
    func sendMessage(_ message: String, projectPath: String, attachments: [MessageAttachment]) async throws -> Message
    func fetchProjects() async throws -> [ProjectItem]
    func clearChat(projectPath: String) async throws
}

@MainActor
public protocol MessagePersistenceServiceProtocol: AnyObject {
    func loadMessages(for projectPath: String) -> [Message]
    func saveMessage(_ message: Message, for projectPath: String)
    func clearMessages(for projectPath: String)
    func archiveCurrentSession(for projectPath: String, metadata: SessionMetadata)
    func loadArchivedSessions(for projectPath: String) -> [ArchivedSession]
}

@MainActor
public protocol ProjectStateManagerProtocol: AnyObject {
    var currentProject: ProjectItem? { get }
    var projectStatePublisher: AnyPublisher<ProjectItem?, Never> { get }
    
    func setProject(_ project: ProjectItem)
    func clearProject()
    func updateProjectContext(_ context: String)
}

// MARK: - Infrastructure Service Protocols

@MainActor
public protocol LoggingManagerProtocol: AnyObject {
    func log(_ message: String, level: LogLevel)
    func logError(_ error: Error, context: String?)
    func logNetworkRequest(_ request: URLRequest)
    func logNetworkResponse(_ response: URLResponse?, data: Data?, error: Error?)
}

@MainActor
public protocol SettingsManagerProtocol: AnyObject {
    var serverURL: String { get set }
    var authToken: String { get set }
    var autoConnect: Bool { get set }
    var enableNotifications: Bool { get set }
    var enableSoundEffects: Bool { get set }
    var enableHapticFeedback: Bool { get set }
    
    func save()
    func load()
}

@MainActor
public protocol PerformanceMonitorProtocol: AnyObject {
    func startTracking(_ metric: String) -> UUID
    func endTracking(_ id: UUID)
    func recordMetric(_ name: String, value: Double)
    func getMetrics() -> [String: Double]
}

// MARK: - Network Service Protocols

@MainActor
public protocol MessageFetchServiceProtocol: AnyObject {
    func fetchMessage(messageId: String, projectPath: String) async throws -> Message
    func fetchMessageBatch(messageIds: [String], projectPath: String) async throws -> [Message]
}

@MainActor
public protocol ConnectionReliabilityManagerProtocol: AnyObject {
    var isHealthy: Bool { get }
    var healthPublisher: AnyPublisher<Bool, Never> { get }
    
    func startMonitoring()
    func stopMonitoring()
    func reportSuccess()
    func reportFailure(_ error: Error)
}

@MainActor
public protocol ClaudeStatusManagerProtocol: AnyObject {
    var currentStatus: ClaudeStatus? { get }
    var statusPublisher: AnyPublisher<ClaudeStatus?, Never> { get }
    
    func updateStatus(_ status: ClaudeStatus)
    func checkStatus() async
}

@MainActor
public protocol PushNotificationServiceProtocol: AnyObject {
    func registerForPushNotifications()
    func handleNotification(_ userInfo: [AnyHashable: Any])
    func updateDeviceToken(_ token: String)
}

// MARK: - UI Service Protocols

@MainActor
public protocol MessageQueueManagerProtocol: AnyObject {
    var hasQueuedMessages: Bool { get }
    var queuedMessageCount: Int { get }
    
    func queueMessage(_ message: Message)
    func processQueue() async
    func clearQueue()
}

@MainActor
public protocol LoadingStateCoordinatorProtocol: AnyObject {
    var isLoading: Bool { get }
    var loadingMessage: String? { get }
    var loadingPublisher: AnyPublisher<Bool, Never> { get }
    
    func startLoading(message: String?)
    func stopLoading()
}

@MainActor
public protocol ClipboardManagerProtocol: AnyObject {
    func copy(_ text: String)
    func copyMessage(_ message: Message)
    func paste() -> String?
}

@MainActor
public protocol HapticManagerProtocol: AnyObject {
    func impact(_ style: HapticStyle)
    func notification(_ type: HapticNotificationType)
    func selection()
}

// MARK: - Supporting Types

public enum LogLevel {
    case debug, info, warning, error
}

// Note: ClaudeStatus enum already exists in the codebase
// Using the existing type instead of creating a duplicate

public enum HapticStyle {
    case light, medium, heavy, soft, rigid
}

public enum HapticNotificationType {
    case success, warning, error
}

// MARK: - Mock Implementations Stubs
// These would normally be in separate test files, but adding minimal stubs here for compilation

@MainActor
public final class MockAICLIService: AICLIServiceProtocol {
    public var isConnected = false
    public var connectionPublisher: AnyPublisher<Bool, Never> { Just(isConnected).eraseToAnyPublisher() }
    
    public func connect(to url: URL, authToken: String?) async throws {}
    public func disconnect() {}
    public func sendMessage(_ message: String, projectPath: String, attachments: [MessageAttachment]) async throws -> Message {
        return Message(id: UUID(), content: "Mock response", sender: .assistant, timestamp: Date())
    }
    public func fetchProjects() async throws -> [ProjectItem] { [] }
    public func clearChat(projectPath: String) async throws {}
}

@MainActor
public final class MockMessagePersistenceService: MessagePersistenceServiceProtocol {
    public func loadMessages(for projectPath: String) -> [Message] { [] }
    public func saveMessage(_ message: Message, for projectPath: String) {}
    public func clearMessages(for projectPath: String) {}
    public func archiveCurrentSession(for projectPath: String, metadata: SessionMetadata) {}
    public func loadArchivedSessions(for projectPath: String) -> [ArchivedSession] { [] }
}

@MainActor
public final class MockProjectStateManager: ProjectStateManagerProtocol {
    public var currentProject: ProjectItem?
    public var projectStatePublisher: AnyPublisher<ProjectItem?, Never> { Just(currentProject).eraseToAnyPublisher() }
    
    public func setProject(_ project: ProjectItem) {}
    public func clearProject() {}
    public func updateProjectContext(_ context: String) {}
}

@MainActor
public final class MockLoggingManager: LoggingManagerProtocol {
    public func log(_ message: String, level: LogLevel) {}
    public func logError(_ error: Error, context: String?) {}
    public func logNetworkRequest(_ request: URLRequest) {}
    public func logNetworkResponse(_ response: URLResponse?, data: Data?, error: Error?) {}
}

@MainActor
public final class MockSettingsManager: SettingsManagerProtocol {
    public var serverURL = ""
    public var authToken = ""
    public var autoConnect = false
    public var enableNotifications = true
    public var enableSoundEffects = true
    public var enableHapticFeedback = true
    
    public func save() {}
    public func load() {}
}

@MainActor
public final class MockPerformanceMonitor: PerformanceMonitorProtocol {
    public func startTracking(_ metric: String) -> UUID { UUID() }
    public func endTracking(_ id: UUID) {}
    public func recordMetric(_ name: String, value: Double) {}
    public func getMetrics() -> [String: Double] { [:] }
}

@MainActor
public final class MockMessageFetchService: MessageFetchServiceProtocol {
    public func fetchMessage(messageId: String, projectPath: String) async throws -> Message {
        return Message(id: UUID(), content: "Mock message", sender: .assistant, timestamp: Date())
    }
    public func fetchMessageBatch(messageIds: [String], projectPath: String) async throws -> [Message] { [] }
}

@MainActor
public final class MockConnectionReliabilityManager: ConnectionReliabilityManagerProtocol {
    public var isHealthy = true
    public var healthPublisher: AnyPublisher<Bool, Never> { Just(isHealthy).eraseToAnyPublisher() }
    
    public func startMonitoring() {}
    public func stopMonitoring() {}
    public func reportSuccess() {}
    public func reportFailure(_ error: Error) {}
}

@MainActor
public final class MockClaudeStatusManager: ClaudeStatusManagerProtocol {
    public var currentStatus: ClaudeStatus?
    public var statusPublisher: AnyPublisher<ClaudeStatus?, Never> { Just(currentStatus).eraseToAnyPublisher() }
    
    public func updateStatus(_ status: ClaudeStatus) {}
    public func checkStatus() async {}
}

@MainActor
public final class MockPushNotificationService: PushNotificationServiceProtocol {
    public func registerForPushNotifications() {}
    public func handleNotification(_ userInfo: [AnyHashable: Any]) {}
    public func updateDeviceToken(_ token: String) {}
}

@MainActor
public final class MockMessageQueueManager: MessageQueueManagerProtocol {
    public var hasQueuedMessages = false
    public var queuedMessageCount = 0
    
    public func queueMessage(_ message: Message) {}
    public func processQueue() async {}
    public func clearQueue() {}
}

@MainActor
public final class MockLoadingStateCoordinator: LoadingStateCoordinatorProtocol {
    public var isLoading = false
    public var loadingMessage: String?
    public var loadingPublisher: AnyPublisher<Bool, Never> { Just(isLoading).eraseToAnyPublisher() }
    
    public func startLoading(message: String?) {}
    public func stopLoading() {}
}

@MainActor
public final class MockClipboardManager: ClipboardManagerProtocol {
    public func copy(_ text: String) {}
    public func copyMessage(_ message: Message) {}
    public func paste() -> String? { nil }
}

@MainActor
public final class MockHapticManager: HapticManagerProtocol {
    public func impact(_ style: HapticStyle) {}
    public func notification(_ type: HapticNotificationType) {}
    public func selection() {}
}
