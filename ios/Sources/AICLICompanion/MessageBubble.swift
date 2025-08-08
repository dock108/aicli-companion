import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct MessageBubble: View {
    let message: Message
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @StateObject private var clipboardManager = ClipboardManager.shared
    
    // Adaptive max width based on device
    private var maxBubbleWidth: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return horizontalSizeClass == .regular ? 700 : 500
        } else {
            return 500
        }
        #else
        return 600
        #endif
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.sender == .user {
                Spacer(minLength: horizontalSizeClass == .regular ? 60 : 40)
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                Group {
                    if message.sender == .user {
                        userBubble
                    } else {
                        aiBubble
                    }
                }
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
            }
            .frame(maxWidth: maxBubbleWidth)
            
            if message.sender != .user {
                Spacer(minLength: horizontalSizeClass == .regular ? 60 : 40)
            }
        }
    }
    
    // MARK: - User Bubble (Right-aligned pill)
    private var userBubble: some View {
        Text(message.content)
            .font(Typography.font(.body))
            .foregroundColor(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: Colors.accentPrimary(for: colorScheme),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .contextMenu {
                Button(action: {
                    clipboardManager.copyToClipboard(message.content)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                
                Button(action: {
                    shareMessage()
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
    }
    
    // MARK: - AI Bubble (Left card with terminal styling)
    private var aiBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasCodeBlock {
                // Parse and render code blocks
                renderFormattedContent()
            } else {
                // Regular text content
                Text(message.content)
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Colors.bgCard(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.strokeLight, lineWidth: 1)
                )
        )
        .contextMenu {
            Button(action: {
                clipboardManager.copyToClipboard(message.content)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            if hasCodeBlock {
                Button(action: {
                    clipboardManager.copyToClipboard(extractPlainText(from: message.content))
                }) {
                    Label("Copy as Plain Text", systemImage: "doc.plaintext")
                }
                
                Button(action: {
                    clipboardManager.copyToClipboard(message.content)
                }) {
                    Label("Copy as Markdown", systemImage: "doc.richtext")
                }
            }
            
            Button(action: {
                shareMessage()
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
    
    // MARK: - Markdown Detection
    private var hasCodeBlock: Bool {
        // Check for any markdown formatting
        return message.content.contains("```") ||
               message.content.contains("`") ||
               message.content.contains("**") ||
               message.content.contains("*") ||
               message.content.contains("#") ||
               message.content.contains("[") ||
               message.content.contains("- ") ||
               message.content.contains("* ") ||
               message.content.range(of: "^\\d+\\. ", options: .regularExpression) != nil
    }
    
    // MARK: - Formatted Content Rendering
    @ViewBuilder
    private func renderFormattedContent() -> some View {
        let parts = parseMessageContent(message.content)
        
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let text):
                    Text(text)
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    
                case .codeBlock(let code, let language):
                    MessageCodeBlockView(code: code, language: language)
                    
                case .inlineCode(let code):
                    Text(code)
                        .font(Typography.font(.code))
                        .foregroundColor(Colors.accentPrimaryEnd)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Colors.bgBase(for: colorScheme))
                        )
                        .textSelection(.enabled)
                    
                case .heading(let text, let level):
                    Text(text)
                        .font(headingFont(for: level))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, level == 1 ? 8 : 4)
                    
                case .bold(let text):
                    Text(text)
                        .font(Typography.font(.body))
                        .fontWeight(.bold)
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    
                case .italic(let text):
                    Text(text)
                        .font(Typography.font(.body))
                        .italic()
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    
                case .link(let text, let url):
                    Link(text, destination: URL(string: url)!)
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.accentPrimaryEnd)
                        .underline()
                    
                case .listItem(let text, let ordered):
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? "1." : "•")
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                            .frame(width: 20, alignment: .leading)
                        
                        Text(text)
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return Typography.font(.heading1)
        case 2: return Typography.font(.heading2)
        case 3: return Typography.font(.heading3)
        default: return Typography.font(.headline)
        }
    }
    
    // MARK: - Content Parsing
    private func parseMessageContent(_ content: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var currentText = ""
        let lines = content.components(separatedBy: "\n")
        var lineIndex = 0
        
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            
            // Check for code block
            if line.hasPrefix("```") {
                // Add any accumulated text
                if !currentText.isEmpty {
                    parts.append(contentsOf: parseInlineMarkdown(currentText))
                    currentText = ""
                }
                
                // Extract language
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                
                // Find closing ```
                var codeLines: [String] = []
                lineIndex += 1
                while lineIndex < lines.count && !lines[lineIndex].hasPrefix("```") {
                    codeLines.append(lines[lineIndex])
                    lineIndex += 1
                }
                
                let code = codeLines.joined(separator: "\n")
                parts.append(.codeBlock(code, language: language.isEmpty ? nil : language))
            }
            // Check for headings
            else if let heading = parseHeading(line) {
                if !currentText.isEmpty {
                    parts.append(contentsOf: parseInlineMarkdown(currentText))
                    currentText = ""
                }
                parts.append(heading)
            }
            // Check for list items
            else if let listItem = parseListItem(line) {
                if !currentText.isEmpty {
                    parts.append(contentsOf: parseInlineMarkdown(currentText))
                    currentText = ""
                }
                parts.append(listItem)
            } else {
                // Regular text
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
            
            lineIndex += 1
        }
        
        // Add any remaining text
        if !currentText.isEmpty {
            parts.append(contentsOf: parseInlineMarkdown(currentText))
        }
        
        return parts
    }
    
    private func parseHeading(_ line: String) -> ContentPart? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("### ") {
            return .heading(String(trimmed.dropFirst(4)), level: 3)
        } else if trimmed.hasPrefix("## ") {
            return .heading(String(trimmed.dropFirst(3)), level: 2)
        } else if trimmed.hasPrefix("# ") {
            return .heading(String(trimmed.dropFirst(2)), level: 1)
        }
        
        return nil
    }
    
    private func parseListItem(_ line: String) -> ContentPart? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Unordered list
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return .listItem(String(trimmed.dropFirst(2)), ordered: false)
        }
        
        // Ordered list (simple check for now)
        if let firstChar = trimmed.first, firstChar.isNumber, trimmed.dropFirst().hasPrefix(". ") {
            let content = trimmed.drop(while: { $0.isNumber }).dropFirst(2)
            return .listItem(String(content), ordered: true)
        }
        
        return nil
    }
    
    private func parseInlineMarkdown(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var remaining = text
        
        while !remaining.isEmpty {
            // Check for inline code
            if let range = remaining.range(of: "`([^`]+)`", options: .regularExpression) {
                let beforeCode = String(remaining[..<range.lowerBound])
                if !beforeCode.isEmpty {
                    parts.append(contentsOf: parseFormattedText(beforeCode))
                }
                
                let codeContent = String(remaining[range]).dropFirst().dropLast()
                parts.append(.inlineCode(String(codeContent)))
                
                remaining = String(remaining[range.upperBound...])
            }
            // Check for links
            else if let linkPart = parseLink(from: remaining) {
                let beforeLink = String(remaining[..<linkPart.range.lowerBound])
                if !beforeLink.isEmpty {
                    parts.append(contentsOf: parseFormattedText(beforeLink))
                }
                
                parts.append(linkPart.part)
                remaining = String(remaining[linkPart.range.upperBound...])
            } else {
                // No more special formatting found
                parts.append(contentsOf: parseFormattedText(remaining))
                break
            }
        }
        
        return parts
    }
    
    private func parseFormattedText(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var remaining = text
        
        while !remaining.isEmpty {
            // Check for bold
            if let range = remaining.range(of: "\\*\\*([^*]+)\\*\\*", options: .regularExpression) {
                let beforeBold = String(remaining[..<range.lowerBound])
                if !beforeBold.isEmpty {
                    parts.append(contentsOf: parseItalicText(beforeBold))
                }
                
                let boldContent = String(remaining[range]).dropFirst(2).dropLast(2)
                parts.append(.bold(String(boldContent)))
                
                remaining = String(remaining[range.upperBound...])
            }
            // Check for italic
            else if let range = remaining.range(of: "\\*([^*]+)\\*", options: .regularExpression) {
                let beforeItalic = String(remaining[..<range.lowerBound])
                if !beforeItalic.isEmpty {
                    parts.append(.text(beforeItalic))
                }
                
                let italicContent = String(remaining[range]).dropFirst().dropLast()
                parts.append(.italic(String(italicContent)))
                
                remaining = String(remaining[range.upperBound...])
            } else {
                // No formatting found
                parts.append(.text(remaining))
                break
            }
        }
        
        return parts
    }
    
    private func parseItalicText(_ text: String) -> [ContentPart] {
        // Check for italic that's not part of bold
        if let range = text.range(of: "\\*([^*]+)\\*", options: .regularExpression) {
            var parts: [ContentPart] = []
            
            let beforeItalic = String(text[..<range.lowerBound])
            if !beforeItalic.isEmpty {
                parts.append(.text(beforeItalic))
            }
            
            let italicContent = String(text[range]).dropFirst().dropLast()
            parts.append(.italic(String(italicContent)))
            
            let afterItalic = String(text[range.upperBound...])
            if !afterItalic.isEmpty {
                parts.append(.text(afterItalic))
            }
            
            return parts
        }
        
        return [.text(text)]
    }
    
    private func parseLink(from text: String) -> (part: ContentPart, range: Range<String.Index>)? {
        // Match [text](url) pattern
        if let match = text.range(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: .regularExpression) {
            let linkText = String(text[match])
            
            // Extract text and URL
            if let textStart = linkText.firstIndex(of: "["),
               let textEnd = linkText.firstIndex(of: "]"),
               let urlStart = linkText.firstIndex(of: "("),
               let urlEnd = linkText.lastIndex(of: ")") {
                let textStartIndex = linkText.index(after: textStart)
                let urlStartIndex = linkText.index(after: urlStart)
                
                let text = String(linkText[textStartIndex..<textEnd])
                let url = String(linkText[urlStartIndex..<urlEnd])
                
                return (.link(text: text, url: url), match)
            }
        }
        
        return nil
    }
    
    private func extractInlineCode(from line: String) -> String? {
        // Simple inline code extraction (between backticks)
        let pattern = "`([^`]+)`"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)),
           let range = Range(match.range(at: 1), in: line) {
            return String(line[range])
        }
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func shareMessage() {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [message.content],
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            // Validate window bounds to prevent NaN values
            let bounds = window.bounds
            let xPosition = bounds.width.isFinite ? bounds.midX : bounds.width / 2
            let yPosition = bounds.height.isFinite ? bounds.midY : bounds.height / 2
            popover.sourceRect = CGRect(x: xPosition, y: yPosition, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        rootViewController.present(activityVC, animated: true)
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
        #endif
    }
    
    private func extractPlainText(from markdown: String) -> String {
        var plainText = markdown
        
        // Remove code blocks
        let codeBlockPattern = "```[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern) {
            plainText = regex.stringByReplacingMatches(
                in: plainText,
                range: NSRange(location: 0, length: plainText.utf16.count),
                withTemplate: ""
            )
        }
        
        // Remove inline code
        let inlineCodePattern = "`[^`]+`"
        if let regex = try? NSRegularExpression(pattern: inlineCodePattern) {
            plainText = regex.stringByReplacingMatches(
                in: plainText,
                range: NSRange(location: 0, length: plainText.utf16.count),
                withTemplate: ""
            )
        }
        
        // Clean up extra whitespace
        plainText = plainText
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return plainText
    }
}

// MARK: - Content Part Enum
private enum ContentPart {
    case text(String)
    case codeBlock(String, language: String?)
    case inlineCode(String)
    case heading(String, level: Int)
    case bold(String)
    case italic(String)
    case link(text: String, url: String)
    case listItem(String, ordered: Bool)
}

// MARK: - Code Block View
@available(iOS 17.0, macOS 14.0, *)
struct MessageCodeBlockView: View {
    let code: String
    let language: String?
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var clipboardManager = ClipboardManager.shared
    @State private var showCopyButton = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label with copy button
            HStack {
                if let lang = language {
                    Text(lang.uppercased())
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Spacer()
                
                Button(action: {
                    clipboardManager.copyToClipboard(code)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                        Text("Copy")
                            .font(Typography.font(.caption))
                    }
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Colors.bgCard(for: colorScheme).opacity(0.8))
                    )
                }
                .opacity(showCopyButton ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Colors.bgBase(for: colorScheme).opacity(0.5))
            
            // Code content with syntax highlighting (simplified)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typography.font(.code))
                    .foregroundColor(Colors.accentWarning) // Terminal green
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Colors.bgBase(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Colors.strokeLight, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyButton = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyButton.toggle()
            }
        }
        .onAppear {
            // Always show on touch devices
            #if os(iOS)
            showCopyButton = true
            #endif
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Message Bubbles") {
    VStack(spacing: 20) {
        MessageBubble(message: Message(
            content: "Hello, how can I help you today?",
            sender: .assistant
        ))
        
        MessageBubble(message: Message(
            content: "I need help with my code",
            sender: .user
        ))
        
        MessageBubble(message: Message(
            content: "Here's a code example:\n\n```swift\nfunc greet(name: String) {\n    print(\"Hello, \\(name)!\")\n}\n```\n\nYou can also use `inline code` like this.",
            sender: .assistant
        ))
        
        MessageBubble(message: Message(
            content: "System notification",
            sender: .system
        ))
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}
