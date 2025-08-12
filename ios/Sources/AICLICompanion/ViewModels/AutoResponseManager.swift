import Foundation
import Combine
import SwiftUI

/// Configuration for auto-response mode
@available(iOS 16.0, macOS 13.0, *)
public struct AutoResponseConfig: Codable {
    var enabled: Bool = false
    var defaultPrompt: String = "Continue working on the current task. If you need clarification, make reasonable assumptions and proceed."
    var maxIterations: Int = 10
    var stopPhrases: [String] = ["TASK_COMPLETE", "NO_MORE_WORK", "FINISHED", "ALL_DONE", "STOP_AUTO"]
    var timeoutSeconds: Int = 300
    var requireConfirmation: Bool = true
    var showNotifications: Bool = true
    
    // Advanced settings
    var delayBetweenResponses: TimeInterval = 2.0
    var enableSafeMode: Bool = true // Prevents destructive operations
    var allowedCommands: [String] = [] // Empty means all allowed
}

/// Manages automatic response functionality ("Jesus Take the Wheel" mode)
@available(iOS 16.0, macOS 13.0, *)
@MainActor
public class AutoResponseManager: ObservableObject {
    public static let shared = AutoResponseManager()
    
    // MARK: - Published Properties
    @Published public var config = AutoResponseConfig()
    @Published public var isActive: Bool = false
    @Published public var currentIteration: Int = 0
    @Published public var history: [AutoResponseEntry] = []
    @Published public var isPaused: Bool = false
    @Published public var lastError: String?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var responseTimer: Timer?
    private var startTime: Date?
    private var messageSubscription: AnyCancellable?
    
    // MARK: - Computed Properties
    public var canActivate: Bool {
        !isActive && config.enabled
    }
    
    public var elapsedTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    public var remainingIterations: Int {
        max(0, config.maxIterations - currentIteration)
    }
    
    // MARK: - Initialization
    private init() {
        loadConfig()
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    /// Activate auto-response mode
    public func activate() {
        guard canActivate else { return }
        
        isActive = true
        currentIteration = 0
        startTime = Date()
        lastError = nil
        
        // Add activation entry to history
        let entry = AutoResponseEntry(
            type: .activation,
            message: "Auto-response mode activated",
            timestamp: Date()
        )
        history.append(entry)
        
        if config.showNotifications {
            showNotification(title: "Auto Mode Active",
                           body: "Claude will continue working automatically")
        }
        print("🤖 Auto-response mode ACTIVATED")
    }
    
    /// Deactivate auto-response mode
    public func deactivate(reason: DeactivationReason = .manual) {
        guard isActive else { return }
        
        isActive = false
        isPaused = false
        responseTimer?.invalidate()
        responseTimer = nil
        
        // Add deactivation entry to history
        let entry = AutoResponseEntry(
            type: .deactivation(reason),
            message: "Auto-response mode deactivated: \(reason.description)",
            timestamp: Date()
        )
        history.append(entry)
        
        if config.showNotifications {
            showNotification(title: "Auto Mode Stopped",
                           body: reason.description)
        }
        print("🛑 Auto-response mode DEACTIVATED: \(reason.description)")
    }
    
    /// Pause auto-response mode
    public func pause() {
        guard isActive && !isPaused else { return }
        isPaused = true
        responseTimer?.invalidate()
        
        let entry = AutoResponseEntry(
            type: .paused,
            message: "Auto-response paused",
            timestamp: Date()
        )
        history.append(entry)
        
        print("⏸️ Auto-response mode PAUSED")
    }
    
    /// Resume auto-response mode
    public func resume() {
        guard isActive && isPaused else { return }
        isPaused = false
        
        let entry = AutoResponseEntry(
            type: .resumed,
            message: "Auto-response resumed",
            timestamp: Date()
        )
        history.append(entry)
        
        print("▶️ Auto-response mode RESUMED")
    }
    
    /// Process incoming message for auto-response
    func processMessage(_ message: Message) -> String? {
        guard isActive && !isPaused else { return nil }
        
        // Check for stop phrases
        if containsStopPhrase(in: message.content) {
            deactivate(reason: .stopPhraseDetected)
            return nil
        }
        
        // Check iteration limit
        currentIteration += 1
        if currentIteration >= config.maxIterations {
            deactivate(reason: .maxIterationsReached)
            return nil
        }
        
        // Check timeout
        if elapsedTime > TimeInterval(config.timeoutSeconds) {
            deactivate(reason: .timeout)
            return nil
        }
        
        // Check if message is asking for confirmation or appears to need input
        if shouldAutoRespond(to: message) {
            let response = generateAutoResponse(for: message)
            
            // Log the auto-response
            let entry = AutoResponseEntry(
                type: .response(currentIteration),
                message: response,
                originalMessage: message.content,
                timestamp: Date()
            )
            history.append(entry)
            
            return response
        }
        
        return nil
    }
    
    /// Clear auto-response history
    public func clearHistory() {
        history.removeAll()
    }
    
    /// Save configuration
    public func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "AutoResponseConfig")
        }
    }
    
    /// Reset to default configuration
    public func resetConfig() {
        config = AutoResponseConfig()
        saveConfig()
    }
    
    // MARK: - Private Methods
    
    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: "AutoResponseConfig"),
           let decoded = try? JSONDecoder().decode(AutoResponseConfig.self, from: data) {
            config = decoded
        }
    }
    
    private func setupObservers() {
        // Save config when it changes
        $config
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveConfig()
            }
            .store(in: &cancellables)
    }
    
    private func containsStopPhrase(in text: String) -> Bool {
        let lowercased = text.lowercased()
        return config.stopPhrases.contains { phrase in
            lowercased.contains(phrase.lowercased())
        }
    }
    
    private func shouldAutoRespond(to message: Message) -> Bool {
        // Only auto-respond to assistant messages
        guard message.sender == .assistant else { return false }
        
        // Check for question patterns
        let questionPatterns = [
            "?",
            "would you like",
            "should i",
            "can i",
            "may i",
            "shall i",
            "do you want",
            "is it okay",
            "confirm",
            "proceed",
            "continue"
        ]
        
        let lowercased = message.content.lowercased()
        let hasQuestion = questionPatterns.contains { pattern in
            lowercased.contains(pattern)
        }
        
        // In safe mode, be more conservative
        if config.enableSafeMode {
            let dangerousPatterns = [
                "delete",
                "remove",
                "destroy",
                "drop",
                "truncate",
                "format",
                "wipe"
            ]
            
            let hasDangerousPattern = dangerousPatterns.contains { pattern in
                lowercased.contains(pattern)
            }
            
            if hasDangerousPattern && !config.requireConfirmation {
                return false // Don't auto-respond to potentially dangerous operations
            }
        }
        
        return hasQuestion
    }
    
    private func generateAutoResponse(for message: Message) -> String {
        // Use custom prompt if the message seems to need specific input
        let needsSpecificInput = message.content.lowercased().contains("please provide") ||
                                message.content.lowercased().contains("what would you like") ||
                                message.content.lowercased().contains("which option")
        
        if needsSpecificInput {
            // Try to be more intelligent about the response
            if message.content.lowercased().contains("directory") ||
               message.content.lowercased().contains("path") {
                return "Use the current working directory."
            } else if message.content.lowercased().contains("name") {
                return "Use a descriptive name based on the functionality."
            } else if message.content.lowercased().contains("yes") ||
                      message.content.lowercased().contains("no") {
                return "Yes, please proceed."
            }
        }
        
        // Default to configured prompt
        return config.defaultPrompt
    }
    
    private func showNotification(title: String, body: String) {
        #if os(iOS)
        // Would integrate with push notification service
        print("📱 Notification: \(title) - \(body)")
        #endif
    }
}

// MARK: - Supporting Types

@available(iOS 16.0, macOS 13.0, *)
public struct AutoResponseEntry: Identifiable, Codable {
    public let id = UUID()
    public let type: EntryType
    public let message: String
    public var originalMessage: String?
    public let timestamp: Date
    
    public enum EntryType: Codable {
        case activation
        case deactivation(DeactivationReason)
        case response(Int) // iteration number
        case paused
        case resumed
        case error(String)
        
        private enum CodingKeys: String, CodingKey {
            case type, reason, iteration, error
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            switch type {
            case "activation": self = .activation
            case "deactivation":
                let reason = try container.decode(DeactivationReason.self, forKey: .reason)
                self = .deactivation(reason)
            case "response":
                let iteration = try container.decode(Int.self, forKey: .iteration)
                self = .response(iteration)
            case "paused": self = .paused
            case "resumed": self = .resumed
            case "error":
                let error = try container.decode(String.self, forKey: .error)
                self = .error(error)
            default: self = .activation
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .activation:
                try container.encode("activation", forKey: .type)
            case .deactivation(let reason):
                try container.encode("deactivation", forKey: .type)
                try container.encode(reason, forKey: .reason)
            case .response(let iteration):
                try container.encode("response", forKey: .type)
                try container.encode(iteration, forKey: .iteration)
            case .paused:
                try container.encode("paused", forKey: .type)
            case .resumed:
                try container.encode("resumed", forKey: .type)
            case .error(let error):
                try container.encode("error", forKey: .type)
                try container.encode(error, forKey: .error)
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
public enum DeactivationReason: String, Codable {
    case manual = "Manual stop by user"
    case stopPhraseDetected = "Stop phrase detected"
    case maxIterationsReached = "Maximum iterations reached"
    case timeout = "Operation timed out"
    case error = "Error occurred"
    
    var description: String { rawValue }
}
