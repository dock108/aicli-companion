import Foundation
import SwiftUI

// MARK: - Conversation Models

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
        metadata.hasToolUsage = messages.contains { $0.type == .toolUse || $0.type == .toolResult }
        metadata.hasRichContent = messages.contains { $0.richContent != nil }
        
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
        
        if words.count > 0 {
            return words.joined(separator: " ")
        }
        return "Conversation \(DateFormatter.shortDate.string(from: createdAt))"
    }
}

struct ConversationMetadata: Codable {
    var messageCount: Int = 0
    var hasToolUsage: Bool = false
    var hasRichContent: Bool = false
    var hasErrors: Bool = false
    var totalCost: Double? = nil
    var tags: [String] = []
    var projectPath: String? = nil
    var language: String? = nil
    var isFavorite: Bool = false
    var isArchived: Bool = false
}

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case markdown = "Markdown"
    case text = "Text"
    case html = "HTML"
    case csv = "CSV"
    
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .markdown: return "md"
        case .text: return "txt"
        case .html: return "html"
        case .csv: return "csv"
        }
    }
    
    var icon: String {
        switch self {
        case .json: return "doc.text"
        case .markdown: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .html: return "globe"
        case .csv: return "tablecells"
        }
    }
}

struct MultipleConversationsExport: Codable {
    let exportDate: Date
    let conversationCount: Int
    let conversations: [Conversation]
}

// MARK: - Conversation Persistence Service

class ConversationPersistenceService: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let conversationsDirectory: URL
    
    init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        conversationsDirectory = documentsDirectory.appendingPathComponent("Conversations")
        
        createDirectoriesIfNeeded()
        loadConversations()
    }
    
    // MARK: - Directory Management
    
    private func createDirectoriesIfNeeded() {
        if !fileManager.fileExists(atPath: conversationsDirectory.path) {
            try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Conversation Management
    
    func createNewConversation(title: String? = nil, sessionId: String? = nil, workingDirectory: String? = nil) -> Conversation {
        let conversation = Conversation(
            title: title ?? "New Conversation",
            sessionId: sessionId,
            workingDirectory: workingDirectory
        )
        
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        saveConversation(conversation)
        
        return conversation
    }
    
    func addMessageToCurrentConversation(_ message: Message) {
        guard var conversation = currentConversation else {
            currentConversation = createNewConversation()
            addMessageToCurrentConversation(message)
            return
        }
        
        conversation.addMessage(message)
        
        // Update in array
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        
        currentConversation = conversation
        saveConversation(conversation)
    }
    
    func updateCurrentConversationTitle(_ title: String) {
        guard var conversation = currentConversation else { return }
        
        conversation.title = title
        conversation.updatedAt = Date()
        
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        
        currentConversation = conversation
        saveConversation(conversation)
    }
    
    func updateCurrentConversationWorkingDirectory(_ workingDirectory: String) {
        guard var conversation = currentConversation else { return }
        
        conversation.workingDirectory = workingDirectory
        conversation.updatedAt = Date()
        
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        
        currentConversation = conversation
        saveConversation(conversation)
    }
    
    func switchToConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        
        // Delete file
        let fileURL = conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
    }
    
    func duplicateConversation(_ conversation: Conversation) -> Conversation {
        var newConversation = conversation
        newConversation.id = UUID()
        newConversation.title = "\(conversation.title) (Copy)"
        newConversation.createdAt = Date()
        newConversation.updatedAt = Date()
        newConversation.sessionId = nil // Reset session ID for copy
        
        conversations.insert(newConversation, at: 0)
        saveConversation(newConversation)
        
        return newConversation
    }
    
    // MARK: - Search and Filtering
    
    func searchConversations(query: String) -> [Conversation] {
        guard !query.isEmpty else { return conversations }
        
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query) ||
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(query)
            }
        }
    }
    
    func getConversationsWithTag(_ tag: String) -> [Conversation] {
        return conversations.filter { $0.metadata.tags.contains(tag) }
    }
    
    func getConversationsWithToolUsage() -> [Conversation] {
        return conversations.filter { $0.metadata.hasToolUsage }
    }
    
    func getAllTags() -> [String] {
        let allTags = conversations.flatMap { $0.metadata.tags }
        return Array(Set(allTags)).sorted()
    }
    
    // MARK: - File Operations
    
    private func saveConversation(_ conversation: Conversation) {
        let fileURL = conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
    
    private func loadConversations() {
        do {
            let files = try fileManager.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            
            var loadedConversations: [Conversation] = []
            
            for file in jsonFiles {
                do {
                    let data = try Data(contentsOf: file)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let conversation = try decoder.decode(Conversation.self, from: data)
                    loadedConversations.append(conversation)
                } catch {
                    print("Failed to load conversation from \(file): \(error)")
                }
            }
            
            // Sort by updated date, most recent first
            conversations = loadedConversations.sorted { $0.updatedAt > $1.updatedAt }
            
        } catch {
            print("Failed to load conversations directory: \(error)")
        }
    }
    
    // MARK: - Conversation Management
    
    func archiveConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].metadata.isArchived = true
            saveConversation(conversations[index])
        }
    }
    
    func unarchiveConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].metadata.isArchived = false
            saveConversation(conversations[index])
        }
    }
    
    func addTagToConversation(_ conversation: Conversation, tag: String) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            if !conversations[index].metadata.tags.contains(tag) {
                conversations[index].metadata.tags.append(tag)
                saveConversation(conversations[index])
            }
        }
    }
    
    func removeTagFromConversation(_ conversation: Conversation, tag: String) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].metadata.tags.removeAll { $0 == tag }
            saveConversation(conversations[index])
        }
    }
    
    func favoriteConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].metadata.isFavorite = true
            saveConversation(conversations[index])
        }
    }
    
    func unfavoriteConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].metadata.isFavorite = false
            saveConversation(conversations[index])
        }
    }
    
    func getFavoriteConversations() -> [Conversation] {
        return conversations.filter { $0.metadata.isFavorite }
    }
    
    func getArchivedConversations() -> [Conversation] {
        return conversations.filter { $0.metadata.isArchived }
    }
    
    func getActiveConversations() -> [Conversation] {
        return conversations.filter { !$0.metadata.isArchived }
    }
    
    func bulkDeleteConversations(_ conversationIds: [UUID]) {
        for id in conversationIds {
            if let conversation = conversations.first(where: { $0.id == id }) {
                deleteConversation(conversation)
            }
        }
    }
    
    func bulkArchiveConversations(_ conversationIds: [UUID]) {
        for id in conversationIds {
            if let conversation = conversations.first(where: { $0.id == id }) {
                archiveConversation(conversation)
            }
        }
    }
    
    func bulkExportConversations(_ conversationIds: [UUID], format: ExportFormat) -> URL? {
        let conversationsToExport = conversations.filter { conversationIds.contains($0.id) }
        return exportMultipleConversations(conversationsToExport, format: format)
    }
    
    // MARK: - Export and Import
    
    func exportConversation(_ conversation: Conversation) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory
        let fileName = "\(conversation.title.replacingOccurrences(of: " ", with: "_"))_\(DateFormatter.filenameSafe.string(from: conversation.createdAt)).json"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(conversation)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Failed to export conversation: \(error)")
            return nil
        }
    }
    
    func exportConversationAsText(_ conversation: Conversation) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory
        let fileName = "\(conversation.title.replacingOccurrences(of: " ", with: "_"))_\(DateFormatter.filenameSafe.string(from: conversation.createdAt)).txt"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        var content = "# \(conversation.title)\n\n"
        content += "Created: \(DateFormatter.readable.string(from: conversation.createdAt))\n"
        content += "Updated: \(DateFormatter.readable.string(from: conversation.updatedAt))\n"
        
        if let workingDir = conversation.workingDirectory {
            content += "Working Directory: \(workingDir)\n"
        }
        
        content += "\n---\n\n"
        
        for message in conversation.messages {
            let sender = message.sender.rawValue.capitalized
            let timestamp = DateFormatter.timeOnly.string(from: message.timestamp)
            
            content += "**\(sender)** (\(timestamp)):\n"
            content += "\(message.content)\n\n"
            
            if let richContent = message.richContent {
                switch richContent.data {
                case .codeBlock(let codeData):
                    content += "```\(codeData.language ?? "")\n\(codeData.code)\n```\n\n"
                case .fileContent(let fileData):
                    content += "File: \(fileData.filename)\n```\n\(fileData.content)\n```\n\n"
                case .commandOutput(let commandData):
                    content += "Command: \(commandData.command)\nOutput:\n```\n\(commandData.output)\n```\n\n"
                case .toolResult(let toolData):
                    content += "Tool: \(toolData.toolName) (\(toolData.success ? "Success" : "Failed"))\n```\n\(toolData.output)\n```\n\n"
                case .markdown(let markdownData):
                    content += "\(markdownData.markdown)\n\n"
                }
            }
            
            content += "---\n\n"
        }
        
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to export conversation as text: \(error)")
            return nil
        }
    }
    
    // MARK: - Enhanced Export Methods
    
    func exportConversation(_ conversation: Conversation, format: ExportFormat) -> URL? {
        switch format {
        case .json:
            return exportConversation(conversation)
        case .text:
            return exportConversationAsText(conversation)
        case .markdown:
            return exportConversationAsMarkdown(conversation)
        case .html:
            return exportConversationAsHTML(conversation)
        case .csv:
            return exportConversationAsCSV(conversation)
        }
    }
    
    func exportConversationAsMarkdown(_ conversation: Conversation) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory
        let fileName = "\(conversation.title.replacingOccurrences(of: " ", with: "_"))_\(DateFormatter.filenameSafe.string(from: conversation.createdAt)).md"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        var content = "# \(conversation.title)\n\n"
        
        // Metadata section
        content += "## Conversation Details\n\n"
        content += "- **Created:** \(DateFormatter.readable.string(from: conversation.createdAt))\n"
        content += "- **Updated:** \(DateFormatter.readable.string(from: conversation.updatedAt))\n"
        content += "- **Messages:** \(conversation.messages.count)\n"
        
        if let workingDir = conversation.workingDirectory {
            content += "- **Working Directory:** `\(workingDir)`\n"
        }
        
        if !conversation.metadata.tags.isEmpty {
            content += "- **Tags:** \(conversation.metadata.tags.joined(separator: ", "))\n"
        }
        
        if conversation.metadata.hasToolUsage {
            content += "- **Tool Usage:** Yes\n"
        }
        
        if let cost = conversation.metadata.totalCost {
            content += "- **Cost:** $\(String(format: "%.4f", cost))\n"
        }
        
        content += "\n---\n\n"
        
        // Messages section
        content += "## Conversation History\n\n"
        
        for (index, message) in conversation.messages.enumerated() {
            let sender = message.sender.rawValue.capitalized
            let timestamp = DateFormatter.timeOnly.string(from: message.timestamp)
            
            content += "### \(sender) - \(timestamp)\n\n"
            content += "\(message.content)\n\n"
            
            // Handle rich content
            if let richContent = message.richContent {
                switch richContent.data {
                case .codeBlock(let codeData):
                    let language = codeData.language ?? ""
                    content += "```\(language)\n\(codeData.code)\n```\n\n"
                case .fileContent(let fileData):
                    content += "**File:** `\(fileData.filename)`\n\n"
                    content += "```\n\(fileData.content)\n```\n\n"
                case .toolResult(let toolData):
                    content += "**Tool Result:** \(toolData.toolName)\n\n"
                    if toolData.success {
                        content += "✅ **Success**\n\n"
                    } else {
                        content += "❌ **Failed**\n\n"
                        if let error = toolData.error {
                            content += "**Error:** \(error)\n\n"
                        }
                    }
                    content += "```\n\(toolData.output)\n```\n\n"
                case .commandOutput(let commandData):
                    content += "**Command:** `\(commandData.command)`\n\n"
                    if commandData.exitCode == 0 {
                        content += "✅ **Success** (Exit Code: \(commandData.exitCode))\n\n"
                    } else {
                        content += "❌ **Failed** (Exit Code: \(commandData.exitCode))\n\n"
                    }
                    content += "```\n\(commandData.output)\n```\n\n"
                }
            }
            
            if index < conversation.messages.count - 1 {
                content += "---\n\n"
            }
        }
        
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to export conversation as Markdown: \(error)")
            return nil
        }
    }
    
    func exportConversationAsHTML(_ conversation: Conversation) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory
        let fileName = "\(conversation.title.replacingOccurrences(of: " ", with: "_"))_\(DateFormatter.filenameSafe.string(from: conversation.createdAt)).html"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(conversation.title)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
                .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .header { border-bottom: 2px solid #e9ecef; margin-bottom: 30px; padding-bottom: 20px; }
                .title { color: #495057; margin: 0 0 15px 0; font-size: 2em; font-weight: 600; }
                .metadata { color: #6c757d; font-size: 0.9em; }
                .metadata span { display: inline-block; margin-right: 20px; }
                .message { margin-bottom: 25px; }
                .message-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
                .sender { font-weight: 600; color: #495057; }
                .sender.user { color: #007bff; }
                .sender.claude { color: #28a745; }
                .sender.system { color: #ffc107; }
                .timestamp { color: #6c757d; font-size: 0.85em; }
                .message-content { background: #f8f9fa; padding: 15px; border-radius: 8px; border-left: 4px solid #e9ecef; }
                .user .message-content { background: #e3f2fd; border-left-color: #2196f3; }
                .claude .message-content { background: #f1f8e9; border-left-color: #4caf50; }
                .system .message-content { background: #fff3cd; border-left-color: #ffc107; }
                pre { background: #f8f9fa; border: 1px solid #e9ecef; border-radius: 6px; padding: 15px; overflow-x: auto; margin: 10px 0; }
                code { background: #f8f9fa; padding: 2px 6px; border-radius: 4px; font-family: 'Monaco', 'Menlo', monospace; }
                .rich-content { margin-top: 15px; padding: 15px; background: #fff; border: 1px solid #e9ecef; border-radius: 6px; }
                .tool-result { border-left: 4px solid #17a2b8; }
                .tool-success { border-left-color: #28a745; }
                .tool-error { border-left-color: #dc3545; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1 class="title">\(conversation.title)</h1>
                    <div class="metadata">
                        <span><strong>Created:</strong> \(DateFormatter.readable.string(from: conversation.createdAt))</span>
                        <span><strong>Messages:</strong> \(conversation.messages.count)</span>
        """
        
        if let workingDir = conversation.workingDirectory {
            html += "<span><strong>Working Directory:</strong> <code>\(workingDir)</code></span>"
        }
        
        if conversation.metadata.hasToolUsage {
            html += "<span><strong>Tool Usage:</strong> Yes</span>"
        }
        
        html += """
                    </div>
                </div>
                <div class="messages">
        """
        
        for message in conversation.messages {
            let sender = message.sender.rawValue
            let timestamp = DateFormatter.timeOnly.string(from: message.timestamp)
            let senderDisplay = message.sender.rawValue.capitalized
            
            html += """
                    <div class="message \(sender)">
                        <div class="message-header">
                            <span class="sender \(sender)">\(senderDisplay)</span>
                            <span class="timestamp">\(timestamp)</span>
                        </div>
                        <div class="message-content">
                            <p>\(message.content.replacingOccurrences(of: "\n", with: "<br>"))</p>
            """
            
            if let richContent = message.richContent {
                html += "<div class=\"rich-content\">"
                
                switch richContent.data {
                case .codeBlock(let codeData):
                    html += "<h4>Code Block</h4>"
                    html += "<pre><code>\(codeData.code)</code></pre>"
                case .fileContent(let fileData):
                    html += "<h4>File: \(fileData.filename)</h4>"
                    html += "<pre><code>\(fileData.content)</code></pre>"
                case .toolResult(let toolData):
                    let statusClass = toolData.success ? "tool-success" : "tool-error"
                    let statusIcon = toolData.success ? "✅" : "❌"
                    html += "<div class=\"tool-result \(statusClass)\">"
                    html += "<h4>\(statusIcon) Tool: \(toolData.toolName)</h4>"
                    if let error = toolData.error, !toolData.success {
                        html += "<p><strong>Error:</strong> \(error)</p>"
                    }
                    html += "<pre><code>\(toolData.output)</code></pre>"
                    html += "</div>"
                case .commandOutput(let commandData):
                    let statusIcon = commandData.exitCode == 0 ? "✅" : "❌"
                    html += "<h4>\(statusIcon) Command: \(commandData.command)</h4>"
                    html += "<p><strong>Exit Code:</strong> \(commandData.exitCode)</p>"
                    html += "<pre><code>\(commandData.output)</code></pre>"
                }
                
                html += "</div>"
            }
            
            html += """
                        </div>
                    </div>
            """
        }
        
        html += """
                </div>
            </div>
        </body>
        </html>
        """
        
        do {
            try html.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to export conversation as HTML: \(error)")
            return nil
        }
    }
    
    func exportConversationAsCSV(_ conversation: Conversation) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory
        let fileName = "\(conversation.title.replacingOccurrences(of: " ", with: "_"))_\(DateFormatter.filenameSafe.string(from: conversation.createdAt)).csv"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        var csv = "Timestamp,Sender,Type,Content,HasRichContent,ToolName,Success\n"
        
        for message in conversation.messages {
            let timestamp = DateFormatter.iso8601.string(from: message.timestamp)
            let sender = message.sender.rawValue
            let type = message.type.rawValue
            let content = "\"" + message.content.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let hasRichContent = message.richContent != nil ? "Yes" : "No"
            
            var toolName = ""
            var success = ""
            
            if let richContent = message.richContent {
                switch richContent.data {
                case .toolResult(let toolData):
                    toolName = toolData.toolName
                    success = toolData.success ? "Yes" : "No"
                case .commandOutput(let commandData):
                    toolName = "Command"
                    success = commandData.exitCode == 0 ? "Yes" : "No"
                default:
                    break
                }
            }
            
            csv += "\(timestamp),\(sender),\(type),\(content),\(hasRichContent),\(toolName),\(success)\n"
        }
        
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("Failed to export conversation as CSV: \(error)")
            return nil
        }
    }
    
    func exportMultipleConversations(_ conversations: [Conversation], format: ExportFormat) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory
        let timestamp = DateFormatter.filenameSafe.string(from: Date())
        let fileName = "conversations_export_\(timestamp).\(format.fileExtension)"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        switch format {
        case .json:
            return exportMultipleConversationsAsJSON(conversations, to: tempURL)
        case .markdown:
            return exportMultipleConversationsAsMarkdown(conversations, to: tempURL)
        case .html:
            return exportMultipleConversationsAsHTML(conversations, to: tempURL)
        case .csv:
            return exportMultipleConversationsAsCSV(conversations, to: tempURL)
        case .text:
            return exportMultipleConversationsAsText(conversations, to: tempURL)
        }
    }
    
    private func exportMultipleConversationsAsJSON(_ conversations: [Conversation], to url: URL) -> URL? {
        let exportData = MultipleConversationsExport(
            exportDate: Date(),
            conversationCount: conversations.count,
            conversations: conversations
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(exportData)
            try data.write(to: url)
            return url
        } catch {
            print("Failed to export multiple conversations as JSON: \(error)")
            return nil
        }
    }
    
    private func exportMultipleConversationsAsMarkdown(_ conversations: [Conversation], to url: URL) -> URL? {
        var content = "# Conversation Export\n\n"
        content += "**Export Date:** \(DateFormatter.readable.string(from: Date()))\n"
        content += "**Total Conversations:** \(conversations.count)\n\n"
        content += "---\n\n"
        
        for (index, conversation) in conversations.enumerated() {
            content += "## \(index + 1). \(conversation.title)\n\n"
            content += "**Created:** \(DateFormatter.readable.string(from: conversation.createdAt))\n"
            content += "**Messages:** \(conversation.messages.count)\n\n"
            
            for message in conversation.messages {
                let sender = message.sender.rawValue.capitalized
                content += "**\(sender):** \(message.content)\n\n"
            }
            
            if index < conversations.count - 1 {
                content += "\n---\n\n"
            }
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to export multiple conversations as Markdown: \(error)")
            return nil
        }
    }
    
    private func exportMultipleConversationsAsHTML(_ conversations: [Conversation], to url: URL) -> URL? {
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Conversation Export</title>
            <style>
                body { font-family: system-ui, -apple-system, sans-serif; line-height: 1.6; max-width: 1000px; margin: 0 auto; padding: 20px; }
                .conversation { border: 1px solid #ddd; margin-bottom: 30px; border-radius: 8px; overflow: hidden; }
                .conversation-header { background: #f8f9fa; padding: 15px; border-bottom: 1px solid #ddd; }
                .conversation-content { padding: 15px; }
                .message { margin-bottom: 15px; padding: 10px; border-radius: 6px; }
                .user { background: #e3f2fd; }
                .claude { background: #f1f8e9; }
                .system { background: #fff3cd; }
            </style>
        </head>
        <body>
            <h1>Conversation Export</h1>
            <p><strong>Export Date:</strong> \(DateFormatter.readable.string(from: Date()))</p>
            <p><strong>Total Conversations:</strong> \(conversations.count)</p>
        """
        
        for conversation in conversations {
            html += """
            <div class="conversation">
                <div class="conversation-header">
                    <h2>\(conversation.title)</h2>
                    <p>Created: \(DateFormatter.readable.string(from: conversation.createdAt)) | Messages: \(conversation.messages.count)</p>
                </div>
                <div class="conversation-content">
            """
            
            for message in conversation.messages {
                html += "<div class=\"message \(message.sender.rawValue)\">"
                html += "<strong>\(message.sender.rawValue.capitalized):</strong> \(message.content.replacingOccurrences(of: "\n", with: "<br>"))"
                html += "</div>"
            }
            
            html += "</div></div>"
        }
        
        html += "</body></html>"
        
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to export multiple conversations as HTML: \(error)")
            return nil
        }
    }
    
    private func exportMultipleConversationsAsCSV(_ conversations: [Conversation], to url: URL) -> URL? {
        var csv = "ConversationID,ConversationTitle,Timestamp,Sender,Type,Content\n"
        
        for conversation in conversations {
            for message in conversation.messages {
                let timestamp = DateFormatter.iso8601.string(from: message.timestamp)
                let content = "\"" + message.content.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                csv += "\(conversation.id),\"\(conversation.title)\",\(timestamp),\(message.sender.rawValue),\(message.type.rawValue),\(content)\n"
            }
        }
        
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to export multiple conversations as CSV: \(error)")
            return nil
        }
    }
    
    private func exportMultipleConversationsAsText(_ conversations: [Conversation], to url: URL) -> URL? {
        var content = "CONVERSATION EXPORT\n"
        content += "==================\n\n"
        content += "Export Date: \(DateFormatter.readable.string(from: Date()))\n"
        content += "Total Conversations: \(conversations.count)\n\n"
        
        for (index, conversation) in conversations.enumerated() {
            content += "\(index + 1). \(conversation.title)\n"
            content += String(repeating: "-", count: conversation.title.count + 3) + "\n"
            content += "Created: \(DateFormatter.readable.string(from: conversation.createdAt))\n"
            content += "Messages: \(conversation.messages.count)\n\n"
            
            for message in conversation.messages {
                content += "[\(message.sender.rawValue.uppercased())] \(message.content)\n\n"
            }
            
            content += "\n"
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to export multiple conversations as Text: \(error)")
            return nil
        }
    }
    
    func importConversation(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let conversation = try decoder.decode(Conversation.self, from: data)
            
            // Check if conversation already exists
            if !conversations.contains(where: { $0.id == conversation.id }) {
                conversations.insert(conversation, at: 0)
                saveConversation(conversation)
                return true
            }
        } catch {
            print("Failed to import conversation: \(error)")
        }
        return false
    }
    
    // MARK: - Statistics
    
    func getStatistics() -> ConversationStatistics {
        let totalMessages = conversations.reduce(0) { $0 + $1.messages.count }
        let totalConversations = conversations.count
        let conversationsWithTools = conversations.filter { $0.metadata.hasToolUsage }.count
        let conversationsWithRichContent = conversations.filter { $0.metadata.hasRichContent }.count
        let totalCost = conversations.compactMap { $0.metadata.totalCost }.reduce(0, +)
        
        return ConversationStatistics(
            totalConversations: totalConversations,
            totalMessages: totalMessages,
            conversationsWithTools: conversationsWithTools,
            conversationsWithRichContent: conversationsWithRichContent,
            totalCost: totalCost > 0 ? totalCost : nil,
            averageMessagesPerConversation: totalConversations > 0 ? Double(totalMessages) / Double(totalConversations) : 0
        )
    }
}

struct ConversationStatistics {
    let totalConversations: Int
    let totalMessages: Int
    let conversationsWithTools: Int
    let conversationsWithRichContent: Int
    let totalCost: Double?
    let averageMessagesPerConversation: Double
}

// MARK: - Date Formatters

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
    
    static let readable: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let filenameSafe: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}