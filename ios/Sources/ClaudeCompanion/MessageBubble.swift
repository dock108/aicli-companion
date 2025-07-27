import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct MessageBubble: View {
    let message: Message
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.sender == .user {
                Spacer(minLength: 40)
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
            .frame(maxWidth: 500) // Reasonable max width for readability
            
            if message.sender != .user {
                Spacer(minLength: 40)
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
}

// MARK: - Content Part Enum
private enum ContentPart {
    case text(String)
    case codeBlock(String, language: String?)
    case inlineCode(String)
}

// MARK: - Code Block View
@available(iOS 14.0, macOS 11.0, *)
struct MessageCodeBlockView: View {
    let code: String
    let language: String?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            if let lang = language {
                HStack {
                    Text(lang.uppercased())
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Colors.bgBase(for: colorScheme).opacity(0.5))
            }
            
            // Code content with syntax highlighting (simplified)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typography.font(.code))
                    .foregroundColor(Colors.accentWarning) // Terminal green
                    .padding(12)
            }
            .background(Colors.bgBase(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Colors.strokeLight, lineWidth: 1)
        )
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Message Bubbles") {
    VStack(spacing: 20) {
        MessageBubble(message: Message(
            content: "Hello, how can I help you today?",
            sender: .claude
        ))
        
        MessageBubble(message: Message(
            content: "I need help with my code",
            sender: .user
        ))
        
        MessageBubble(message: Message(
            content: "Here's a code example:\n\n```swift\nfunc greet(name: String) {\n    print(\"Hello, \\(name)!\")\n}\n```\n\nYou can also use `inline code` like this.",
            sender: .claude
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