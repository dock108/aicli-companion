import Foundation
import CloudKit

// MARK: - Enhanced Auto-Reply Settings

@available(iOS 16.0, macOS 13.0, *)
public struct AutoReplySettings: Codable, Identifiable, Hashable {
    public let id: UUID
    public let projectId: UUID
    public let projectName: String
    
    // Basic Settings
    public var isEnabled: Bool = false
    public var mode: AutoReplyMode = .smartStop
    public var useAI: Bool = true
    public var minConfidence: Double = 0.7
    
    // Mode-Specific Settings
    public var smartStopSettings: SmartStopSettings
    public var timeLimits: TimeLimits
    public var messageLimits: MessageLimits
    public var hybridSettings: HybridSettings
    
    // Advanced Settings
    public var allowOverride: Bool = true
    public var requireConfirmation: Bool = false
    public var notifyOnStop: Bool = true
    public var saveHistory: Bool = true
    public var learningEnabled: Bool = true
    
    // Metadata
    public var lastModified: Date = Date()
    public var deviceId: String = ""
    public var version: Int = 1
    
    public init(
        projectId: UUID,
        projectName: String,
        id: UUID = UUID()
    ) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.smartStopSettings = SmartStopSettings()
        self.timeLimits = TimeLimits()
        self.messageLimits = MessageLimits()
        self.hybridSettings = HybridSettings()
        #if os(iOS)
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        #else
        self.deviceId = ""
        #endif
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(projectId)
        hasher.combine(lastModified)
    }
    
    public static func == (lhs: AutoReplySettings, rhs: AutoReplySettings) -> Bool {
        lhs.id == rhs.id && lhs.lastModified == rhs.lastModified
    }
}

// MARK: - Auto Reply Modes

@available(iOS 16.0, macOS 13.0, *)
public enum AutoReplyMode: String, CaseIterable, Codable {
    case smartStop = "smart_stop"
    case untilCompletion = "until_completion"
    case timeBased = "timed"
    case messageBased = "message_count"
    case hybrid = "hybrid"
    
    public var displayName: String {
        switch self {
        case .smartStop: return "Smart Stop"
        case .untilCompletion: return "Until Completion"
        case .timeBased: return "Time-Based"
        case .messageBased: return "Message-Based"
        case .hybrid: return "Hybrid"
        }
    }
    
    public var description: String {
        switch self {
        case .smartStop: return "Automatically stops on completion, errors, or when stuck"
        case .untilCompletion: return "Continues until task is explicitly marked complete"
        case .timeBased: return "Works for a specified duration"
        case .messageBased: return "Sends up to a specified number of messages"
        case .hybrid: return "Combines multiple stop conditions"
        }
    }
    
    public var icon: String {
        switch self {
        case .smartStop: return "brain.head.profile"
        case .untilCompletion: return "flag.checkered"
        case .timeBased: return "clock"
        case .messageBased: return "number"
        case .hybrid: return "slider.horizontal.3"
        }
    }
}

// MARK: - Smart Stop Settings

@available(iOS 16.0, macOS 13.0, *)
public struct SmartStopSettings: Codable, Hashable {
    public var stuckDetectionSensitivity: Int = 3 // 1-5 scale
    public var stopOnErrors: Bool = true
    public var stopOnCompletion: Bool = true
    public var maxLoopAttempts: Int = 5
    public var requireExplicitCompletion: Bool = false
    
    public init() {}
    
    public var stuckThreshold: Double {
        // Convert sensitivity to similarity threshold
        switch stuckDetectionSensitivity {
        case 1: return 0.95 // Very sensitive
        case 2: return 0.90
        case 3: return 0.85 // Default
        case 4: return 0.80
        case 5: return 0.75 // Less sensitive
        default: return 0.85
        }
    }
}

// MARK: - Time Limits

@available(iOS 16.0, macOS 13.0, *)
public struct TimeLimits: Codable, Hashable {
    public var enabled: Bool = false
    public var minutes: Int = 30
    public var extendOnProgress: Bool = true
    public var warningMinutes: Int = 5
    
    public init() {}
    
    public var timeInterval: TimeInterval {
        return TimeInterval(minutes * 60)
    }
    
    public var warningInterval: TimeInterval {
        return TimeInterval(warningMinutes * 60)
    }
    
    public var estimatedMessages: Int {
        // Rough estimate: 2-3 messages per minute
        return minutes * 2
    }
}

// MARK: - Message Limits

@available(iOS 16.0, macOS 13.0, *)
public struct MessageLimits: Codable, Hashable {
    public var enabled: Bool = false
    public var maxMessages: Int = 20
    public var countOnlySuccessful: Bool = true
    public var warningCount: Int = 5
    
    public init() {}
    
    public var warningThreshold: Int {
        return max(1, maxMessages - warningCount)
    }
}

// MARK: - Hybrid Settings

@available(iOS 16.0, macOS 13.0, *)
public struct HybridSettings: Codable, Hashable {
    public var enableTimeLimit: Bool = true
    public var enableMessageLimit: Bool = true
    public var enableSmartStop: Bool = true
    public var priority: StopPriority = .firstToTrigger
    
    public init() {}
}

@available(iOS 16.0, macOS 13.0, *)
public enum StopPriority: String, Codable, CaseIterable {
    case firstToTrigger = "first"
    case allMustTrigger = "all"
    case smartDecision = "smart"
    
    public var displayName: String {
        switch self {
        case .firstToTrigger: return "First Condition"
        case .allMustTrigger: return "All Conditions"
        case .smartDecision: return "Smart Decision"
        }
    }
    
    public var description: String {
        switch self {
        case .firstToTrigger: return "Stop when any condition is met"
        case .allMustTrigger: return "Stop only when all conditions are met"
        case .smartDecision: return "Let AI decide based on context"
        }
    }
}

// MARK: - Auto Reply Session

@available(iOS 16.0, macOS 13.0, *)
public class AutoReplySession: ObservableObject, Identifiable {
    public let id = UUID()
    public let settings: AutoReplySettings
    
    @Published public var isActive: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var messagesSent: Int = 0
    @Published public var startTime: Date?
    @Published public var endTime: Date?
    @Published public var lastResponse: String?
    @Published public var currentStatus: AutoReplySessionStatus = .inactive
    @Published public var confidence: Double = 0.0
    @Published public var stopReason: StopReason?
    
    public init(settings: AutoReplySettings) {
        self.settings = settings
    }
    
    // MARK: - Computed Properties
    
    public var isTimeLimited: Bool {
        return settings.mode == .timeBased ||
               (settings.mode == .hybrid && settings.hybridSettings.enableTimeLimit)
    }
    
    public var isMessageLimited: Bool {
        return settings.mode == .messageBased ||
               (settings.mode == .hybrid && settings.hybridSettings.enableMessageLimit)
    }
    
    public var elapsedTime: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    public var remainingTime: TimeInterval? {
        guard isTimeLimited, let startTime = startTime else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let total = settings.timeLimits.timeInterval
        return max(0, total - elapsed)
    }
    
    public var remainingMessages: Int? {
        guard isMessageLimited else { return nil }
        let limit = settings.messageLimits.maxMessages
        return max(0, limit - messagesSent)
    }
    
    public var progress: SessionProgress? {
        switch settings.mode {
        case .timeBased:
            guard let remaining = remainingTime else { return nil }
            let total = settings.timeLimits.timeInterval
            let current = total - remaining
            return SessionProgress(current: current, total: total, unit: .time)
            
        case .messageBased:
            let total = Double(settings.messageLimits.maxMessages)
            let current = Double(messagesSent)
            return SessionProgress(current: current, total: total, unit: .messages)
            
        case .hybrid:
            // Show the most restrictive progress
            var progresses: [SessionProgress] = []
            
            if settings.hybridSettings.enableTimeLimit,
               let timeProgress = remainingTime {
                let total = settings.timeLimits.timeInterval
                let current = total - timeProgress
                progresses.append(SessionProgress(current: current, total: total, unit: .time))
            }
            
            if settings.hybridSettings.enableMessageLimit {
                let total = Double(settings.messageLimits.maxMessages)
                let current = Double(messagesSent)
                progresses.append(SessionProgress(current: current, total: total, unit: .messages))
            }
            
            return progresses.max { $0.percentage < $1.percentage }
            
        default:
            return nil
        }
    }
    
    // MARK: - Session Control
    
    public func start() {
        guard !isActive else { return }
        
        isActive = true
        isPaused = false
        messagesSent = 0
        startTime = Date()
        endTime = nil
        stopReason = nil
        currentStatus = .active
        
        // Auto-reply session started
    }
    
    public func pause() {
        guard isActive && !isPaused else { return }
        
        isPaused = true
        currentStatus = .paused
        
        // Auto-reply session paused
    }
    
    public func resume() {
        guard isActive && isPaused else { return }
        
        isPaused = false
        currentStatus = .active
        
        // Auto-reply session resumed
    }
    
    public func stop(reason: StopReason = .manual) {
        guard isActive else { return }
        
        isActive = false
        isPaused = false
        endTime = Date()
        stopReason = reason
        currentStatus = .completed
        
        // Auto-reply session stopped
    }
    
    public func recordMessage(response: String, confidence: Double) {
        messagesSent += 1
        lastResponse = response
        self.confidence = confidence
    }
    
    public func shouldStop() -> StopReason? {
        guard isActive && !isPaused else { return nil }
        
        // Check time limits
        if isTimeLimited, let remaining = remainingTime, remaining <= 0 {
            return .timeLimit
        }
        
        // Check message limits
        if isMessageLimited, let remaining = remainingMessages, remaining <= 0 {
            return .messageLimit
        }
        
        return nil
    }
}

// MARK: - Supporting Types

@available(iOS 16.0, macOS 13.0, *)
public enum AutoReplySessionStatus: String, Codable {
    case inactive
    case active
    case paused
    case completed
    case error
    
    public var displayName: String {
        switch self {
        case .inactive: return "Inactive"
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }
    
    public var color: String {
        switch self {
        case .inactive: return "gray"
        case .active: return "green"
        case .paused: return "orange"
        case .completed: return "blue"
        case .error: return "red"
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
public enum StopReason: String, Codable {
    case manual = "manual"
    case timeLimit = "time_limit"
    case messageLimit = "message_limit"
    case completion = "completion"
    case error = "error"
    case showstopper = "showstopper"
    case stuck = "stuck"
    case lowConfidence = "low_confidence"
    
    public var displayName: String {
        switch self {
        case .manual: return "Manual Stop"
        case .timeLimit: return "Time Limit Reached"
        case .messageLimit: return "Message Limit Reached"
        case .completion: return "Task Completed"
        case .error: return "Error Occurred"
        case .showstopper: return "Critical Issue"
        case .stuck: return "Progress Stalled"
        case .lowConfidence: return "Low Confidence"
        }
    }
    
    public var description: String {
        switch self {
        case .manual: return "User manually stopped the session"
        case .timeLimit: return "Maximum time limit was reached"
        case .messageLimit: return "Maximum message count was reached"
        case .completion: return "Task was marked as complete"
        case .error: return "An error occurred that prevented continuation"
        case .showstopper: return "A critical issue was detected"
        case .stuck: return "No progress was being made"
        case .lowConfidence: return "Response confidence was too low"
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct SessionProgress {
    public let current: Double
    public let total: Double
    public let unit: ProgressUnit
    
    public var percentage: Double {
        guard total > 0 else { return 0 }
        return min(1.0, current / total)
    }
    
    public var displayText: String {
        switch unit {
        case .time:
            let minutes = Int(current / 60)
            let totalMinutes = Int(total / 60)
            return "\(minutes)/\(totalMinutes) min"
        case .messages:
            return "\(Int(current))/\(Int(total)) messages"
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
public enum ProgressUnit {
    case time
    case messages
}

// MARK: - CloudKit Extensions

@available(iOS 16.0, macOS 13.0, *)
extension AutoReplySettings {
    /// Convert to CloudKit record
    public func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "AutoReplySettings", recordID: CKRecord.ID(recordName: id.uuidString))
        
        record["projectId"] = projectId.uuidString
        record["projectName"] = projectName
        record["isEnabled"] = isEnabled
        record["mode"] = mode.rawValue
        record["useAI"] = useAI
        record["minConfidence"] = minConfidence
        record["allowOverride"] = allowOverride
        record["requireConfirmation"] = requireConfirmation
        record["notifyOnStop"] = notifyOnStop
        record["saveHistory"] = saveHistory
        record["learningEnabled"] = learningEnabled
        record["lastModified"] = lastModified
        record["deviceId"] = deviceId
        record["version"] = version
        
        // Encode complex objects as JSON
        if let smartStopData = try? JSONEncoder().encode(smartStopSettings) {
            record["smartStopSettings"] = smartStopData
        }
        if let timeLimitsData = try? JSONEncoder().encode(timeLimits) {
            record["timeLimits"] = timeLimitsData
        }
        if let messageLimitsData = try? JSONEncoder().encode(messageLimits) {
            record["messageLimits"] = messageLimitsData
        }
        if let hybridSettingsData = try? JSONEncoder().encode(hybridSettings) {
            record["hybridSettings"] = hybridSettingsData
        }
        
        return record
    }
    
    /// Create from CloudKit record
    public static func from(ckRecord: CKRecord) throws -> AutoReplySettings {
        guard let projectIdString = ckRecord["projectId"] as? String,
              let projectId = UUID(uuidString: projectIdString),
              let projectName = ckRecord["projectName"] as? String else {
            throw AutoReplyError.invalidCloudKitRecord
        }
        
        var settings = AutoReplySettings(projectId: projectId, projectName: projectName)
        
        if let recordId = UUID(uuidString: ckRecord.recordID.recordName) {
            settings = AutoReplySettings(projectId: projectId, projectName: projectName, id: recordId)
        }
        
        settings.isEnabled = ckRecord["isEnabled"] as? Bool ?? false
        settings.useAI = ckRecord["useAI"] as? Bool ?? true
        settings.minConfidence = ckRecord["minConfidence"] as? Double ?? 0.7
        settings.allowOverride = ckRecord["allowOverride"] as? Bool ?? true
        settings.requireConfirmation = ckRecord["requireConfirmation"] as? Bool ?? false
        settings.notifyOnStop = ckRecord["notifyOnStop"] as? Bool ?? true
        settings.saveHistory = ckRecord["saveHistory"] as? Bool ?? true
        settings.learningEnabled = ckRecord["learningEnabled"] as? Bool ?? true
        settings.lastModified = ckRecord["lastModified"] as? Date ?? Date()
        settings.deviceId = ckRecord["deviceId"] as? String ?? ""
        settings.version = ckRecord["version"] as? Int ?? 1
        
        if let modeString = ckRecord["mode"] as? String,
           let mode = AutoReplyMode(rawValue: modeString) {
            settings.mode = mode
        }
        
        // Decode complex objects from JSON
        if let smartStopData = ckRecord["smartStopSettings"] as? Data,
           let smartStopSettings = try? JSONDecoder().decode(SmartStopSettings.self, from: smartStopData) {
            settings.smartStopSettings = smartStopSettings
        }
        
        if let timeLimitsData = ckRecord["timeLimits"] as? Data,
           let timeLimits = try? JSONDecoder().decode(TimeLimits.self, from: timeLimitsData) {
            settings.timeLimits = timeLimits
        }
        
        if let messageLimitsData = ckRecord["messageLimits"] as? Data,
           let messageLimits = try? JSONDecoder().decode(MessageLimits.self, from: messageLimitsData) {
            settings.messageLimits = messageLimits
        }
        
        if let hybridSettingsData = ckRecord["hybridSettings"] as? Data,
           let hybridSettings = try? JSONDecoder().decode(HybridSettings.self, from: hybridSettingsData) {
            settings.hybridSettings = hybridSettings
        }
        
        return settings
    }
}

@available(iOS 16.0, macOS 13.0, *)
public enum AutoReplyError: Error, LocalizedError {
    case invalidCloudKitRecord
    case syncFailed
    case configurationError
    
    public var errorDescription: String? {
        switch self {
        case .invalidCloudKitRecord:
            return "Invalid CloudKit record format"
        case .syncFailed:
            return "Failed to sync settings with CloudKit"
        case .configurationError:
            return "Invalid configuration"
        }
    }
}
