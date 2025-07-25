import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    var content: String
    let sender: MessageSender
    let timestamp: Date
    let type: MessageType
    var metadata: ClaudeMessageMetadata?
    var streamingState: StreamingState?
    let requestId: String?
    let richContent: RichContent?

    init(id: UUID = UUID(), content: String, sender: MessageSender, timestamp: Date = Date(), type: MessageType = .text, metadata: ClaudeMessageMetadata? = nil, streamingState: StreamingState? = nil, requestId: String? = nil, richContent: RichContent? = nil) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.type = type
        self.metadata = metadata
        self.streamingState = streamingState
        self.requestId = requestId
        self.richContent = richContent
    }
}

// MARK: - Rich Content Models

struct RichContent: Codable {
    let contentType: RichContentType
    let data: RichContentData
}

enum RichContentType: String, Codable {
    case codeBlock = "code_block"
    case fileContent = "file_content"
    case commandOutput = "command_output"
    case toolResult = "tool_result"
    case markdown = "markdown"
}

enum RichContentData: Codable {
    case codeBlock(CodeBlockData)
    case fileContent(FileContentData)
    case commandOutput(CommandOutputData)
    case toolResult(ToolResultData)
    case markdown(MarkdownData)
}

struct CodeBlockData: Codable {
    let code: String
    let language: String?
    let filename: String?
    let startLine: Int?
    let endLine: Int?
}

struct FileContentData: Codable {
    let filename: String
    let filePath: String
    let content: String
    let language: String?
    let lineCount: Int
    let size: Int?
}

struct CommandOutputData: Codable {
    let command: String
    let output: String
    let exitCode: Int?
    let workingDirectory: String?
    let duration: TimeInterval?
}

struct ToolResultData: Codable {
    let toolName: String
    let input: [String: AnyCodable]?
    let output: String
    let success: Bool
    let error: String?
    let duration: TimeInterval?
}

struct MarkdownData: Codable {
    let markdown: String
    let renderMode: MarkdownRenderMode
}

enum MarkdownRenderMode: String, Codable {
    case full = "full"
    case inline = "inline"
    case stripped = "stripped"
}

enum MessageSender: String, Codable, CaseIterable {
    case user = "user"
    case claude = "claude"
    case system = "system"
}

enum MessageType: String, Codable, CaseIterable {
    case text = "text"
    case markdown = "markdown"
    case code = "code"
    case fileContent = "file_content"
    case commandOutput = "command_output"
    case toolResult = "tool_result"
    case error = "error"
    case permission = "permission"
    case toolUse = "tool_use"
    case system = "system"
}

enum StreamingState: String, Codable, CaseIterable {
    case pending = "pending"
    case streaming = "streaming"
    case completed = "completed"
    case failed = "failed"
}

struct ClaudeMessageMetadata: Codable {
    let sessionId: String
    let duration: TimeInterval
    let cost: Double?
    let tools: [String]?

    init(sessionId: String, duration: TimeInterval, cost: Double? = nil, tools: [String]? = nil) {
        self.sessionId = sessionId
        self.duration = duration
        self.cost = cost
        self.tools = tools
    }
}

// MARK: - Claude Code API Response Models

struct ClaudeCodeResponse: Codable {
    let type: String
    let subtype: String
    let isError: Bool
    let duration: TimeInterval
    let durationApiMs: TimeInterval?
    let numTurns: Int
    let result: String
    let sessionId: String
    let totalCost: Double?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case type, subtype, result
        case isError = "is_error"
        case duration = "duration_ms"
        case durationApiMs = "duration_api_ms"
        case numTurns = "num_turns"
        case sessionId = "session_id"
        case totalCost = "total_cost_usd"
        case usage
    }
}

struct Usage: Codable {
    let inputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    let outputTokens: Int
    let serverToolUse: ServerToolUse?
    let serviceTier: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case serverToolUse = "server_tool_use"
        case serviceTier = "service_tier"
    }
}

struct ServerToolUse: Codable {
    let webSearchRequests: Int

    enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
    }
}

// MARK: - Connection Models

struct ServerConnection: Codable {
    let address: String
    let port: Int
    let authToken: String?
    let isSecure: Bool

    init(address: String, port: Int, authToken: String? = nil, isSecure: Bool = false) {
        self.address = address
        self.port = port
        self.authToken = authToken
        self.isSecure = isSecure
    }

    var url: URL? {
        let scheme = isSecure ? "https" : "http"
        
        // Handle IPv6 addresses by wrapping them in brackets
        let formattedAddress: String
        if address.contains(":") && !address.hasPrefix("[") {
            // This is likely an IPv6 address that needs brackets
            formattedAddress = "[\(address)]"
        } else {
            formattedAddress = address
        }
        
        return URL(string: "\(scheme)://\(formattedAddress):\(port)")
    }

    var wsURL: URL? {
        let scheme = isSecure ? "wss" : "ws"
        
        // Handle IPv6 addresses by wrapping them in brackets
        let formattedAddress: String
        if address.contains(":") && !address.hasPrefix("[") {
            // This is likely an IPv6 address that needs brackets
            formattedAddress = "[\(address)]"
        } else {
            formattedAddress = address
        }
        
        return URL(string: "\(scheme)://\(formattedAddress):\(port)/ws")
    }
}

struct DiscoveredServer {
    let name: String
    let address: String
    let port: Int
    let isSecure: Bool
}

// MARK: - Error Types

// MARK: - WebSocket Message Models

struct WebSocketMessage: Codable {
    let type: WebSocketMessageType
    let requestId: String?
    let timestamp: Date
    let data: Data

    enum Data: Codable {
        case ask(AskRequest)
        case streamStart(StreamStartRequest)
        case streamSend(StreamSendRequest)
        case permission(PermissionResponse)
        case streamClose(StreamCloseRequest)
        case ping(PingRequest)
        case subscribe(SubscribeRequest)
        case setWorkingDirectory(SetWorkingDirectoryRequest)
        case welcome(WelcomeResponse)
        case askResponse(AskResponseData)
        case streamStarted(StreamStartedResponse)
        case streamData(StreamDataResponse)
        case streamToolUse(StreamToolUseResponse)
        case permissionRequest(PermissionRequestData)
        case streamComplete(StreamCompleteResponse)
        case error(ErrorResponse)
        case sessionStatus(SessionStatusResponse)
        case pong(PongResponse)

        // New rich message types
        case systemInit(SystemInitResponse)
        case assistantMessage(AssistantMessageResponse)
        case toolUse(ToolUseResponse)
        case toolResult(ToolResultResponse)
        case conversationResult(ConversationResultResponse)
        case workingDirectorySet(WorkingDirectorySetResponse)
    }
    
    // Custom decoding to handle server message format
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(WebSocketMessageType.self, forKey: .type)
        self.requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        
        // Create a decoder for the data field
        let dataDecoder = try container.superDecoder(forKey: .data)
        
        // Decode data based on message type
        switch type {
        case .welcome:
            self.data = .welcome(try WelcomeResponse(from: dataDecoder))
        case .askResponse:
            self.data = .askResponse(try AskResponseData(from: dataDecoder))
        case .streamStarted:
            self.data = .streamStarted(try StreamStartedResponse(from: dataDecoder))
        case .streamData:
            self.data = .streamData(try StreamDataResponse(from: dataDecoder))
        case .streamToolUse:
            self.data = .streamToolUse(try StreamToolUseResponse(from: dataDecoder))
        case .permissionRequest:
            self.data = .permissionRequest(try PermissionRequestData(from: dataDecoder))
        case .streamComplete:
            self.data = .streamComplete(try StreamCompleteResponse(from: dataDecoder))
        case .error:
            self.data = .error(try ErrorResponse(from: dataDecoder))
        case .sessionStatus:
            self.data = .sessionStatus(try SessionStatusResponse(from: dataDecoder))
        case .pong:
            self.data = .pong(try PongResponse(from: dataDecoder))
        case .systemInit:
            self.data = .systemInit(try SystemInitResponse(from: dataDecoder))
        case .assistantMessage:
            self.data = .assistantMessage(try AssistantMessageResponse(from: dataDecoder))
        case .toolUse:
            self.data = .toolUse(try ToolUseResponse(from: dataDecoder))
        case .toolResult:
            self.data = .toolResult(try ToolResultResponse(from: dataDecoder))
        case .conversationResult:
            self.data = .conversationResult(try ConversationResultResponse(from: dataDecoder))
        case .workingDirectorySet:
            self.data = .workingDirectorySet(try WorkingDirectorySetResponse(from: dataDecoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Unsupported message type for decoding: \(type)")
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, requestId, timestamp, data
    }
}

enum WebSocketMessageType: String, Codable {
    // Client → Server
    case ask = "ask"
    case streamStart = "streamStart"
    case streamSend = "streamSend"
    case permission = "permission"
    case streamClose = "streamClose"
    case ping = "ping"
    case subscribe = "subscribe"
    case setWorkingDirectory = "setWorkingDirectory"

    // Server → Client
    case welcome = "welcome"
    case askResponse = "askResponse"
    case streamStarted = "streamStarted"
    case streamData = "streamData"
    case streamToolUse = "streamToolUse"
    case permissionRequest = "permissionRequest"
    case streamComplete = "streamComplete"
    case error = "error"
    case sessionStatus = "sessionStatus"
    case pong = "pong"

    // New rich message types from enhanced server
    case systemInit = "systemInit"
    case assistantMessage = "assistantMessage"
    case toolUse = "toolUse"
    case toolResult = "toolResult"
    case conversationResult = "conversationResult"
    case workingDirectorySet = "workingDirectorySet"
}

// MARK: - Client Request Models

struct AskRequest: Codable {
    let prompt: String
    let workingDirectory: String?
    let options: AskOptions?
}

struct AskOptions: Codable {
    let format: String
    let timeout: TimeInterval
}

struct StreamStartRequest: Codable {
    let prompt: String
    let workingDirectory: String?
    let options: StreamOptions?
}

struct StreamOptions: Codable {
    let sessionName: String?
    let preserveContext: Bool
}

struct StreamSendRequest: Codable {
    let sessionId: String
    let prompt: String
}

struct PermissionResponse: Codable {
    let sessionId: String
    let response: String
    let remember: Bool
}

struct StreamCloseRequest: Codable {
    let sessionId: String
    let reason: String
}

struct PingRequest: Codable {}

struct SubscribeRequest: Codable {
    let events: [String]
    let sessionIds: [String]?
}

struct SetWorkingDirectoryRequest: Codable {
    let workingDirectory: String
}

// MARK: - Server Response Models

struct WelcomeResponse: Codable {
    let clientId: String
    let serverVersion: String
    let claudeCodeVersion: String?
    let capabilities: [String]
    let maxSessions: Int
}

struct AskResponseData: Codable {
    let success: Bool
    let response: ClaudeCodeResponse?
    let error: String?
}

struct StreamStartedResponse: Codable {
    let sessionId: String
    let sessionName: String?
    let workingDirectory: String
}

struct StreamDataResponse: Codable {
    let sessionId: String
    let streamType: String
    let content: StreamContent
    let isComplete: Bool
}

struct StreamContent: Codable {
    let type: String
    let text: String?
    let data: [String: AnyCodable]?
}

struct StreamToolUseResponse: Codable {
    let sessionId: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let status: String
}

struct PermissionRequestData: Codable {
    let sessionId: String
    let prompt: String
    let options: [String]
    let defaultOption: String
    let timeout: TimeInterval
}

struct StreamCompleteResponse: Codable {
    let sessionId: String
    let finalResult: String
    let duration: TimeInterval
    let cost: Double?
    let usage: Usage?
}

struct ErrorResponse: Codable {
    let code: String
    let message: String
    let details: [String: AnyCodable]?
}

struct SessionStatusResponse: Codable {
    let sessionId: String
    let status: String
    let lastActivity: Date
    let messageCount: Int
    let totalCost: Double?
}

struct PongResponse: Codable {
    let serverTime: Date
}

// MARK: - Rich Message Response Models

struct SystemInitResponse: Codable {
    let type: String
    let sessionId: String?
    let workingDirectory: String?
    let availableTools: [String]
    let mcpServers: [String]
    let model: String?
    let timestamp: Date
}

struct AssistantMessageResponse: Codable {
    let type: String
    let messageId: String?
    let content: [MessageContentBlock]
    let model: String?
    let usage: Usage?
    let timestamp: Date
}

struct MessageContentBlock: Codable {
    let type: String
    let text: String?
    let toolName: String?
    let toolInput: [String: AnyCodable]?
    let toolId: String?

    enum CodingKeys: String, CodingKey {
        case type, text
        case toolName = "name"
        case toolInput = "input"
        case toolId = "id"
    }
}

struct ToolUseResponse: Codable {
    let type: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let toolId: String
    let timestamp: Date
}

struct ToolResultResponse: Codable {
    let type: String
    let toolName: String
    let toolId: String
    let result: String?
    let success: Bool
    let error: String?
    let timestamp: Date
}

struct ConversationResultResponse: Codable {
    let type: String
    let success: Bool
    let result: String?
    let sessionId: String?
    let duration: TimeInterval?
    let cost: Double?
    let usage: Usage?
    let timestamp: Date
}

struct WorkingDirectorySetResponse: Codable {
    let workingDirectory: String
    let success: Bool
}

// MARK: - Helper Types

struct AnyCodable: Codable {
    let value: Any

    init<T>(_ value: T) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

enum ClaudeCompanionError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case serverNotFound
    case invalidResponse
    case networkError(Error)
    case jsonParsingError(Error)
    case webSocketError(String)
    case sessionNotFound(String)
    case permissionDenied
    case rateLimited
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "Authentication failed. Please check your token."
        case .serverNotFound:
            return "Claude Code server not found"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .jsonParsingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .webSocketError(let message):
            return "WebSocket error: \(message)"
        case .sessionNotFound(let sessionId):
            return "Session not found: \(sessionId)"
        case .permissionDenied:
            return "Permission denied"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .timeout:
            return "Request timed out"
        }
    }
}
