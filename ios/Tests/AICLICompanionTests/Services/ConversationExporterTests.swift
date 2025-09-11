import XCTest
@testable import AICLICompanion

final class ConversationExporterTests: XCTestCase {
    var exporter: ConversationExporter!
    var sampleConversation: Conversation!
    var multipleConversations: [Conversation]!
    
    override func setUp() {
        super.setUp()
        exporter = ConversationExporter()
        sampleConversation = createSampleConversation()
        multipleConversations = createMultipleConversations()
    }
    
    // MARK: - Single Conversation Export Tests
    
    func testExportToJSON() throws {
        let data = try exporter.export(sampleConversation, to: .json)
        
        XCTAssertGreaterThan(data.count, 0)
        
        // Verify it's valid JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conversation = try decoder.decode(Conversation.self, from: data)
        XCTAssertEqual(conversation.id, sampleConversation.id)
        XCTAssertEqual(conversation.title, sampleConversation.title)
        XCTAssertEqual(conversation.messages.count, sampleConversation.messages.count)
    }
    
    func testExportToMarkdown() throws {
        let data = try exporter.export(sampleConversation, to: .markdown)
        let markdown = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(markdown)
        XCTAssertTrue(markdown!.contains("# Test Conversation"))
        XCTAssertTrue(markdown!.contains("👤 **User**"))
        XCTAssertTrue(markdown!.contains("🤖 **Assistant**"))
        XCTAssertTrue(markdown!.contains("Hello, Claude"))
        XCTAssertTrue(markdown!.contains("Hello! How can I help you?"))
    }
    
    func testExportToText() throws {
        let data = try exporter.export(sampleConversation, to: .text)
        let text = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("Test Conversation"))
        XCTAssertTrue(text!.contains("USER"))
        XCTAssertTrue(text!.contains("ASSISTANT"))
        XCTAssertTrue(text!.contains("Hello, Claude"))
        XCTAssertTrue(text!.contains("Hello! How can I help you?"))
    }
    
    func testExportToHTML() throws {
        let data = try exporter.export(sampleConversation, to: .html)
        let html = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html!.contains("<title>Test Conversation</title>"))
        XCTAssertTrue(html!.contains("👤 User"))
        XCTAssertTrue(html!.contains("🤖 Assistant"))
        XCTAssertTrue(html!.contains("Hello, Claude"))
        XCTAssertTrue(html!.contains("Hello! How can I help you?"))
    }
    
    func testExportToPDF() throws {
        let data = try exporter.export(sampleConversation, to: .pdf)
        
        // Currently returns HTML data as fallback
        XCTAssertGreaterThan(data.count, 0)
        let html = String(data: data, encoding: .utf8)
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("<!DOCTYPE html>"))
    }
    
    // MARK: - Multiple Conversations Export Tests
    
    func testExportMultipleToJSON() throws {
        let data = try exporter.export(multipleConversations, to: .json)
        
        XCTAssertGreaterThan(data.count, 0)
        
        // Verify it's valid JSON structure
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(jsonObject)
        
        if let jsonDict = jsonObject as? [String: Any] {
            let conversations = jsonDict["conversations"] as? [Any]
            XCTAssertEqual(conversations?.count, multipleConversations.count)
            XCTAssertEqual(jsonDict["format"] as? String, "json")
            let totalMessages = jsonDict["totalMessages"] as? Int
            XCTAssertGreaterThan(totalMessages ?? 0, 0)
        }
    }
    
    func testExportMultipleToMarkdown() throws {
        let data = try exporter.export(multipleConversations, to: .markdown)
        let markdown = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(markdown)
        XCTAssertTrue(markdown!.contains("# Multiple Conversations Export"))
        XCTAssertTrue(markdown!.contains("**Total Conversations:** \(multipleConversations.count)"))
        
        // Should contain content from all conversations
        for conversation in multipleConversations {
            XCTAssertTrue(markdown!.contains(conversation.title))
        }
    }
    
    func testExportMultipleToText() throws {
        let data = try exporter.export(multipleConversations, to: .text)
        let text = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("Multiple Conversations Export"))
        XCTAssertTrue(text!.contains("Total Conversations: \(multipleConversations.count)"))
        
        // Should contain content from all conversations
        for conversation in multipleConversations {
            XCTAssertTrue(text!.contains(conversation.title))
        }
    }
    
    func testExportMultipleToHTML() throws {
        let data = try exporter.export(multipleConversations, to: .html)
        let html = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html!.contains("Multiple Conversations Export"))
        XCTAssertTrue(html!.contains("Total Conversations"))
        
        // Should contain content from all conversations
        for conversation in multipleConversations {
            XCTAssertTrue(html!.contains(conversation.title))
        }
    }
    
    func testExportMultipleToPDF() throws {
        let data = try exporter.export(multipleConversations, to: .pdf)
        
        // Currently returns HTML data as fallback
        XCTAssertGreaterThan(data.count, 0)
        let html = String(data: data, encoding: .utf8)
        XCTAssertNotNil(html)
        XCTAssertTrue(html!.contains("<!DOCTYPE html>"))
    }
    
    // MARK: - Rich Content Export Tests
    
    func testExportWithCodeBlockRichContent() throws {
        let conversation = createConversationWithRichContent(.codeBlock(CodeBlockData(
            language: "swift",
            code: "func test() {\n    print(\"Hello\")\n}",
            filename: "test.swift",
            lineNumbers: true
        )))
        
        let markdownData = try exporter.export(conversation, to: .markdown)
        let markdown = String(data: markdownData, encoding: .utf8)!
        
        XCTAssertTrue(markdown.contains("```swift"))
        XCTAssertTrue(markdown.contains("func test()"))
        
        let htmlData = try exporter.export(conversation, to: .html)
        let html = String(data: htmlData, encoding: .utf8)!
        
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("func test()"))
    }
    
    func testExportWithFileContentRichContent() throws {
        let conversation = createConversationWithRichContent(.fileContent(FileContentData(
            filename: "test.txt",
            content: "This is a test file",
            mimeType: "text/plain",
            size: 19,
            encoding: "utf-8"
        )))
        
        let markdownData = try exporter.export(conversation, to: .markdown)
        let markdown = String(data: markdownData, encoding: .utf8)!
        
        XCTAssertTrue(markdown.contains("**File:** `test.txt`"))
        XCTAssertTrue(markdown.contains("This is a test file"))
        
        let htmlData = try exporter.export(conversation, to: .html)
        let html = String(data: htmlData, encoding: .utf8)!
        
        XCTAssertTrue(html.contains("<h4>File: test.txt</h4>"))
        XCTAssertTrue(html.contains("This is a test file"))
    }
    
    func testExportWithCommandOutputRichContent() throws {
        let conversation = createConversationWithRichContent(.commandOutput(CommandOutputData(
            command: "ls -la",
            output: "total 0\ndrwxr-xr-x  2 user  staff  64 Jan  1 12:00 .",
            exitCode: 0,
            workingDirectory: "/tmp"
        )))
        
        let textData = try exporter.export(conversation, to: .text)
        let text = String(data: textData, encoding: .utf8)!
        
        XCTAssertTrue(text.contains("[COMMAND: ls -la]"))
        XCTAssertTrue(text.contains("total 0"))
    }
    
    func testExportWithToolResultRichContent() throws {
        let conversation = createConversationWithRichContent(.toolResult(ToolResultData(
            toolName: "calculator",
            result: "42",
            success: true,
            metadata: nil
        )))
        
        let markdownData = try exporter.export(conversation, to: .markdown)
        let markdown = String(data: markdownData, encoding: .utf8)!
        
        XCTAssertTrue(markdown.contains("**Tool:** calculator"))
        XCTAssertTrue(markdown.contains("42"))
    }
    
    func testExportWithAttachmentsRichContent() throws {
        let attachment = AttachmentInfo(
            id: UUID(),
            name: "image.png",
            mimeType: "image/png",
            size: 1024,
            base64Data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==",
            url: nil,
            thumbnailBase64: nil
        )
        
        let conversation = createConversationWithRichContent(.attachments(AttachmentsData(
            attachments: [attachment]
        )))
        
        let markdownData = try exporter.export(conversation, to: .markdown)
        let markdown = String(data: markdownData, encoding: .utf8)!
        
        XCTAssertTrue(markdown.contains("📎 image.png"))
        
        let htmlData = try exporter.export(conversation, to: .html)
        let html = String(data: htmlData, encoding: .utf8)!
        
        XCTAssertTrue(html.contains("<strong>Attachments:</strong>"))
        XCTAssertTrue(html.contains("image.png"))
    }
    
    // MARK: - Edge Cases and Error Handling Tests
    
    func testExportEmptyConversation() throws {
        let emptyConversation = Conversation(title: "Empty Conversation")
        
        let data = try exporter.export(emptyConversation, to: .json)
        XCTAssertGreaterThan(data.count, 0)
        
        // Just verify it's valid JSON structure
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(jsonObject)
        
        if let jsonDict = jsonObject as? [String: Any] {
            XCTAssertEqual(jsonDict["title"] as? String, "Empty Conversation")
            let messages = jsonDict["messages"] as? [Any]
            XCTAssertEqual(messages?.count, 0)
        }
    }
    
    func testExportEmptyConversationToMarkdown() throws {
        let emptyConversation = Conversation(title: "Empty Conversation")
        
        let data = try exporter.export(emptyConversation, to: .markdown)
        let markdown = String(data: data, encoding: .utf8)!
        
        XCTAssertTrue(markdown.contains("# Empty Conversation"))
        XCTAssertTrue(markdown.contains("**Created:**"))
        XCTAssertTrue(markdown.contains("**Last Updated:**"))
    }
    
    func testExportConversationWithWorkingDirectory() throws {
        var conversation = sampleConversation!
        conversation.workingDirectory = "/Users/test/project"
        
        let markdownData = try exporter.export(conversation, to: .markdown)
        let markdown = String(data: markdownData, encoding: .utf8)!
        
        XCTAssertTrue(markdown.contains("**Working Directory:** `/Users/test/project`"))
        
        let htmlData = try exporter.export(conversation, to: .html)
        let html = String(data: htmlData, encoding: .utf8)!
        
        XCTAssertTrue(html.contains("<strong>Working Directory:</strong> <code>/Users/test/project</code>"))
    }
    
    func testExportWithSpecialCharacters() throws {
        let conversation = createConversationWithSpecialCharacters()
        
        let htmlData = try exporter.export(conversation, to: .html)
        let html = String(data: htmlData, encoding: .utf8)!
        
        // Should handle line breaks properly
        XCTAssertTrue(html.contains("<br>"))
        
        let jsonData = try exporter.export(conversation, to: .json)
        // Should not throw when encoding special characters
        XCTAssertGreaterThan(jsonData.count, 0)
    }
    
    // MARK: - DateFormatter Tests
    
    func testDateFormatterExtensions() {
        let date = Date()
        
        let exportFormatted = DateFormatter.exportFormatter.string(from: date)
        XCTAssertFalse(exportFormatted.isEmpty)
        
        let messageFormatted = DateFormatter.messageFormatter.string(from: date)
        XCTAssertFalse(messageFormatted.isEmpty)
        
        let timeOnlyFormatted = DateFormatter.timeOnly.string(from: date)
        XCTAssertFalse(timeOnlyFormatted.isEmpty)
    }
    
    // MARK: - ExportFormat Tests
    
    func testExportFormatProperties() {
        XCTAssertEqual(ExportFormat.json.displayName, "JSON")
        XCTAssertEqual(ExportFormat.markdown.displayName, "Markdown")
        XCTAssertEqual(ExportFormat.text.displayName, "Plain Text")
        XCTAssertEqual(ExportFormat.html.displayName, "HTML")
        XCTAssertEqual(ExportFormat.pdf.displayName, "PDF")
        
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.text.fileExtension, "txt")
        XCTAssertEqual(ExportFormat.html.fileExtension, "html")
        XCTAssertEqual(ExportFormat.pdf.fileExtension, "pdf")
        
        XCTAssertEqual(ExportFormat.json.mimeType, "application/json")
        XCTAssertEqual(ExportFormat.markdown.mimeType, "text/markdown")
        XCTAssertEqual(ExportFormat.text.mimeType, "text/plain")
        XCTAssertEqual(ExportFormat.html.mimeType, "text/html")
        XCTAssertEqual(ExportFormat.pdf.mimeType, "application/pdf")
    }
    
    func testExportFormatCodable() throws {
        let format = ExportFormat.json
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(format)
        
        let decoder = JSONDecoder()
        let decodedFormat = try decoder.decode(ExportFormat.self, from: data)
        
        XCTAssertEqual(format, decodedFormat)
    }
    
    func testExportFormatCaseIterable() {
        let allFormats = ExportFormat.allCases
        XCTAssertEqual(allFormats.count, 5)
        XCTAssertTrue(allFormats.contains(.json))
        XCTAssertTrue(allFormats.contains(.markdown))
        XCTAssertTrue(allFormats.contains(.text))
        XCTAssertTrue(allFormats.contains(.html))
        XCTAssertTrue(allFormats.contains(.pdf))
    }
    
    // MARK: - MultipleConversationsExport Tests
    
    func testMultipleConversationsExportCreation() {
        let conversations = createMultipleConversations()
        let export = MultipleConversationsExport(conversations: conversations, format: .json)
        
        XCTAssertEqual(export.conversations.count, conversations.count)
        XCTAssertEqual(export.format, .json)
        XCTAssertGreaterThan(export.totalMessages, 0)
        XCTAssertLessThanOrEqual(export.exportedAt.timeIntervalSinceNow, 0)
        XCTAssertGreaterThan(export.exportedAt.timeIntervalSinceNow, -1)
    }
    
    func testMultipleConversationsExportCodable() throws {
        let conversations = createMultipleConversations()
        let export = MultipleConversationsExport(conversations: conversations, format: .markdown)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedExport = try decoder.decode(MultipleConversationsExport.self, from: data)
        
        XCTAssertEqual(decodedExport.conversations.count, export.conversations.count)
        XCTAssertEqual(decodedExport.format, export.format)
        XCTAssertEqual(decodedExport.totalMessages, export.totalMessages)
    }
    
    // MARK: - Performance Tests
    
    func testExportLargeConversation() throws {
        let largeConversation = createLargeConversation()
        
        let startTime = Date()
        let data = try exporter.export(largeConversation, to: .json)
        let exportTime = Date().timeIntervalSince(startTime)
        
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertLessThan(exportTime, 1.0) // Should complete within 1 second
    }
    
    func testExportMultipleLargeConversations() throws {
        let conversations = (0..<5).map { _ in createLargeConversation() }
        
        let startTime = Date()
        let data = try exporter.export(conversations, to: .markdown)
        let exportTime = Date().timeIntervalSince(startTime)
        
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertLessThan(exportTime, 3.0) // Should complete within 3 seconds
    }
    
    // MARK: - Helper Methods
    
    private func createSampleConversation() -> Conversation {
        var conversation = Conversation(title: "Test Conversation")
        
        let userMessage = Message(
            content: "Hello, Claude",
            sender: .user,
            timestamp: Date().addingTimeInterval(-120) // 2 minutes ago
        )
        
        let assistantMessage = Message(
            content: "Hello! How can I help you?",
            sender: .assistant,
            timestamp: Date().addingTimeInterval(-60) // 1 minute ago
        )
        
        conversation.addMessage(userMessage)
        conversation.addMessage(assistantMessage)
        
        return conversation
    }
    
    private func createMultipleConversations() -> [Conversation] {
        var conversations: [Conversation] = []
        
        for i in 1...3 {
            var conversation = Conversation(title: "Conversation \(i)")
            
            let message = Message(
                content: "This is message in conversation \(i)",
                sender: .user,
                timestamp: Date().addingTimeInterval(-TimeInterval(i * 60))
            )
            
            conversation.addMessage(message)
            conversations.append(conversation)
        }
        
        return conversations
    }
    
    private func createConversationWithRichContent(_ richContentData: RichContentData) -> Conversation {
        var conversation = Conversation(title: "Rich Content Test")
        
        let richContent = RichContent(
            contentType: richContentData.contentType,
            data: richContentData
        )
        
        let message = Message(
            content: "Here's some rich content",
            sender: .assistant,
            richContent: richContent
        )
        
        conversation.addMessage(message)
        return conversation
    }
    
    private func createConversationWithSpecialCharacters() -> Conversation {
        var conversation = Conversation(title: "Special Characters Test")
        
        let message = Message(
            content: "Here are some special characters: <>&\"'\nNew line\tTab character",
            sender: .user
        )
        
        conversation.addMessage(message)
        return conversation
    }
    
    private func createLargeConversation() -> Conversation {
        var conversation = Conversation(title: "Large Conversation")
        
        for i in 0..<100 {
            let message = Message(
                content: "This is message number \(i) in a large conversation. ".repeated(10),
                sender: i % 2 == 0 ? .user : .assistant,
                timestamp: Date().addingTimeInterval(-TimeInterval(i))
            )
            
            conversation.addMessage(message)
        }
        
        return conversation
    }
}

// MARK: - String Extension for Testing

private extension String {
    func repeated(_ times: Int) -> String {
        return String(repeating: self, count: times)
    }
}

// MARK: - RichContentData Extension for Testing

private extension RichContentData {
    var contentType: RichContentType {
        switch self {
        case .codeBlock: return .codeBlock
        case .fileContent: return .fileContent
        case .commandOutput: return .commandOutput
        case .toolResult: return .toolResult
        case .markdown: return .markdown
        case .attachments: return .attachments
        }
    }
}
