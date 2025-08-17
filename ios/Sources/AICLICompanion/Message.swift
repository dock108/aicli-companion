import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    var content: String
    let sender: MessageSender
    let timestamp: Date
    let type: MessageType
    var metadata: AICLIMessageMetadata?
    var streamingState: StreamingState?
    let requestId: String?
    let richContent: RichContent?
    
    // CloudKit removed - local storage only
    var readByDevices: [String] = []
    var deletedByDevices: [String] = []
    var syncedAt: Date?
    var needsSync: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case id, content, sender, timestamp, type, metadata, streamingState, requestId, richContent
    }

    init(id: UUID = UUID(), content: String, sender: MessageSender, timestamp: Date = Date(), type: MessageType = .text, metadata: AICLIMessageMetadata? = nil, streamingState: StreamingState? = nil, requestId: String? = nil, richContent: RichContent? = nil, attachments: [AttachmentData]? = nil) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.type = type
        self.metadata = metadata
        self.streamingState = streamingState
        self.requestId = requestId
        
        // If attachments are provided, create rich content for them
        if let attachments = attachments, !attachments.isEmpty {
            let attachmentsData = AttachmentsData(attachments: attachments.map { attachment in
                AttachmentInfo(
                    id: UUID(),
                    name: attachment.name,
                    mimeType: attachment.mimeType,
                    size: attachment.size,
                    base64Data: attachment.data.base64EncodedString(),
                    url: nil,
                    thumbnailBase64: nil
                )
            })
            self.richContent = RichContent(
                contentType: .attachments,
                data: .attachments(attachmentsData)
            )
        } else {
            self.richContent = richContent
        }
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
    case attachments = "attachments"
}

enum RichContentData: Codable {
    case codeBlock(CodeBlockData)
    case fileContent(FileContentData)
    case commandOutput(CommandOutputData)
    case toolResult(ToolResultData)
    case markdown(MarkdownData)
    case attachments(AttachmentsData)
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
    case full
    case inline
    case stripped
}

struct AttachmentsData: Codable {
    let attachments: [AttachmentInfo]
}

struct AttachmentInfo: Codable, Identifiable {
    let id: UUID
    let name: String
    let mimeType: String
    let size: Int
    let base64Data: String? // For small files
    let url: String? // For files stored on server
    let thumbnailBase64: String? // For images
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

enum MessageSender: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

enum MessageType: String, Codable, CaseIterable {
    case text
    case markdown
    case code
    case fileContent = "file_content"
    case commandOutput = "command_output"
    case toolResult = "tool_result"
    case error
    case permission
    case toolUse = "tool_use"
    case system
}

enum StreamingState: String, Codable, CaseIterable {
    case pending
    case streaming
    case completed
    case failed
}

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(AICLICompanionError)
    
    static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

struct AICLIMessageMetadata: Codable {
    let sessionId: String
    let duration: TimeInterval
    let cost: Double?
    let tools: [String]?
    let queuedAt: Date?
    let deliveredAt: Date?
    let queuePriority: Int?
    var additionalInfo: [String: Any]?

    init(sessionId: String, duration: TimeInterval, cost: Double? = nil, tools: [String]? = nil, queuedAt: Date? = nil, deliveredAt: Date? = nil, queuePriority: Int? = nil, additionalInfo: [String: Any]? = nil) {
        self.sessionId = sessionId
        self.duration = duration
        self.cost = cost
        self.tools = tools
        self.queuedAt = queuedAt
        self.deliveredAt = deliveredAt
        self.queuePriority = queuePriority
        self.additionalInfo = additionalInfo
    }
    
    // Custom coding to handle additionalInfo
    enum CodingKeys: String, CodingKey {
        case sessionId, duration, cost, tools, queuedAt, deliveredAt, queuePriority, additionalInfo
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        tools = try container.decodeIfPresent([String].self, forKey: .tools)
        queuedAt = try container.decodeIfPresent(Date.self, forKey: .queuedAt)
        deliveredAt = try container.decodeIfPresent(Date.self, forKey: .deliveredAt)
        queuePriority = try container.decodeIfPresent(Int.self, forKey: .queuePriority)
        
        // Decode additionalInfo as AnyCodable
        if let additionalData = try? container.decodeIfPresent([String: AnyCodable].self, forKey: .additionalInfo) {
            additionalInfo = additionalData.mapValues { $0.value }
        } else {
            additionalInfo = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(cost, forKey: .cost)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(queuedAt, forKey: .queuedAt)
        try container.encodeIfPresent(deliveredAt, forKey: .deliveredAt)
        try container.encodeIfPresent(queuePriority, forKey: .queuePriority)
        
        // Encode additionalInfo as AnyCodable
        if let additionalInfo = additionalInfo {
            let encodableInfo = additionalInfo.mapValues { AnyCodable($0) }
            try container.encode(encodableInfo, forKey: .additionalInfo)
        }
    }
}

// MARK: - Status Message Metadata

struct StatusMetadata: Codable {
    let statusType: String // "progress", "tools", "completion", "interruption"
    let stage: String? // "creating", "thinking", "working", "completed", etc.
    let duration: Double? // Duration in seconds
    let tokens: Int? // Token count
    let tools: [String]? // Tools being used
    let canInterrupt: Bool // Whether the operation can be interrupted
    let originalText: String // Original status text from Claude CLI
    
    init(statusType: String, stage: String? = nil, duration: Double? = nil, tokens: Int? = nil, tools: [String]? = nil, canInterrupt: Bool = false, originalText: String) {
        self.statusType = statusType
        self.stage = stage
        self.duration = duration
        self.tokens = tokens
        self.tools = tools
        self.canInterrupt = canInterrupt
        self.originalText = originalText
    }
}

// MARK: - AICLI API Response Models

struct AICLIResponse: Codable {
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

struct Deliverable: Codable {
    let type: String
    let language: String?
    let code: String?
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
        if address.contains(":") && !address.hasPrefix("[") && !address.contains(".") {
            // This is likely an IPv6 address that needs brackets
            // (contains colons, no brackets, and no dots which would indicate a domain)
            formattedAddress = "[\(address)]"
        } else {
            formattedAddress = address
        }
        
        // Don't include port if it's the default for the scheme
        let defaultPort = isSecure ? 443 : 80
        if port == defaultPort {
            return URL(string: "\(scheme)://\(formattedAddress)")
        } else {
            return URL(string: "\(scheme)://\(formattedAddress):\(port)")
        }
    }

    var wsURL: URL? {
        let scheme = isSecure ? "wss" : "ws"
        
        // Handle IPv6 addresses by wrapping them in brackets
        let formattedAddress: String
        if address.contains(":") && !address.hasPrefix("[") && !address.contains(".") {
            // This is likely an IPv6 address that needs brackets
            // (contains colons, no brackets, and no dots which would indicate a domain)
            formattedAddress = "[\(address)]"
        } else {
            formattedAddress = address
        }
        
        // Don't include port if it's the default for the scheme
        let defaultPort = isSecure ? 443 : 80
        if port == defaultPort {
            return URL(string: "\(scheme)://\(formattedAddress)/ws")
        } else {
            return URL(string: "\(scheme)://\(formattedAddress):\(port)/ws")
        }
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
        case claudeCommand(ClaudeCommandRequest)
        case registerDevice(RegisterDeviceRequest)
        case getMessageHistory(GetMessageHistoryRequest)
        case acknowledgeMessages(AcknowledgeMessagesRequest)
        case clearChat(ClearChatRequest)
        case welcome(WelcomeResponse)
        case askResponse(AskResponseData)
        case streamStarted(StreamStartedResponse)
        case streamData(StreamDataResponse)
        case streamChunk(StreamChunkResponse)
        case streamToolUse(StreamToolUseResponse)
        case permissionRequest(PermissionRequestData)
        case streamComplete(StreamCompleteResponse)
        case error(ErrorResponse)
        case sessionStatus(SessionStatusResponse)
        case pong(PongResponse)
        case claudeResponse(ClaudeCommandResponse)
        case subscribed(SubscribedResponse)

        // New rich message types
        case systemInit(SystemInitResponse)
        case assistantMessage(AssistantMessageResponse)
        case toolUse(ToolUseResponse)
        case toolResult(ToolResultResponse)
        case conversationResult(ConversationResultResponse)
        case workingDirectorySet(WorkingDirectorySetResponse)
        case progress(ProgressResponse)
        case deviceRegistered(DeviceRegisteredResponse)
        case getMessageHistoryResponse(GetMessageHistoryResponse)
        case clearChatResponse(ClearChatResponse)
    }
    
    // Memberwise initializer for creating messages programmatically
    init(type: WebSocketMessageType, requestId: String?, timestamp: Date, data: Data) {
        self.type = type
        self.requestId = requestId
        self.timestamp = timestamp
        self.data = data
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
        case .progress:
            self.data = .progress(try ProgressResponse(from: dataDecoder))
        case .claudeResponse:
            self.data = .claudeResponse(try ClaudeCommandResponse(from: dataDecoder))
        case .subscribed:
            self.data = .subscribed(try SubscribedResponse(from: dataDecoder))
        case .streamChunk:
            self.data = .streamChunk(try StreamChunkResponse(from: dataDecoder))
        case .deviceRegistered:
            self.data = .deviceRegistered(try DeviceRegisteredResponse(from: dataDecoder))
        case .getMessageHistory:
            self.data = .getMessageHistory(try GetMessageHistoryRequest(from: dataDecoder))
        case .acknowledgeMessages:
            self.data = .acknowledgeMessages(try AcknowledgeMessagesRequest(from: dataDecoder))
        case .clearChat:
            self.data = .clearChat(try ClearChatRequest(from: dataDecoder))
        case .getMessageHistoryResponse:
            self.data = .getMessageHistoryResponse(try GetMessageHistoryResponse(from: dataDecoder))
        case .clearChatResponse:
            self.data = .clearChatResponse(try ClearChatResponse(from: dataDecoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Unsupported message type for decoding: \(type)")
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, requestId, timestamp, data
    }
    
    // Custom encoding
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encode(timestamp, forKey: .timestamp)
        
        // Encode data based on its case
        switch data {
        case .ask(let request):
            try container.encode(request, forKey: .data)
        case .streamStart(let request):
            try container.encode(request, forKey: .data)
        case .streamSend(let request):
            try container.encode(request, forKey: .data)
        case .permission(let response):
            try container.encode(response, forKey: .data)
        case .streamClose(let request):
            try container.encode(request, forKey: .data)
        case .ping(let request):
            try container.encode(request, forKey: .data)
        case .subscribe(let request):
            try container.encode(request, forKey: .data)
        case .setWorkingDirectory(let request):
            try container.encode(request, forKey: .data)
        case .claudeCommand(let request):
            try container.encode(request, forKey: .data)
        case .registerDevice(let request):
            try container.encode(request, forKey: .data)
        case .welcome(let response):
            try container.encode(response, forKey: .data)
        case .askResponse(let data):
            try container.encode(data, forKey: .data)
        case .streamStarted(let response):
            try container.encode(response, forKey: .data)
        case .streamData(let response):
            try container.encode(response, forKey: .data)
        case .streamToolUse(let response):
            try container.encode(response, forKey: .data)
        case .permissionRequest(let data):
            try container.encode(data, forKey: .data)
        case .streamComplete(let response):
            try container.encode(response, forKey: .data)
        case .error(let response):
            try container.encode(response, forKey: .data)
        case .sessionStatus(let response):
            try container.encode(response, forKey: .data)
        case .pong(let response):
            try container.encode(response, forKey: .data)
        case .claudeResponse(let response):
            try container.encode(response, forKey: .data)
        case .subscribed(let response):
            try container.encode(response, forKey: .data)
        case .systemInit(let response):
            try container.encode(response, forKey: .data)
        case .assistantMessage(let response):
            try container.encode(response, forKey: .data)
        case .toolUse(let response):
            try container.encode(response, forKey: .data)
        case .toolResult(let response):
            try container.encode(response, forKey: .data)
        case .conversationResult(let response):
            try container.encode(response, forKey: .data)
        case .workingDirectorySet(let response):
            try container.encode(response, forKey: .data)
        case .progress(let response):
            try container.encode(response, forKey: .data)
        case .streamChunk(let response):
            try container.encode(response, forKey: .data)
        case .deviceRegistered(let response):
            try container.encode(response, forKey: .data)
        case .getMessageHistory(let request):
            try container.encode(request, forKey: .data)
        case .acknowledgeMessages(let request):
            try container.encode(request, forKey: .data)
        case .clearChat(let request):
            try container.encode(request, forKey: .data)
        case .getMessageHistoryResponse(let response):
            try container.encode(response, forKey: .data)
        case .clearChatResponse(let response):
            try container.encode(response, forKey: .data)
        }
    }
}

enum WebSocketMessageType: String, Codable {
    // Client → Server
    case ask
    case streamStart
    case streamSend
    case permission
    case streamClose
    case ping
    case subscribe
    case setWorkingDirectory
    case claudeCommand
    case registerDevice
    case getMessageHistory
    case acknowledgeMessages
    case clearChat

    // Server → Client
    case welcome
    case getMessageHistoryResponse
    case askResponse
    case streamStarted
    case streamData
    case streamChunk
    case streamToolUse
    case permissionRequest
    case streamComplete
    case error
    case sessionStatus
    case pong
    case claudeResponse
    case subscribed

    // New rich message types from enhanced server
    case systemInit
    case assistantMessage
    case toolUse
    case toolResult
    case conversationResult
    case workingDirectorySet
    case clearChatResponse
    
    // Progress and status message types
    case progress
    
    // Device registration
    case deviceRegistered
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

struct ClaudeCommandRequest: Codable {
    let command: String
    let projectPath: String
    let sessionId: String?
}

struct GetMessageHistoryRequest: Codable {
    let sessionId: String
    let limit: Int?
    let offset: Int?
}

struct AcknowledgeMessagesRequest: Codable {
    let messageIds: [String]
}

struct ClearChatRequest: Codable {
    let sessionId: String
}

struct ClearChatResponse: Codable {
    let success: Bool
    let oldSessionId: String
    let newSessionId: String
    let message: String
}

// MARK: - Server Response Models

struct WelcomeResponse: Codable {
    let clientId: String
    let serverVersion: String
    let claudeCodeVersion: String?
    let capabilities: [String]?  // Optional - server is stateless
    let maxSessions: Int?        // Optional - not needed in stateless architecture
}

struct AskResponseData: Codable {
    let success: Bool
    let response: AICLIResponse?
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

struct StreamChunkResponse: Codable {
    let sessionId: String
    let chunk: StreamChunk
}

struct StreamChunk: Codable {
    let id: String
    let type: String
    let content: String
    let isFinal: Bool
    let metadata: StreamChunkMetadata?
}

struct StreamChunkMetadata: Codable {
    let language: String?
    let level: Int?
    let toolName: String?
    
    // Status-related metadata for Claude CLI status chunks
    let statusType: String?
    let stage: String?
    let activity: String? // Activity from server stream parser
    let duration: Double?
    let tokens: Int?
    let tools: [String]?
    let canInterrupt: Bool?
    
    init(language: String? = nil, level: Int? = nil, toolName: String? = nil, statusType: String? = nil, stage: String? = nil, activity: String? = nil, duration: Double? = nil, tokens: Int? = nil, tools: [String]? = nil, canInterrupt: Bool? = nil) {
        self.language = language
        self.level = level
        self.toolName = toolName
        self.statusType = statusType
        self.stage = stage
        self.activity = activity
        self.duration = duration
        self.tokens = tokens
        self.tools = tools
        self.canInterrupt = canInterrupt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        self.language = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "language"))
        self.level = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKeys(stringValue: "level"))
        self.toolName = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "toolName"))
        
        // Decode status-related fields
        self.statusType = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "statusType"))
        self.stage = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "stage"))
        self.activity = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "activity"))
        self.duration = try container.decodeIfPresent(Double.self, forKey: DynamicCodingKeys(stringValue: "duration"))
        self.tokens = try container.decodeIfPresent(Int.self, forKey: DynamicCodingKeys(stringValue: "tokens"))
        self.tools = try container.decodeIfPresent([String].self, forKey: DynamicCodingKeys(stringValue: "tools"))
        self.canInterrupt = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKeys(stringValue: "canInterrupt"))
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init(stringValue: String) {
            self.stringValue = stringValue
        }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
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
    let workingDirectory: String
    let isActive: Bool
    let createdAt: String
    let lastActivity: String
    let process: ProcessInfo?
    
    struct ProcessInfo: Codable {
        let pid: Int?
        let connected: Bool
        let signalCode: String?
        let exitCode: Int?
    }
}

struct PongResponse: Codable {
    let serverTime: Date
}

struct SubscribedResponse: Codable {
    let events: [String]
    let sessionIds: [String]
    let success: Bool
}

// MARK: - Rich Message Response Models

struct SystemInitResponse: Codable {
    let type: String
    let sessionId: String?
    let claudeSessionId: String?  // Claude's actual session ID
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
    let claudeSessionId: String?  // Claude's actual session ID
    let deliverables: [Deliverable]?
    let aggregated: Bool?
    let messageCount: Int?
    let isComplete: Bool?
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
    let claudeSessionId: String?  // Claude's actual session ID
    let duration: TimeInterval?
    let cost: Double?
    let usage: Usage?
    let timestamp: Date
}

struct WorkingDirectorySetResponse: Codable {
    let workingDirectory: String
    let success: Bool
}

struct ClaudeCommandResponse: Codable {
    let content: String
    let success: Bool
    let sessionId: String?
    let error: String?
}

struct GetMessageHistoryResponse: Codable {
    let success: Bool
    let sessionId: String
    let messages: [HistoryMessage]
    let totalCount: Int
    let offset: Int
    let limit: Int?
    let hasMore: Bool
    let sessionMetadata: SessionMetadata
    let timestamp: String
}

struct HistoryMessage: Codable {
    let id: String
    let type: String
    let content: [MessageContent]?
    let timestamp: String?
    let model: String?
    let usage: Usage?
}

struct MessageContent: Codable {
    let type: String
    let text: String?
}

struct SessionMetadata: Codable {
    let workingDirectory: String
    let conversationStarted: Bool
    let createdAt: TimeInterval
    let lastActivity: TimeInterval
}

struct ProgressResponse: Codable {
    let sessionId: String
    let stage: String
    let progress: Double?
    let message: String
    let timestamp: Date
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

enum AICLICompanionError: LocalizedError, Equatable {
    case connectionFailed(String)
    case authenticationFailed
    case serverNotFound
    case invalidResponse
    case invalidURL
    case httpError(Int)
    case noData
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
        case .invalidURL:
            return "Invalid server URL"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .noData:
            return "No data received from server"
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
    
    // MARK: - Equatable Implementation
    static func == (lhs: AICLICompanionError, rhs: AICLICompanionError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionFailed(let lhsMessage), .connectionFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.authenticationFailed, .authenticationFailed),
             (.serverNotFound, .serverNotFound),
             (.invalidResponse, .invalidResponse),
             (.invalidURL, .invalidURL),
             (.noData, .noData),
             (.permissionDenied, .permissionDenied),
             (.rateLimited, .rateLimited),
             (.timeout, .timeout):
            return true
        case (.httpError(let lhsCode), .httpError(let rhsCode)):
            return lhsCode == rhsCode
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.jsonParsingError(let lhsError), .jsonParsingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.webSocketError(let lhsMessage), .webSocketError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.sessionNotFound(let lhsSession), .sessionNotFound(let rhsSession)):
            return lhsSession == rhsSession
        default:
            return false
        }
    }
}

// MARK: - Progress Info for UI

struct ProgressInfo {
    let stage: String
    let progress: Double?
    let message: String
    let timestamp: Date
    let startTime: Date
    let tokenCount: Int
    let duration: TimeInterval
    let activity: String?
    let canInterrupt: Bool
    
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    init(from progressResponse: ProgressResponse) {
        self.stage = progressResponse.stage
        self.progress = progressResponse.progress
        self.message = progressResponse.message
        self.timestamp = progressResponse.timestamp
        // Use timestamp as start time if not specified
        self.startTime = progressResponse.timestamp
        // Token count is not in ProgressResponse, default to 0
        self.tokenCount = 0
        self.duration = 0
        self.activity = nil
        self.canInterrupt = false
    }
    
    init(stage: String, progress: Double? = nil, message: String, startTime: Date = Date(), duration: TimeInterval = 0, tokenCount: Int = 0, activity: String? = nil, canInterrupt: Bool = false) {
        self.stage = stage
        self.progress = progress
        self.message = message
        self.timestamp = Date()
        self.startTime = startTime
        self.tokenCount = tokenCount
        self.duration = duration
        self.activity = activity
        self.canInterrupt = canInterrupt
    }
}

// MARK: - Device Registration

struct RegisterDeviceRequest: Codable {
    let token: String
    let platform: String
}

struct DeviceRegisteredResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - CloudKit Extensions Removed
// Local storage only - no cloud sync
