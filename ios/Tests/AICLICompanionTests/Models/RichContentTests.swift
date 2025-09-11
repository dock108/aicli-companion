import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class RichContentTests: XCTestCase {
    // MARK: - RichContentType Tests
    
    func testRichContentTypeRawValues() {
        XCTAssertEqual(RichContentType.codeBlock.rawValue, "codeBlock")
        XCTAssertEqual(RichContentType.fileContent.rawValue, "fileContent")
        XCTAssertEqual(RichContentType.commandOutput.rawValue, "commandOutput")
        XCTAssertEqual(RichContentType.toolResult.rawValue, "toolResult")
        XCTAssertEqual(RichContentType.markdown.rawValue, "markdown")
        XCTAssertEqual(RichContentType.attachments.rawValue, "attachments")
    }
    
    func testRichContentTypeCodable() throws {
        let types: [RichContentType] = [
            .codeBlock, .fileContent, .commandOutput,
            .toolResult, .markdown, .attachments
        ]
        
        for type in types {
            let encoder = JSONEncoder()
            let data = try encoder.encode(type)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(RichContentType.self, from: data)
            
            XCTAssertEqual(decoded, type)
        }
    }
    
    // MARK: - CodeBlockData Tests
    
    func testCodeBlockDataInitialization() {
        let codeBlock = CodeBlockData(
            language: "swift",
            code: "let x = 42",
            filename: "test.swift",
            lineNumbers: true
        )
        
        XCTAssertEqual(codeBlock.language, "swift")
        XCTAssertEqual(codeBlock.code, "let x = 42")
        XCTAssertEqual(codeBlock.filename, "test.swift")
        XCTAssertTrue(codeBlock.lineNumbers)
    }
    
    func testCodeBlockDataCodable() throws {
        let original = CodeBlockData(
            language: "python",
            code: "print('Hello')",
            filename: nil,
            lineNumbers: false
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodeBlockData.self, from: data)
        
        XCTAssertEqual(decoded.language, original.language)
        XCTAssertEqual(decoded.code, original.code)
        XCTAssertNil(decoded.filename)
        XCTAssertFalse(decoded.lineNumbers)
    }
    
    // MARK: - FileContentData Tests
    
    func testFileContentDataInitialization() {
        let fileContent = FileContentData(
            filename: "document.txt",
            content: "File contents here",
            mimeType: "text/plain",
            size: 18,
            encoding: "utf-8"
        )
        
        XCTAssertEqual(fileContent.filename, "document.txt")
        XCTAssertEqual(fileContent.content, "File contents here")
        XCTAssertEqual(fileContent.mimeType, "text/plain")
        XCTAssertEqual(fileContent.size, 18)
        XCTAssertEqual(fileContent.encoding, "utf-8")
    }
    
    func testFileContentDataCodable() throws {
        let original = FileContentData(
            filename: "image.png",
            content: "base64data",
            mimeType: "image/png",
            size: 1024,
            encoding: "base64"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FileContentData.self, from: data)
        
        XCTAssertEqual(decoded.filename, original.filename)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.mimeType, original.mimeType)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.encoding, original.encoding)
    }
    
    // MARK: - CommandOutputData Tests
    
    func testCommandOutputDataInitialization() {
        let commandOutput = CommandOutputData(
            command: "ls -la",
            output: "total 0\ndrwxr-xr-x",
            exitCode: 0,
            workingDirectory: "/Users/test"
        )
        
        XCTAssertEqual(commandOutput.command, "ls -la")
        XCTAssertEqual(commandOutput.output, "total 0\ndrwxr-xr-x")
        XCTAssertEqual(commandOutput.exitCode, 0)
        XCTAssertEqual(commandOutput.workingDirectory, "/Users/test")
    }
    
    func testCommandOutputDataWithNilDirectory() {
        let commandOutput = CommandOutputData(
            command: "echo test",
            output: "test",
            exitCode: 0,
            workingDirectory: nil
        )
        
        XCTAssertNil(commandOutput.workingDirectory)
    }
    
    func testCommandOutputDataCodable() throws {
        let original = CommandOutputData(
            command: "git status",
            output: "On branch main",
            exitCode: 0,
            workingDirectory: "/project"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CommandOutputData.self, from: data)
        
        XCTAssertEqual(decoded.command, original.command)
        XCTAssertEqual(decoded.output, original.output)
        XCTAssertEqual(decoded.exitCode, original.exitCode)
        XCTAssertEqual(decoded.workingDirectory, original.workingDirectory)
    }
    
    // MARK: - ToolResultData Tests
    
    func testToolResultDataInitialization() {
        let metadata: [String: AnyCodable] = [
            "duration": AnyCodable(2.5),
            "attempts": AnyCodable(3)
        ]
        
        let toolResult = ToolResultData(
            toolName: "Bash",
            result: "Command executed",
            success: true,
            metadata: metadata
        )
        
        XCTAssertEqual(toolResult.toolName, "Bash")
        XCTAssertEqual(toolResult.result, "Command executed")
        XCTAssertTrue(toolResult.success)
        XCTAssertNotNil(toolResult.metadata)
        XCTAssertEqual(toolResult.metadata?.count, 2)
    }
    
    func testToolResultDataWithoutMetadata() {
        let toolResult = ToolResultData(
            toolName: "Read",
            result: "File contents",
            success: true,
            metadata: nil
        )
        
        XCTAssertNil(toolResult.metadata)
    }
    
    func testToolResultDataCodable() throws {
        let original = ToolResultData(
            toolName: "Write",
            result: "File written",
            success: false,
            metadata: ["error": AnyCodable("Permission denied")]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolResultData.self, from: data)
        
        XCTAssertEqual(decoded.toolName, original.toolName)
        XCTAssertEqual(decoded.result, original.result)
        XCTAssertEqual(decoded.success, original.success)
        XCTAssertNotNil(decoded.metadata)
    }
    
    // MARK: - MarkdownData Tests
    
    func testMarkdownDataInitialization() {
        let markdown = MarkdownData(
            content: "# Header\n\nParagraph",
            renderMode: .full
        )
        
        XCTAssertEqual(markdown.content, "# Header\n\nParagraph")
        XCTAssertEqual(markdown.renderMode, .full)
    }
    
    func testMarkdownRenderModeRawValues() {
        XCTAssertEqual(MarkdownRenderMode.full.rawValue, "full")
        XCTAssertEqual(MarkdownRenderMode.inline.rawValue, "inline")
        XCTAssertEqual(MarkdownRenderMode.code.rawValue, "code")
    }
    
    func testMarkdownDataCodable() throws {
        let original = MarkdownData(
            content: "**Bold** text",
            renderMode: .inline
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MarkdownData.self, from: data)
        
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.renderMode, original.renderMode)
    }
    
    // MARK: - AttachmentInfo Tests
    
    func testAttachmentInfoInitialization() {
        let id = UUID()
        let attachment = AttachmentInfo(
            id: id,
            name: "photo.jpg",
            mimeType: "image/jpeg",
            size: 2048,
            base64Data: "base64string",
            url: "https://example.com/photo.jpg",
            thumbnailBase64: "thumbdata"
        )
        
        XCTAssertEqual(attachment.id, id)
        XCTAssertEqual(attachment.name, "photo.jpg")
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertEqual(attachment.size, 2048)
        XCTAssertEqual(attachment.base64Data, "base64string")
        XCTAssertEqual(attachment.url, "https://example.com/photo.jpg")
        XCTAssertEqual(attachment.thumbnailBase64, "thumbdata")
    }
    
    func testAttachmentInfoDefaults() {
        let attachment = AttachmentInfo(
            name: "file.pdf",
            mimeType: "application/pdf",
            size: 1024
        )
        
        XCTAssertNotNil(attachment.id)
        XCTAssertNil(attachment.base64Data)
        XCTAssertNil(attachment.url)
        XCTAssertNil(attachment.thumbnailBase64)
    }
    
    func testAttachmentInfoCodable() throws {
        let original = AttachmentInfo(
            name: "document.docx",
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            size: 5000,
            base64Data: "documentdata",
            url: nil,
            thumbnailBase64: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AttachmentInfo.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.mimeType, original.mimeType)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.base64Data, original.base64Data)
        XCTAssertNil(decoded.url)
        XCTAssertNil(decoded.thumbnailBase64)
    }
    
    // MARK: - AttachmentsData Tests
    
    func testAttachmentsDataInitialization() {
        let attachment1 = AttachmentInfo(
            name: "file1.txt",
            mimeType: "text/plain",
            size: 100
        )
        
        let attachment2 = AttachmentInfo(
            name: "file2.png",
            mimeType: "image/png",
            size: 200
        )
        
        let attachmentsData = AttachmentsData(
            attachments: [attachment1, attachment2]
        )
        
        XCTAssertEqual(attachmentsData.attachments.count, 2)
        XCTAssertEqual(attachmentsData.attachments[0].name, "file1.txt")
        XCTAssertEqual(attachmentsData.attachments[1].name, "file2.png")
    }
    
    func testAttachmentsDataEmpty() {
        let attachmentsData = AttachmentsData(attachments: [])
        XCTAssertTrue(attachmentsData.attachments.isEmpty)
    }
    
    // MARK: - RichContent Integration Tests
    
    func testRichContentWithCodeBlock() {
        let codeBlockData = CodeBlockData(
            language: "javascript",
            code: "console.log('test')",
            filename: "test.js",
            lineNumbers: true
        )
        
        let richContent = RichContent(
            contentType: .codeBlock,
            data: .codeBlock(codeBlockData)
        )
        
        XCTAssertEqual(richContent.contentType, .codeBlock)
        if case .codeBlock(let data) = richContent.data {
            XCTAssertEqual(data.language, "javascript")
            XCTAssertEqual(data.code, "console.log('test')")
        } else {
            XCTFail("Expected code block data")
        }
    }
    
    func testRichContentWithFileContent() {
        let fileContentData = FileContentData(
            filename: "readme.md",
            content: "# README",
            mimeType: "text/markdown",
            size: 8,
            encoding: "utf-8"
        )
        
        let richContent = RichContent(
            contentType: .fileContent,
            data: .fileContent(fileContentData)
        )
        
        XCTAssertEqual(richContent.contentType, .fileContent)
        if case .fileContent(let data) = richContent.data {
            XCTAssertEqual(data.filename, "readme.md")
            XCTAssertEqual(data.content, "# README")
        } else {
            XCTFail("Expected file content data")
        }
    }
    
    func testRichContentWithCommandOutput() {
        let commandOutputData = CommandOutputData(
            command: "pwd",
            output: "/Users/test",
            exitCode: 0,
            workingDirectory: nil
        )
        
        let richContent = RichContent(
            contentType: .commandOutput,
            data: .commandOutput(commandOutputData)
        )
        
        XCTAssertEqual(richContent.contentType, .commandOutput)
        if case .commandOutput(let data) = richContent.data {
            XCTAssertEqual(data.command, "pwd")
            XCTAssertEqual(data.output, "/Users/test")
            XCTAssertEqual(data.exitCode, 0)
        } else {
            XCTFail("Expected command output data")
        }
    }
    
    func testRichContentCodable() throws {
        let markdownData = MarkdownData(
            content: "## Section",
            renderMode: .full
        )
        
        let original = RichContent(
            contentType: .markdown,
            data: .markdown(markdownData)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RichContent.self, from: data)
        
        XCTAssertEqual(decoded.contentType, original.contentType)
        if case .markdown(let decodedData) = decoded.data,
           case .markdown(let originalData) = original.data {
            XCTAssertEqual(decodedData.content, originalData.content)
            XCTAssertEqual(decodedData.renderMode, originalData.renderMode)
        } else {
            XCTFail("Expected markdown data in both original and decoded")
        }
    }
}
