import Foundation

// MARK: - Claude Response Models
struct AssistantMessageResponse: Codable {
    let content: [MessageContentBlock]
    let messageId: String?
    let sessionId: String?
    let model: String?
    let usage: Usage?
    let stopReason: String?
    let stopSequence: String?
    let type: String
    let role: String
}

struct MessageContentBlock: Codable {
    let type: String
    let text: String?
    let source: AnyCodable?
    let name: String?
    let input: AnyCodable?
    let toolUseId: String?
    let content: String?
    let isError: Bool?
}

struct ToolUseResponse: Codable {
    let id: String
    let name: String
    let input: [String: AnyCodable]
}

struct ToolResultResponse: Codable {
    let toolUseId: String
    let content: [MessageContentBlock]
    let isError: Bool?
}

struct ConversationResultResponse: Codable {
    let success: Bool
    let result: String?
    let error: String?
    let sessionId: String?
    let claudeSessionId: String?
    let duration: Double?
    let usage: Usage?
}

struct WorkingDirectorySetResponse: Codable {
    let path: String
    let success: Bool
}

struct ClaudeCommandResponse: Codable {
    let output: String
    let exitCode: Int
    let error: String?
}

struct GetMessageHistoryResponse: Codable {
    let messages: [HistoryMessage]
    let total: Int
    let hasMore: Bool
    let sessionMetadata: SessionMetadata?
}

struct HistoryMessage: Codable {
    let id: String
    let content: String
    let sender: MessageSender
    let timestamp: Date
    let messageContent: [MessageContent]?
}

struct MessageContent: Codable {
    let type: String
    let text: String?
}

public struct SessionMetadata: Codable {
    public let sessionId: String
    public let startTime: Date
    public let messageCount: Int
    
    public init(sessionId: String, startTime: Date, messageCount: Int) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.messageCount = messageCount
    }
}

struct ClearChatResponse: Codable {
    let success: Bool
    let message: String?
    let clearedMessageCount: Int?
    let timestamp: Date
}

struct ProgressResponse: Codable {
    let message: String
    let progress: Double?
    let stage: String?
    let estimatedTimeRemaining: TimeInterval?
}

// MARK: - Utility Models
struct ProgressInfo {
    let message: String
    let progress: Double?
    let stage: String?
    let estimatedTimeRemaining: TimeInterval?
    let isIndeterminate: Bool
    
    init(message: String, progress: Double? = nil, stage: String? = nil, estimatedTimeRemaining: TimeInterval? = nil, isIndeterminate: Bool = false) {
        self.message = message
        self.progress = progress
        self.stage = stage
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.isIndeterminate = isIndeterminate
    }
    
    init(from response: ProgressResponse) {
        self.message = response.message
        self.progress = response.progress
        self.stage = response.stage
        self.estimatedTimeRemaining = response.estimatedTimeRemaining
        self.isIndeterminate = response.progress == nil
    }
}

public struct AnyCodable: Codable {
    public let value: Any
    
    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = ()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self.value {
        case is Void:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let anyArray = array.map { AnyCodable($0) }
            try container.encode(anyArray)
        case let dictionary as [String: Any]:
            let anyDictionary = dictionary.mapValues { AnyCodable($0) }
            try container.encode(anyDictionary)
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(self.value, context)
        }
    }
}

// MARK: - Device Registration (Push Notifications)
struct RegisterDeviceRequest: Codable {
    let deviceToken: String
    let deviceType: String
    let appVersion: String
}

struct DeviceRegisteredResponse: Codable {
    let success: Bool
    let deviceId: String?
    let message: String?
}
