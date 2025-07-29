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
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .padding(.horizontal, 4)
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
    
    // MARK: - Code Block Detection
    private var hasCodeBlock: Bool {
        message.content.contains("```") || message.content.contains("`")
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
                }
            }
        }
    }
    
    // MARK: - Content Parsing
    private func parseMessageContent(_ content: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        var currentText = ""
        let lines = content.components(separatedBy: "\n")
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            // Check for code block
            if line.hasPrefix("```") {
                // Add any accumulated text
                if !currentText.isEmpty {
                    parts.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                
                // Extract language
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                
                // Find closing ```
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                
                let code = codeLines.joined(separator: "\n")
                parts.append(.codeBlock(code, language: language.isEmpty ? nil : language))
            } else if let inlineCode = extractInlineCode(from: line) {
                // Handle inline code
                if !currentText.isEmpty {
                    parts.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                parts.append(.inlineCode(inlineCode))
            } else {
                // Regular text
                currentText += (currentText.isEmpty ? "" : "\n") + line
            }
            
            i += 1
        }
        
        // Add any remaining text
        if !currentText.isEmpty {
            parts.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        
        return parts
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
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
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