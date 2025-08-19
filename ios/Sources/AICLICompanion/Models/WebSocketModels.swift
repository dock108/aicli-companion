import Foundation

// MARK: - WebSocket Message Models
struct WebSocketMessage: Codable {
    let type: WebSocketMessageType
    let data: WebSocketMessageData?
    let id: String?
    let requestId: String?
    let error: String?
    let timestamp: Date?
    
    init(type: WebSocketMessageType, data: WebSocketMessageData? = nil, id: String? = nil, requestId: String? = nil, error: String? = nil, timestamp: Date? = nil) {
        self.type = type
        self.data = data
        self.id = id
        self.requestId = requestId
        self.error = error
        self.timestamp = timestamp
    }
}

enum WebSocketMessageType: String, Codable {
    // Request types
    case ask = "ask"
    case streamStart = "stream_start"
    case streamSend = "stream_send"
    case streamClose = "stream_close"
    case permission = "permission"
    case ping = "ping"
    case subscribe = "subscribe"
    case setWorkingDirectory = "set_working_directory"
    case claudeCommand = "claude_command"
    case getMessageHistory = "get_message_history"
    case acknowledgeMessages = "acknowledge_messages"
    case clearChat = "clear_chat"
    
    // Response types
    case welcome = "welcome"
    case askResponse = "ask_response"
    case streamStarted = "stream_started"
    case streamData = "stream_data"
    case streamToolUse = "stream_tool_use"
    case streamChunk = "stream_chunk"
    case permissionRequest = "permission_request"
    case streamComplete = "stream_complete"
    case error = "error"
    case sessionStatus = "session_status"
    case pong = "pong"
    case subscribed = "subscribed"
    case systemInit = "system_init"
    case assistantMessage = "assistant_message"
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case conversationResult = "conversation_result"
    case workingDirectorySet = "working_directory_set"
    case claudeCommandResponse = "claude_command_response"
    case messageHistory = "message_history"
    case messagesAcknowledged = "messages_acknowledged"
    case chatCleared = "chat_cleared"
    case progress = "progress"
}

enum WebSocketMessageData: Codable {
    case ask(AskRequest)
    case streamStart(StreamStartRequest)
    case streamSend(StreamSendRequest)
    case streamClose(StreamCloseRequest)
    case permission(PermissionResponse)
    case ping(PingRequest)
    case subscribe(SubscribeRequest)
    case setWorkingDirectory(SetWorkingDirectoryRequest)
    case claudeCommand(ClaudeCommandRequest)
    case getMessageHistory(GetMessageHistoryRequest)
    case acknowledgeMessages(AcknowledgeMessagesRequest)
    case clearChat(ClearChatRequest)
    case welcome(WelcomeResponse)
    case askResponse(AskResponseData)
    case streamStarted(StreamStartedResponse)
    case streamData(StreamDataResponse)
    case streamToolUse(StreamToolUseResponse)
    case streamChunk(StreamChunkResponse)
    case permissionRequest(PermissionRequestData)
    case streamComplete(StreamCompleteResponse)
    case error(ErrorResponse)
    case sessionStatus(SessionStatusResponse)
    case pong(PongResponse)
    case subscribed(SubscribedResponse)
    case systemInit(SystemInitResponse)
    case assistantMessage(AssistantMessageResponse)
    case toolUse(ToolUseResponse)
    case toolResult(ToolResultResponse)
    case conversationResult(ConversationResultResponse)
    case workingDirectorySet(WorkingDirectorySetResponse)
    case claudeCommandResponse(ClaudeCommandResponse)
    case messageHistory(GetMessageHistoryResponse)
    case messagesAcknowledged(AcknowledgedResponse)
    case chatCleared(ClearChatResponse)
    case progress(ProgressResponse)
}

// MARK: - Request Models
struct AskRequest: Codable {
    let message: String
    let options: AskOptions?
}

struct AskOptions: Codable {
    let includeHistory: Bool?
}

struct StreamStartRequest: Codable {
    let message: String
    let options: StreamOptions?
}

struct StreamOptions: Codable {
    let includeHistory: Bool?
}

struct StreamSendRequest: Codable {
    let message: String
}

struct PermissionResponse: Codable {
    let response: String
    let requestId: String
}

struct StreamCloseRequest: Codable {
    let reason: String?
}

struct PingRequest: Codable {}

struct SubscribeRequest: Codable {
    let events: [String]
}

struct SetWorkingDirectoryRequest: Codable {
    let path: String
}

struct ClaudeCommandRequest: Codable {
    let command: String
    let args: [String]?
}

struct GetMessageHistoryRequest: Codable {
    let limit: Int?
    let offset: Int?
}

struct AcknowledgeMessagesRequest: Codable {
    let messageIds: [String]
}

struct ClearChatRequest: Codable {
    let confirm: Bool
}

// MARK: - Response Models
struct WelcomeResponse: Codable {
    let serverVersion: String
    let supportedFeatures: [String]
    let sessionId: String?
}

struct AskResponseData: Codable {
    let response: String
    let sessionId: String?
}

struct StreamStartedResponse: Codable {
    let streamId: String
    let sessionId: String?
}

struct StreamDataResponse: Codable {
    let content: [StreamContent]
    let streamId: String?
}

struct StreamContent: Codable {
    let type: String
    let text: String?
}

struct StreamToolUseResponse: Codable {
    let toolUse: ToolUseResponse
    let streamId: String?
}

struct StreamChunkResponse: Codable {
    let chunk: StreamChunk
}

struct StreamChunk: Codable {
    let type: String
    let content: String?
    let metadata: StreamChunkMetadata?
}

struct StreamChunkMetadata: Codable {
    let toolName: String?
    let toolId: String?
    let isPartial: Bool?
    let index: Int?
    let total: Int?
    let progress: Double?
    let estimatedTimeRemaining: TimeInterval?
    let status: String?
    let details: [String: AnyCodable]?
    let sessionId: String?
    let requestId: String?
    let duration: TimeInterval?
    let usage: Usage?
    let model: String?
    let finishReason: String?
    let stopSequence: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
}

struct PermissionRequestData: Codable {
    let prompt: String
    let options: [String]
    let requestId: String
}

struct StreamCompleteResponse: Codable {
    let streamId: String
    let finalResponse: String?
    let sessionId: String?
}

struct ErrorResponse: Codable {
    let message: String
    let code: String?
}

struct SessionStatusResponse: Codable {
    let isActive: Bool
    let sessionId: String?
    let startTime: Date?
    let lastActivity: Date?
    let messageCount: Int?
    let workingDirectory: String?
    let serverVersion: String?
}

struct PongResponse: Codable {
    let timestamp: Date
}

struct SubscribedResponse: Codable {
    let events: [String]
    let success: Bool
}

struct SystemInitResponse: Codable {
    let system: String
    let version: String
    let features: [String]
    let workingDirectory: String?
}

// Type aliases for backward compatibility
typealias AcknowledgedResponse = ClearChatResponse
