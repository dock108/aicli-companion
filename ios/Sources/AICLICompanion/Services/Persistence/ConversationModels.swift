import Foundation

// MARK: - Conversation Data Models

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    var sessionId: String?
    var workingDirectory: String?
    var createdAt: Date
    var updatedAt: Date
    var metadata: ConversationMetadata

    init(title: String = "New Conversation", sessionId: String? = nil, workingDirectory: String? = nil) {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.createdAt = Date()
        self.updatedAt = Date()
        self.metadata = ConversationMetadata()
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()

        // Update metadata
        metadata.messageCount = messages.count
        metadata.hasToolUsage = messages.contains { (message: Message) in
            message.type == .toolUse || message.type == .toolResult
        }
        metadata.hasRichContent = messages.contains { (message: Message) in
            message.richContent != nil
        }

        // Auto-generate title from first user message if still default
        if title == "New Conversation" || title.isEmpty {
            if let firstUserMessage = messages.first(where: { $0.sender == .user }) {
                title = generateTitle(from: firstUserMessage.content)
            }
        }
    }

    private func generateTitle(from content: String) -> String {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(6)

        if !words.isEmpty {
            return words.joined(separator: " ")
        }
        return "New Conversation"
    }
}

struct ConversationMetadata: Codable {
    var messageCount: Int = 0
    var hasToolUsage: Bool = false
    var hasRichContent: Bool = false
    var tags: [String] = []
    var isFavorite: Bool = false
    var lastActiveAt: Date = Date()
}

enum ExportFormat: String, Codable, CaseIterable {
    case json = "json"
    case markdown = "md"
    case text = "txt"
    case html = "html"
    case pdf = "pdf"
    
    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .text: return "Plain Text"
        case .html: return "HTML"
        case .pdf: return "PDF"
        }
    }
    
    var fileExtension: String {
        return self.rawValue
    }
    
    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .markdown: return "text/markdown"
        case .text: return "text/plain"
        case .html: return "text/html"
        case .pdf: return "application/pdf"
        }
    }
}

struct MultipleConversationsExport: Codable {
    let conversations: [Conversation]
    let exportedAt: Date
    let format: ExportFormat
    let totalMessages: Int
    
    init(conversations: [Conversation], format: ExportFormat) {
        self.conversations = conversations
        self.format = format
        self.exportedAt = Date()
        self.totalMessages = conversations.reduce(0) { $0 + $1.messages.count }
    }
}

struct ConversationStatistics {
    let totalConversations: Int
    let totalMessages: Int
    let averageMessagesPerConversation: Double
    let oldestConversation: Date?
    let newestConversation: Date?
    let conversationsWithToolUsage: Int
    let conversationsWithRichContent: Int
    let totalStorageSize: Int
}
