import Foundation

// MARK: - Server Connection Models
public enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case authenticating
    case unauthorized
    case error(String)
    
    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

public struct ServerConnection: Codable {
    public let id: UUID
    public let name: String
    public let address: String
    public let port: Int
    public let authToken: String?
    public let isSecure: Bool
    public let lastConnected: Date?
    public let isDefault: Bool
    
    public init(id: UUID = UUID(), name: String, address: String, port: Int, authToken: String? = nil, isSecure: Bool = false, lastConnected: Date? = nil, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.authToken = authToken
        self.isSecure = isSecure
        self.lastConnected = lastConnected
        self.isDefault = isDefault
    }
    
    public var url: String {
        let scheme = isSecure ? "https" : "http"
        return "\(scheme)://\(address):\(port)"
    }
    
    public var wsUrl: String {
        let scheme = isSecure ? "wss" : "ws"
        return "\(scheme)://\(address):\(port)/ws"
    }
    
    var displayName: String {
        return name.isEmpty ? "\(address):\(port)" : name
    }
}

struct DiscoveredServer {
    let name: String
    let address: String
    let port: Int
    let isSecure: Bool
    let lastSeen: Date
    
    var url: String {
        let scheme = isSecure ? "https" : "http"
        return "\(scheme)://\(address):\(port)"
    }
}

// MARK: - Server Response Models
struct AICLIResponse: Codable {
    let success: Bool
    let content: String?
    let error: String?
    let sessionId: String?
    let claudeSessionId: String?
    let usage: Usage?
    let deliverables: [Deliverable]?
    let toolUse: [ServerToolUse]?
    let duration: Double?
    let result: String?
    
    init(success: Bool, content: String? = nil, error: String? = nil, sessionId: String? = nil, claudeSessionId: String? = nil, usage: Usage? = nil, deliverables: [Deliverable]? = nil, toolUse: [ServerToolUse]? = nil, duration: Double? = nil, result: String? = nil) {
        self.success = success
        self.content = content
        self.error = error
        self.sessionId = sessionId
        self.claudeSessionId = claudeSessionId
        self.usage = usage
        self.deliverables = deliverables
        self.toolUse = toolUse
        self.duration = duration
        self.result = result
    }
}

struct Usage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?
    
    init(inputTokens: Int? = nil, outputTokens: Int? = nil, cacheCreationInputTokens: Int? = nil, cacheReadInputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

struct ServerToolUse: Codable {
    let id: String
    let name: String
    let input: [String: AnyCodable]
}

struct Deliverable: Codable {
    let artifact: String
    let content: String
}

// MARK: - Error Types
public enum AICLICompanionError: LocalizedError, Equatable {
    case networkError(String)
    case authenticationFailed
    case serverError(String)
    case invalidResponse
    case connectionTimeout
    case websocketError(String)
    case invalidURL
    case noProjectSelected
    case fileNotFound(String)
    case permissionDenied
    case invalidInput(String)
    case sessionExpired
    case rateLimited
    case serverUnavailable
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed:
            return "Authentication failed"
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .connectionTimeout:
            return "Connection timeout"
        case .websocketError(let message):
            return "WebSocket error: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .noProjectSelected:
            return "No project selected"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied:
            return "Permission denied"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .sessionExpired:
            return "Session expired"
        case .rateLimited:
            return "Rate limited"
        case .serverUnavailable:
            return "Server unavailable"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    public static func == (lhs: AICLICompanionError, rhs: AICLICompanionError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let a), .networkError(let b)): return a == b
        case (.authenticationFailed, .authenticationFailed): return true
        case (.serverError(let a), .serverError(let b)): return a == b
        case (.invalidResponse, .invalidResponse): return true
        case (.connectionTimeout, .connectionTimeout): return true
        case (.websocketError(let a), .websocketError(let b)): return a == b
        case (.invalidURL, .invalidURL): return true
        case (.noProjectSelected, .noProjectSelected): return true
        case (.fileNotFound(let a), .fileNotFound(let b)): return a == b
        case (.permissionDenied, .permissionDenied): return true
        case (.invalidInput(let a), .invalidInput(let b)): return a == b
        case (.sessionExpired, .sessionExpired): return true
        case (.rateLimited, .rateLimited): return true
        case (.serverUnavailable, .serverUnavailable): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}