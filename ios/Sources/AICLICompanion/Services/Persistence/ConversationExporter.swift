import Foundation

// MARK: - Conversation Export Operations

class ConversationExporter {
    // MARK: - Single Conversation Export
    
    func export(_ conversation: Conversation, to format: ExportFormat) throws -> Data {
        switch format {
        case .json:
            return try exportToJSON(conversation)
        case .markdown:
            return try exportToMarkdown(conversation)
        case .text:
            return try exportToText(conversation)
        case .html:
            return try exportToHTML(conversation)
        case .pdf:
            return try exportToPDF(conversation)
        }
    }
    
    // MARK: - Multiple Conversations Export
    
    func export(_ conversations: [Conversation], to format: ExportFormat) throws -> Data {
        let multipleExport = MultipleConversationsExport(conversations: conversations, format: format)
        
        switch format {
        case .json:
            return try JSONEncoder().encode(multipleExport)
        case .markdown:
            return try exportMultipleToMarkdown(conversations)
        case .text:
            return try exportMultipleToText(conversations)
        case .html:
            return try exportMultipleToHTML(conversations)
        case .pdf:
            return try exportMultipleToPDF(conversations)
        }
    }
    
    // MARK: - Private Export Methods
    
    private func exportToJSON(_ conversation: Conversation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(conversation)
    }
    
    private func exportToMarkdown(_ conversation: Conversation) throws -> Data {
        var markdown = "# \(conversation.title)\n\n"
        markdown += "**Created:** \(DateFormatter.exportFormatter.string(from: conversation.createdAt))\n"
        markdown += "**Last Updated:** \(DateFormatter.exportFormatter.string(from: conversation.updatedAt))\n"
        
        if let workingDirectory = conversation.workingDirectory {
            markdown += "**Working Directory:** `\(workingDirectory)`\n"
        }
        
        markdown += "\n---\n\n"
        
        for message in conversation.messages {
            let sender = message.sender == .user ? "👤 **User**" : "🤖 **Assistant**"
            let timestamp = DateFormatter.messageFormatter.string(from: message.timestamp)
            
            markdown += "## \(sender) (\(timestamp))\n\n"
            markdown += "\(message.content)\n\n"
            
            if let richContent = message.richContent {
                markdown += formatRichContentForMarkdown(richContent)
                markdown += "\n"
            }
            
            markdown += "---\n\n"
        }
        
        return markdown.data(using: .utf8) ?? Data()
    }
    
    private func exportToText(_ conversation: Conversation) throws -> Data {
        var text = "\(conversation.title)\n"
        text += String(repeating: "=", count: conversation.title.count) + "\n\n"
        text += "Created: \(DateFormatter.exportFormatter.string(from: conversation.createdAt))\n"
        text += "Last Updated: \(DateFormatter.exportFormatter.string(from: conversation.updatedAt))\n"
        
        if let workingDirectory = conversation.workingDirectory {
            text += "Working Directory: \(workingDirectory)\n"
        }
        
        text += "\n" + String(repeating: "-", count: 50) + "\n\n"
        
        for message in conversation.messages {
            let sender = message.sender == .user ? "USER" : "ASSISTANT"
            let timestamp = DateFormatter.messageFormatter.string(from: message.timestamp)
            
            text += "[\(sender)] \(timestamp)\n"
            text += "\(message.content)\n\n"
            
            if let richContent = message.richContent {
                text += formatRichContentForText(richContent)
                text += "\n"
            }
            
            text += String(repeating: "-", count: 30) + "\n\n"
        }
        
        return text.data(using: .utf8) ?? Data()
    }
    
    private func exportToHTML(_ conversation: Conversation) throws -> Data {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>\(conversation.title)</title>
            <meta charset="utf-8">
            <style>
                body { font-family: system-ui, -apple-system, sans-serif; margin: 40px; }
                .header { border-bottom: 2px solid #eee; padding-bottom: 20px; margin-bottom: 30px; }
                .message { margin-bottom: 30px; padding: 20px; border-radius: 8px; }
                .user { background-color: #f0f8ff; }
                .assistant { background-color: #f8f8f8; }
                .timestamp { color: #666; font-size: 0.9em; }
                .content { margin-top: 10px; line-height: 1.6; }
                pre { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>\(conversation.title)</h1>
                <p><strong>Created:</strong> \(DateFormatter.exportFormatter.string(from: conversation.createdAt))</p>
                <p><strong>Last Updated:</strong> \(DateFormatter.exportFormatter.string(from: conversation.updatedAt))</p>
        """
        
        if let workingDirectory = conversation.workingDirectory {
            html += "<p><strong>Working Directory:</strong> <code>\(workingDirectory)</code></p>"
        }
        
        html += "</div>"
        
        for message in conversation.messages {
            let senderClass = message.sender == .user ? "user" : "assistant"
            let senderName = message.sender == .user ? "👤 User" : "🤖 Assistant"
            let timestamp = DateFormatter.messageFormatter.string(from: message.timestamp)
            
            html += """
            <div class="message \(senderClass)">
                <div class="timestamp">\(senderName) - \(timestamp)</div>
                <div class="content">\(message.content.replacingOccurrences(of: "\n", with: "<br>"))</div>
            """
            
            if let richContent = message.richContent {
                html += formatRichContentForHTML(richContent)
            }
            
            html += "</div>"
        }
        
        html += "</body></html>"
        
        return html.data(using: .utf8) ?? Data()
    }
    
    private func exportToPDF(_ conversation: Conversation) throws -> Data {
        // For now, return HTML as base - PDF generation would require additional framework
        return try exportToHTML(conversation)
    }
    
    // MARK: - Multiple Conversations Export
    
    private func exportMultipleToMarkdown(_ conversations: [Conversation]) throws -> Data {
        var markdown = "# Multiple Conversations Export\n\n"
        markdown += "**Exported on:** \(DateFormatter.exportFormatter.string(from: Date()))\n"
        markdown += "**Total Conversations:** \(conversations.count)\n\n"
        
        for conversation in conversations {
            let conversationData = try exportToMarkdown(conversation)
            if let conversationMarkdown = String(data: conversationData, encoding: .utf8) {
                markdown += conversationMarkdown + "\n\n"
            }
        }
        
        return markdown.data(using: .utf8) ?? Data()
    }
    
    private func exportMultipleToText(_ conversations: [Conversation]) throws -> Data {
        var text = "Multiple Conversations Export\n"
        text += String(repeating: "=", count: 32) + "\n\n"
        text += "Exported on: \(DateFormatter.exportFormatter.string(from: Date()))\n"
        text += "Total Conversations: \(conversations.count)\n\n"
        
        for conversation in conversations {
            let conversationData = try exportToText(conversation)
            if let conversationText = String(data: conversationData, encoding: .utf8) {
                text += conversationText + "\n\n"
            }
        }
        
        return text.data(using: .utf8) ?? Data()
    }
    
    private func exportMultipleToHTML(_ conversations: [Conversation]) throws -> Data {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Multiple Conversations Export</title>
            <meta charset="utf-8">
            <style>
                body { font-family: system-ui, -apple-system, sans-serif; margin: 40px; }
                .export-header { border-bottom: 3px solid #ddd; padding-bottom: 20px; margin-bottom: 40px; }
                .conversation-separator { border-top: 2px solid #eee; margin: 40px 0; padding-top: 20px; }
            </style>
        </head>
        <body>
            <div class="export-header">
                <h1>Multiple Conversations Export</h1>
                <p><strong>Exported on:</strong> \(DateFormatter.exportFormatter.string(from: Date()))</p>
                <p><strong>Total Conversations:</strong> \(conversations.count)</p>
            </div>
        """
        
        for (index, conversation) in conversations.enumerated() {
            if index > 0 {
                html += "<div class='conversation-separator'></div>"
            }
            
            let conversationData = try exportToHTML(conversation)
            if let conversationHTML = String(data: conversationData, encoding: .utf8) {
                // Extract body content from the individual HTML
                let bodyStart = conversationHTML.range(of: "<body>")?.upperBound
                let bodyEnd = conversationHTML.range(of: "</body>")?.lowerBound
                
                if let start = bodyStart, let end = bodyEnd {
                    let bodyContent = String(conversationHTML[start..<end])
                    html += bodyContent
                }
            }
        }
        
        html += "</body></html>"
        
        return html.data(using: .utf8) ?? Data()
    }
    
    private func exportMultipleToPDF(_ conversations: [Conversation]) throws -> Data {
        // For now, return HTML as base - PDF generation would require additional framework
        return try exportMultipleToHTML(conversations)
    }
    
    // MARK: - Rich Content Formatting
    
    private func formatRichContentForMarkdown(_ richContent: RichContent) -> String {
        switch richContent.data {
        case .codeBlock(let data):
            return "```\(data.language ?? "")\n\(data.code)\n```"
        case .fileContent(let data):
            return "**File:** `\(data.filename)`\n```\n\(data.content)\n```"
        case .commandOutput(let data):
            return "**Command:** `\(data.command)`\n```\n\(data.output)\n```"
        case .toolResult(let data):
            return "**Tool:** \(data.toolName)\n```\n\(data.result)\n```"
        case .markdown(let data):
            return data.content
        case .attachments(let data):
            return data.attachments.map { "📎 \($0.name)" }.joined(separator: ", ")
        }
    }
    
    private func formatRichContentForText(_ richContent: RichContent) -> String {
        switch richContent.data {
        case .codeBlock(let data):
            return "[CODE: \(data.language ?? "unknown")]\n\(data.code)\n[END CODE]"
        case .fileContent(let data):
            return "[FILE: \(data.filename)]\n\(data.content)\n[END FILE]"
        case .commandOutput(let data):
            return "[COMMAND: \(data.command)]\n\(data.output)\n[END COMMAND]"
        case .toolResult(let data):
            return "[TOOL: \(data.toolName)]\n\(data.result)\n[END TOOL]"
        case .markdown(let data):
            return data.content
        case .attachments(let data):
            return "[ATTACHMENTS: \(data.attachments.map { $0.name }.joined(separator: ", "))]"
        }
    }
    
    private func formatRichContentForHTML(_ richContent: RichContent) -> String {
        switch richContent.data {
        case .codeBlock(let data):
            return "<pre><code>\(data.code)</code></pre>"
        case .fileContent(let data):
            return "<h4>File: \(data.filename)</h4><pre><code>\(data.content)</code></pre>"
        case .commandOutput(let data):
            return "<h4>Command: \(data.command)</h4><pre><code>\(data.output)</code></pre>"
        case .toolResult(let data):
            return "<h4>Tool: \(data.toolName)</h4><pre><code>\(data.result)</code></pre>"
        case .markdown(let data):
            return data.content.replacingOccurrences(of: "\n", with: "<br>")
        case .attachments(let data):
            return "<p><strong>Attachments:</strong> \(data.attachments.map { $0.name }.joined(separator: ", "))</p>"
        }
    }
}

// MARK: - DateFormatter Extensions

extension DateFormatter {
    static let exportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter
    }()
    
    static let messageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
