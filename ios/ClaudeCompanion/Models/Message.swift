import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let content: String
    let sender: MessageSender
    let timestamp: Date
    let type: MessageType
    let metadata: ClaudeMessageMetadata?
    
    init(id: UUID = UUID(), content: String, sender: MessageSender, timestamp: Date = Date(), type: MessageType = .text, metadata: ClaudeMessageMetadata? = nil) {
        self.id = id
        self.content = content
        self.sender = sender
        self.timestamp = timestamp
        self.type = type
        self.metadata = metadata
    }
}

enum MessageSender: String, Codable, CaseIterable {
    case user = "user"
    case claude = "claude"
    case system = "system"
}

enum MessageType: String, Codable, CaseIterable {
    case text = "text"
    case code = "code"
    case error = "error"
    case permission = "permission"
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
        return URL(string: "\(scheme)://\(address):\(port)")
    }
    
    var wsURL: URL? {
        let scheme = isSecure ? "wss" : "ws"
        return URL(string: "\(scheme)://\(address):\(port)/ws")
    }
}

struct DiscoveredServer {
    let name: String
    let address: String
    let port: Int
    let isSecure: Bool
}

// MARK: - Error Types

enum ClaudeCompanionError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case serverNotFound
    case invalidResponse
    case networkError(Error)
    case jsonParsingError(Error)
    
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
        }
    }
}