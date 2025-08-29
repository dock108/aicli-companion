import SwiftUI
import Foundation

// MARK: - File Path Metadata

struct FilePathMetadata: Codable, Hashable {
    let path: String
    let lineNumber: Int?
}

// MARK: - AttributedString Extension for File Paths

struct FilePathAttributeKey: AttributedStringKey {
    typealias Value = FilePathMetadata
    static let name = "filePathMetadata"
}

extension AttributeScopes.SwiftUIAttributes {
    var filePathMetadata: FilePathAttributeKey.Type { FilePathAttributeKey.self }
}

extension AttributedString {
    var filePathMetadata: FilePathMetadata? {
        get { self[FilePathAttributeKey.self] }
        set { self[FilePathAttributeKey.self] = newValue }
    }
}

// MARK: - Markdown Parsing Utilities

struct MarkdownParser {
    // MARK: - Content Part Types
    
    enum ContentPart {
        case text(String)
        case bold(String)
        case italic(String)
        case code(String)
        case link(String, url: String)
        case filePath(String, lineNumber: Int?)
        case heading(level: Int, text: String)
        case listItem(String)
        case codeBlock(String, language: String?)
    }
    
    // MARK: - Main Parsing Methods
    
    static func parseMarkdown(_ text: String) -> AttributedString {
        let contentParts = parseMessageContent(text)
        var attributedString = AttributedString()
        
        for (index, part) in contentParts.enumerated() {
            let isLastPart = (index == contentParts.count - 1)
            
            switch part {
            case .text(let string):
                attributedString += AttributedString(string)
            case .bold(let string):
                var boldString = AttributedString(string)
                boldString.font = .body.bold()
                attributedString += boldString
            case .italic(let string):
                var italicString = AttributedString(string)
                italicString.font = .body.italic()
                attributedString += italicString
            case .code(let string):
                var codeString = AttributedString(string)
                codeString.font = .system(.body, design: .monospaced)
                codeString.backgroundColor = .secondary.opacity(0.2)
                attributedString += codeString
            case .link(let text, let url):
                var linkString = AttributedString(text)
                linkString.foregroundColor = .blue
                linkString.underlineStyle = .single
                if let linkURL = URL(string: url) {
                    linkString.link = linkURL
                }
                attributedString += linkString
            case .filePath(let path, let lineNumber):
                var filePathString = AttributedString(path)
                filePathString.foregroundColor = .blue
                filePathString.underlineStyle = .single
                // Create a custom URL that we can parse later
                // Using a custom scheme to avoid file:// URL parsing issues
                var urlString = "aicli-file://\(path)"
                if let lineNumber = lineNumber {
                    urlString += "#\(lineNumber)"
                }
                if let url = URL(string: urlString) {
                    filePathString.link = url
                }
                // Also store file path metadata for debugging
                filePathString.filePathMetadata = FilePathMetadata(path: path, lineNumber: lineNumber)
                print("📄 [MARKDOWN PARSER] Added file path as link: \(path), line: \(lineNumber?.description ?? "nil")")
                attributedString += filePathString
            case .heading(let level, let text):
                var headingString = AttributedString(text)
                headingString.font = headingFont(for: level)
                headingString.foregroundColor = .primary
                // Add spacing before heading if not first element
                if index > 0 {
                    attributedString += AttributedString("\n")
                }
                attributedString += headingString
                // Only add newline if not the last element
                if !isLastPart {
                    attributedString += AttributedString("\n\n")
                }
            case .listItem(let text):
                // Add small spacing before list items (but not excessive)
                if index > 0 && !isFirstListItem(at: index, in: contentParts) {
                    attributedString += AttributedString("\n")
                }
                
                // Add bullet point
                attributedString += AttributedString("• ")
                
                // Parse the list item text for inline formatting including file paths
                let inlineParts = parseInlineMarkdown(text)
                for inlinePart in inlineParts {
                    switch inlinePart {
                    case .text(let string):
                        attributedString += AttributedString(string)
                    case .bold(let string):
                        var boldString = AttributedString(string)
                        boldString.font = .body.bold()
                        attributedString += boldString
                    case .italic(let string):
                        var italicString = AttributedString(string)
                        italicString.font = .body.italic()
                        attributedString += italicString
                    case .code(let string):
                        var codeString = AttributedString(string)
                        codeString.font = .system(.body, design: .monospaced)
                        codeString.backgroundColor = .secondary.opacity(0.2)
                        attributedString += codeString
                    case .link(let text, let url):
                        var linkString = AttributedString(text)
                        linkString.foregroundColor = .blue
                        linkString.underlineStyle = .single
                        if let linkURL = URL(string: url) {
                            linkString.link = linkURL
                        }
                        attributedString += linkString
                    case .filePath(let path, let lineNumber):
                        var filePathString = AttributedString(path)
                        filePathString.foregroundColor = .blue
                        filePathString.underlineStyle = .single
                        // Create a custom URL that we can parse later
                        // Using a custom scheme to avoid file:// URL parsing issues
                        var urlString = "aicli-file://\(path)"
                        if let lineNumber = lineNumber {
                            urlString += "#\(lineNumber)"
                        }
                        if let url = URL(string: urlString) {
                            filePathString.link = url
                        }
                        // Also store file path metadata for debugging
                        filePathString.filePathMetadata = FilePathMetadata(path: path, lineNumber: lineNumber)
                        print("📄 [MARKDOWN PARSER] Added inline file path as link: \(path), line: \(lineNumber?.description ?? "nil")")
                        attributedString += filePathString
                    default:
                        // For any other inline parts, just add as text
                        attributedString += AttributedString("\(inlinePart)")
                    }
                }
                
                // Only add newline if not the last element
                if !isLastPart {
                    attributedString += AttributedString("\n")
                }
            case .codeBlock(let code, _):
                var codeString = AttributedString(code.trimmingCharacters(in: .newlines))
                codeString.font = .system(.body, design: .monospaced)
                codeString.backgroundColor = .secondary.opacity(0.1)
                // Add spacing around code blocks only if not at edges
                if index > 0 {
                    attributedString += AttributedString("\n")
                }
                attributedString += codeString
                if !isLastPart {
                    attributedString += AttributedString("\n")
                }
            }
        }
        
        return attributedString
    }
    
    static func parseMessageContent(_ content: String) -> [ContentPart] {
        let lines = content.components(separatedBy: .newlines)
        var parts: [ContentPart] = []
        var inCodeBlock = false
        var codeBlockContent = ""
        var codeBlockLanguage: String?
        
        for (index, line) in lines.enumerated() {
            let isLastLine = (index == lines.count - 1)
            
            // Check for code block start/end
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End of code block
                    parts.append(.codeBlock(codeBlockContent, language: codeBlockLanguage))
                    inCodeBlock = false
                    codeBlockContent = ""
                    codeBlockLanguage = nil
                } else {
                    // Start of code block
                    inCodeBlock = true
                    codeBlockLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if codeBlockLanguage?.isEmpty == true {
                        codeBlockLanguage = nil
                    }
                }
                continue
            }
            
            if inCodeBlock {
                codeBlockContent += line + "\n"
                continue
            }
            
            // Parse regular content
            if let heading = parseHeading(line) {
                parts.append(heading)
            } else if let listItem = parseListItem(line) {
                parts.append(listItem)
            } else {
                let inlineParts = parseInlineMarkdown(line)
                // Only add non-empty inline parts
                if !inlineParts.isEmpty && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(contentsOf: inlineParts)
                    // Only add newline if not the last line
                    if !isLastLine {
                        parts.append(.text("\n"))
                    }
                }
            }
        }
        
        return parts
    }
    
    // MARK: - Specific Parsing Functions
    
    private static func parseHeading(_ line: String) -> ContentPart? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("#### ") {
            return .heading(level: 4, text: String(trimmed.dropFirst(5)))
        } else if trimmed.hasPrefix("### ") {
            return .heading(level: 3, text: String(trimmed.dropFirst(4)))
        } else if trimmed.hasPrefix("## ") {
            return .heading(level: 2, text: String(trimmed.dropFirst(3)))
        } else if trimmed.hasPrefix("# ") {
            return .heading(level: 1, text: String(trimmed.dropFirst(2)))
        }
        
        return nil
    }
    
    private static func parseListItem(_ line: String) -> ContentPart? {
        let trimmed = line.trimmingCharacters(in: .leadingWhitespaces)
        
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            let prefix = trimmed.hasPrefix("• ") ? "• " : (trimmed.hasPrefix("- ") ? "- " : "* ")
            return .listItem(String(trimmed.dropFirst(prefix.count)))
        }
        
        return nil
    }
    
    private static func parseInlineMarkdown(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var remaining = text
        
        while !remaining.isEmpty {
            // Check for file paths first (before links)
            if let (filePathPart, filePathRange) = parseFilePath(from: remaining) {
                // Add text before file path if any
                let beforeFilePath = String(remaining[remaining.startIndex..<filePathRange.lowerBound])
                if !beforeFilePath.isEmpty {
                    parts.append(contentsOf: parseFormattedText(beforeFilePath))
                }
                
                parts.append(filePathPart)
                remaining = String(remaining[filePathRange.upperBound...])
                continue
            }
            
            // Check for links
            if let (linkPart, linkRange) = parseLink(from: remaining) {
                // Add text before link if any
                let beforeLink = String(remaining[remaining.startIndex..<linkRange.lowerBound])
                if !beforeLink.isEmpty {
                    parts.append(contentsOf: parseFormattedText(beforeLink))
                }
                
                parts.append(linkPart)
                remaining = String(remaining[linkRange.upperBound...])
                continue
            }
            
            // Parse other formatting
            let formattedParts = parseFormattedText(remaining)
            parts.append(contentsOf: formattedParts)
            break
        }
        
        return parts
    }
    
    private static func parseFormattedText(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var remaining = text
        
        while !remaining.isEmpty {
            // Look for inline code first (highest priority)
            if let codeRange = remaining.range(of: "`([^`]+)`", options: .regularExpression) {
                // Add text before code
                let beforeCode = String(remaining[remaining.startIndex..<codeRange.lowerBound])
                if !beforeCode.isEmpty {
                    parts.append(contentsOf: parseItalicText(beforeCode))
                }
                
                // Extract code content
                let codeMatch = String(remaining[codeRange])
                let codeContent = String(codeMatch.dropFirst().dropLast()) // Remove backticks
                parts.append(.code(codeContent))
                
                remaining = String(remaining[codeRange.upperBound...])
                continue
            }
            
            // Parse bold and italic
            parts.append(contentsOf: parseItalicText(remaining))
            break
        }
        
        return parts
    }
    
    private static func parseItalicText(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var remaining = text
        
        while !remaining.isEmpty {
            // Look for bold text first (**text**)
            if let boldRange = remaining.range(of: "\\*\\*([^*]+)\\*\\*", options: .regularExpression) {
                // Add text before bold
                let beforeBold = String(remaining[remaining.startIndex..<boldRange.lowerBound])
                if !beforeBold.isEmpty {
                    parts.append(.text(beforeBold))
                }
                
                // Extract bold content
                let boldMatch = String(remaining[boldRange])
                let boldContent = String(boldMatch.dropFirst(2).dropLast(2)) // Remove **
                parts.append(.bold(boldContent))
                
                remaining = String(remaining[boldRange.upperBound...])
                continue
            }
            
            // Look for italic text (*text*)
            if let italicRange = remaining.range(of: "\\*([^*]+)\\*", options: .regularExpression) {
                // Add text before italic
                let beforeItalic = String(remaining[remaining.startIndex..<italicRange.lowerBound])
                if !beforeItalic.isEmpty {
                    parts.append(.text(beforeItalic))
                }
                
                // Extract italic content
                let italicMatch = String(remaining[italicRange])
                let italicContent = String(italicMatch.dropFirst().dropLast()) // Remove *
                parts.append(.italic(italicContent))
                
                remaining = String(remaining[italicRange.upperBound...])
                continue
            }
            
            // No more formatting found, add remaining text
            parts.append(.text(remaining))
            break
        }
        
        return parts
    }
    
    private static func parseLink(from text: String) -> (part: ContentPart, range: Range<String.Index>)? {
        // Look for markdown links [text](url)
        guard let linkRange = text.range(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: .regularExpression) else {
            return nil
        }
        
        _ = String(text[linkRange])
        
        // Extract text and URL using regex groups
        // swiftlint:disable:next force_try
        let regex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
        _ = NSRange(linkRange, in: text)
        
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3 else {
            return nil
        }
        
        let textRange = Range(match.range(at: 1), in: text)!
        let urlRange = Range(match.range(at: 2), in: text)!
        
        let linkText = String(text[textRange])
        let linkURL = String(text[urlRange])
        
        return (.link(linkText, url: linkURL), linkRange)
    }
    
    private static func parseFilePath(from text: String) -> (part: ContentPart, range: Range<String.Index>)? {
        // File path patterns to match - simplified for better reliability
        let patterns = [
            // Pattern 1: Backtick-enclosed filenames: `filename.py`, `README_LOTTERY.md`
            "`([a-zA-Z0-9_.-]+\\.[a-zA-Z0-9]{1,10})`",
            
            // Pattern 2: Simple standalone filenames with word boundaries
            "\\b([a-zA-Z][a-zA-Z0-9_.-]*\\.[a-zA-Z0-9]{1,6})\\b",
            
            // Pattern 3: Paths with directories
            "\\b((?:[a-zA-Z0-9_.-]+/)+[a-zA-Z0-9_.-]+\\.[a-zA-Z0-9]{1,6})\\b",
            
            // Pattern 4: Relative paths starting with ./
            "\\b(\\.{1,2}/[a-zA-Z0-9_./.-]+\\.[a-zA-Z0-9]{1,6})\\b"
        ]
        
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange),
                  match.numberOfRanges >= 2 else {
                continue
            }
            
            // Get the captured group (the actual file path)
            let captureRange = match.range(at: 1)
            guard let pathRange = Range(captureRange, in: text) else { continue }
            
            let fullPath = String(text[pathRange])
            
            // For backtick pattern (index 0), we want to use the full match range for visual consistency
            let visualRange = index == 0 ? Range(match.range(at: 0), in: text)! : pathRange
            
            // Parse line number if present
            var filePath = fullPath
            var lineNumber: Int?
            
            if let colonIndex = fullPath.lastIndex(of: ":") {
                let afterColon = String(fullPath[fullPath.index(after: colonIndex)...])
                if let lineNum = Int(afterColon) {
                    filePath = String(fullPath[..<colonIndex])
                    lineNumber = lineNum
                }
            }
            
            // Validate that this looks like a real file path
            if isValidFilePath(filePath) {
                return (.filePath(filePath, lineNumber: lineNumber), visualRange)
            }
        }
        
        return nil
    }
    
    private static func isValidFilePath(_ path: String) -> Bool {
        // Basic validation to avoid false positives
        
        // Must have a file extension
        guard let dotIndex = path.lastIndex(of: ".") else { return false }
        
        // Must not be just a number or very short
        guard path.count >= 3 else { return false }
        
        // Extract file extension
        let extensionStartIndex = path.index(after: dotIndex)
        let fileExtension = String(path[extensionStartIndex...]).lowercased()
        
        // Must have a reasonable extension length (1-10 chars)
        guard fileExtension.count >= 1 && fileExtension.count <= 10 else { return false }
        
        // Check if extension contains only alphanumeric characters
        guard fileExtension.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        
        // Common file extensions that Claude might reference
        let commonExtensions = Set([
            "js", "ts", "jsx", "tsx", "py", "swift", "java", "cpp", "c", "h", "hpp",
            "go", "rs", "rb", "php", "html", "css", "scss", "sass", "json", "xml",
            "yml", "yaml", "toml", "md", "txt", "sh", "bat", "sql", "r", "m", "mm",
            "vue", "svelte", "dart", "kt", "scala", "clj", "hs", "elm", "ex", "exs",
            "cfg", "ini", "conf", "log", "csv", "tsv", "env", "dockerfile", "lock"
        ])
        
        let pathLower = path.lowercased()
        
        // Accept if:
        // 1. Has a common extension
        // 2. Looks like a file path (contains /)
        // 3. Starts with relative path indicators
        // 4. Has any reasonable file extension (not in our list but looks valid)
        return commonExtensions.contains(fileExtension) ||
               path.contains("/") ||
               path.hasPrefix("./") ||
               path.hasPrefix("../") ||
               // Accept any file with reasonable extension if it looks like a filename
               (fileExtension.count >= 1 && fileExtension.count <= 6 &&
                path.count >= 4 &&
                !path.contains(" ") && // No spaces
                path.first?.isLetter == true) // Starts with letter
    }
    
    // MARK: - Helper Functions
    
    private static func isFirstListItem(at index: Int, in parts: [ContentPart]) -> Bool {
        guard index > 0 else { return true }
        if case .listItem = parts[index - 1] {
            return false
        }
        return true
    }
    
    private static func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        default: return .body
        }
    }
    
    static func extractPlainText(from markdown: String) -> String {
        let parts = parseMessageContent(markdown)
        return parts.compactMap { part in
            switch part {
            case .text(let string), .bold(let string), .italic(let string), .code(let string):
                return string
            case .link(let text, _):
                return text
            case .filePath(let path, let lineNumber):
                return lineNumber != nil ? "\(path):\(lineNumber!)" : path
            case .heading(_, let text), .listItem(let text):
                return text
            case .codeBlock(let code, _):
                return code
            }
        }.joined()
    }
}

// MARK: - Character Set Extension

private extension CharacterSet {
    static let leadingWhitespaces = CharacterSet(charactersIn: " \t")
}
