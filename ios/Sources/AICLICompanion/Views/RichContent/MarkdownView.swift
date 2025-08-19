import SwiftUI
import Foundation

// MARK: - Markdown View Component

@available(iOS 16.0, macOS 13.0, *)
struct MarkdownView: View {
    let markdownData: MarkdownData
    @State private var showActions = false
    @State private var showCopyConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header (only for full render mode)
            if markdownData.renderMode == .full {
                HStack {
                    Image(systemName: "doc.richtext")
                        .foregroundColor(.purple)
                    
                    Text("Markdown Content")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        if showCopyConfirmation {
                            Text("Copied!")
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                        
                        Button {
                            copyToClipboard(markdownData.content)
                            withAnimation {
                                showCopyConfirmation = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showCopyConfirmation = false
                                }
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .opacity(showActions ? 1 : 0)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                Divider()
                    .padding(.horizontal, 12)
            }
            
            // Content based on render mode
            Group {
                switch markdownData.renderMode {
                case .full:
                    renderedMarkdownContent
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                
                case .inline:
                    renderedMarkdownContent
                
                case .code:
                    Text(markdownData.content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .background(markdownData.renderMode == .full ? Color.clear : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: markdownData.renderMode == .full ? 10 : 0))
        .overlay(
            markdownData.renderMode == .full ?
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1) :
            nil
        )
        .onHover { hovering in
            if markdownData.renderMode == .full {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showActions = hovering
                }
            }
        }
    }
    
    private var renderedMarkdownContent: some View {
        // Simple markdown rendering - in a real app you might use a proper markdown library
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseMarkdownLines(), id: \.id) { line in
                line.view
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func parseMarkdownLines() -> [MarkdownLine] {
        let lines = markdownData.content.components(separatedBy: .newlines)
        return lines.enumerated().map { index, line in
            MarkdownLine(id: index, content: line)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Simple Markdown Line Parser

private struct MarkdownLine: Identifiable {
    let id: Int
    let content: String
    
    var view: some View {
        Group {
            if content.hasPrefix("# ") {
                Text(String(content.dropFirst(2)))
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.vertical, 4)
            } else if content.hasPrefix("## ") {
                Text(String(content.dropFirst(3)))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.vertical, 3)
            } else if content.hasPrefix("### ") {
                Text(String(content.dropFirst(4)))
                    .font(.title3)
                    .fontWeight(.medium)
                    .padding(.vertical, 2)
            } else if content.hasPrefix("- ") || content.hasPrefix("* ") {
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .fontWeight(.bold)
                    Text(String(content.dropFirst(2)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if content.hasPrefix("> ") {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 4)
                    Text(String(content.dropFirst(2)))
                        .italic()
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            } else if content.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                    .frame(height: 8)
            } else {
                Text(parseInlineMarkdown(content))
                    .textSelection(.enabled)
            }
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Bold text (**text**)
        let boldPattern = #"\*\*(.*?)\*\*"#
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = boldRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let boldText = String(text[range])
                    let content = String(boldText.dropFirst(2).dropLast(2))
                    if let attributedRange = Range(match.range, in: attributedString) {
                        attributedString.replaceSubrange(attributedRange, with: AttributedString(content))
                        if let newRange = attributedString.range(of: content) {
                            attributedString[newRange].font = .body.bold()
                        }
                    }
                }
            }
        }
        
        // Italic text (*text*)
        let italicPattern = #"\*(.*?)\*"#
        if let italicRegex = try? NSRegularExpression(pattern: italicPattern) {
            let matches = italicRegex.matches(in: String(attributedString.characters), range: NSRange(attributedString.startIndex..., in: attributedString))
            for match in matches.reversed() {
                if let range = Range(match.range, in: attributedString) {
                    let content = attributedString[range]
                    let italicContent = String(content.characters.dropFirst().dropLast())
                    attributedString.replaceSubrange(range, with: AttributedString(italicContent))
                    if let newRange = attributedString.range(of: italicContent) {
                        attributedString[newRange].font = .body.italic()
                    }
                }
            }
        }
        
        return attributedString
    }
}
