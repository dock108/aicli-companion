import Foundation

/// Auto-response configuration that gets sent to the server
/// Matches the server-side AutoResponseConfig interface
@available(iOS 16.0, macOS 13.0, *)
public struct ServerAutoResponseConfig: Codable {
    public let enabled: Bool
    public let mode: String
    public let limits: AutoResponseLimits
    public let projectName: String
    public let currentTask: String?
    public let useAI: Bool
    public let minConfidence: Double
    
    public init(
        enabled: Bool,
        mode: String,
        limits: AutoResponseLimits,
        projectName: String,
        currentTask: String? = nil,
        useAI: Bool,
        minConfidence: Double
    ) {
        self.enabled = enabled
        self.mode = mode
        self.limits = limits
        self.projectName = projectName
        self.currentTask = currentTask
        self.useAI = useAI
        self.minConfidence = minConfidence
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct AutoResponseLimits: Codable {
    public let maxMessages: Int?
    public let maxMinutes: Int?
    public let stopOnError: Bool
    public let stopOnCompletion: Bool
    public let requireExplicitCompletion: Bool
    
    public init(
        maxMessages: Int? = nil,
        maxMinutes: Int? = nil,
        stopOnError: Bool,
        stopOnCompletion: Bool,
        requireExplicitCompletion: Bool
    ) {
        self.maxMessages = maxMessages
        self.maxMinutes = maxMinutes
        self.stopOnError = stopOnError
        self.stopOnCompletion = stopOnCompletion
        self.requireExplicitCompletion = requireExplicitCompletion
    }
}

// MARK: - AutoReplySettings -> AutoResponseConfig Conversion
@available(iOS 16.0, macOS 13.0, *)
extension AutoReplySettings {
    /// Convert iOS AutoReplySettings to server AutoResponseConfig
    public func toAutoResponseConfig() -> ServerAutoResponseConfig? {
        guard isEnabled else { return nil }
        
        let limits = AutoResponseLimits(
            maxMessages: messageLimits.enabled ? messageLimits.maxMessages : nil,
            maxMinutes: timeLimits.enabled ? timeLimits.minutes : nil,
            stopOnError: smartStopSettings.stopOnErrors,
            stopOnCompletion: smartStopSettings.stopOnCompletion,
            requireExplicitCompletion: smartStopSettings.requireExplicitCompletion
        )
        
        return ServerAutoResponseConfig(
            enabled: true,
            mode: mode.serverValue,
            limits: limits,
            projectName: projectName,
            currentTask: nil, // Could be extracted from context in the future
            useAI: useAI,
            minConfidence: minConfidence
        )
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension AutoReplyMode {
    /// Server-compatible mode string
    var serverValue: String {
        switch self {
        case .smartStop:
            return "smart_stop"
        case .untilCompletion:
            return "until_completion"
        case .timeBased:
            return "time_based"
        case .messageBased:
            return "message_based"
        case .hybrid:
            return "hybrid"
        }
    }
}
