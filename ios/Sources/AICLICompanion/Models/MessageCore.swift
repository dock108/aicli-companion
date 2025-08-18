import Foundation

// MARK: - Core Message Model
public struct Message: Identifiable, Codable {
    public let id: UUID
    public var content: String
    public let sender: MessageSender
    public let timestamp: Date
    public let type: MessageType
    public var metadata: AICLIMessageMetadata?
    public var streamingState: StreamingState?
    public let requestId: String?
    public let richContent: RichContent?
    
    // CloudKit removed - local storage only
    var readByDevices: [String] = []
    var deletedByDevices: [String] = []
    var syncedAt: Date?
    var needsSync: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case id, content, sender, timestamp, type, metadata, streamingState, requestId, richContent
    }

    public init(id: UUID = UUID(), content: String, sender: MessageSender, timestamp: Date = Date(), type: MessageType = .text, metadata: AICLIMessageMetadata? = nil, streamingState: StreamingState? = nil, requestId: String? = nil, richContent: RichContent? = nil, attachments: [AttachmentData]? = nil) {
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

// MARK: - Basic Message Types
public enum MessageSender: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

public enum MessageType: String, Codable, CaseIterable {
    case text
    case markdown
    case code
    case error
    case system
    case file
    case command
    case audio
    case stream
    case toolUse
    case toolResult
}

public enum StreamingState: String, Codable, CaseIterable {
    case none
    case streaming
    case complete
    case error
}

// MARK: - Message Metadata
public struct AICLIMessageMetadata: Codable {
    public let sessionId: String
    public let duration: TimeInterval
    public var additionalInfo: [String: AnyCodable]?
    public var statusMetadata: StatusMetadata?
    public var queuedAt: Date?
    public var deliveredAt: Date?
    
    // CloudKit removed - local storage only
    var syncedAt: Date?
    var needsSync: Bool = true
    
    public init(sessionId: String, duration: TimeInterval, additionalInfo: [String: AnyCodable]? = nil, statusMetadata: StatusMetadata? = nil, queuedAt: Date? = nil, deliveredAt: Date? = nil) {
        self.sessionId = sessionId
        self.duration = duration
        self.additionalInfo = additionalInfo
        self.statusMetadata = statusMetadata
        self.queuedAt = queuedAt
        self.deliveredAt = deliveredAt
    }
}

public struct StatusMetadata: Codable {
    public let status: String
    public let progress: Double?
    public let details: [String: AnyCodable]?
    public let isConnected: Bool
    public let connectionStatus: String?
    
    // CloudKit removed - local storage only
    var syncedAt: Date?
    var needsSync: Bool = true
    
    init(status: String, progress: Double? = nil, details: [String: AnyCodable]? = nil, isConnected: Bool = false, connectionStatus: String? = nil) {
        self.status = status
        self.progress = progress
        self.details = details
        self.isConnected = isConnected
        self.connectionStatus = connectionStatus
    }
}
