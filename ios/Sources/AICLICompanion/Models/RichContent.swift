import Foundation

// MARK: - Rich Content Support
public struct RichContent: Codable {
    public let contentType: RichContentType
    public let data: RichContentData
}

public enum RichContentType: String, Codable {
    case codeBlock
    case fileContent
    case commandOutput
    case toolResult
    case markdown
    case attachments
}

public enum RichContentData: Codable {
    case codeBlock(CodeBlockData)
    case fileContent(FileContentData)
    case commandOutput(CommandOutputData)
    case toolResult(ToolResultData)
    case markdown(MarkdownData)
    case attachments(AttachmentsData)
}

public struct CodeBlockData: Codable {
    public let language: String
    public let code: String
    public let filename: String?
    public let lineNumbers: Bool
}

public struct FileContentData: Codable {
    public let filename: String
    public let content: String
    public let mimeType: String
    public let size: Int
    public let encoding: String
}

public struct CommandOutputData: Codable {
    public let command: String
    public let output: String
    public let exitCode: Int
    public let workingDirectory: String?
}

public struct ToolResultData: Codable {
    public let toolName: String
    public let result: String
    public let success: Bool
    public let metadata: [String: AnyCodable]?
}

public struct MarkdownData: Codable {
    public let content: String
    public let renderMode: MarkdownRenderMode
}

public enum MarkdownRenderMode: String, Codable {
    case full
    case inline
    case code
}

public struct AttachmentsData: Codable {
    public let attachments: [AttachmentInfo]
}

public struct AttachmentInfo: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let mimeType: String
    public let size: Int
    public let base64Data: String?
    public let url: String?
    public let thumbnailBase64: String?
    
    public init(id: UUID = UUID(), name: String, mimeType: String, size: Int, base64Data: String? = nil, url: String? = nil, thumbnailBase64: String? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.base64Data = base64Data
        self.url = url
        self.thumbnailBase64 = thumbnailBase64
    }
}
