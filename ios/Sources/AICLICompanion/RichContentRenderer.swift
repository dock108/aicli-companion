import SwiftUI
import Foundation

// MARK: - Main Rich Content View
// Uses composition pattern with specialized view components

@available(iOS 16.0, macOS 13.0, *)
struct RichContentView: View {
    let content: RichContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch content.data {
            case .codeBlock(let codeData):
                CodeBlockView(codeData: codeData)
            case .fileContent(let fileData):
                FileContentView(fileData: fileData, isExpanded: $isExpanded)
            case .commandOutput(let commandData):
                CommandOutputView(commandData: commandData, isExpanded: $isExpanded)
            case .toolResult(let toolData):
                ToolResultView(toolData: toolData, isExpanded: $isExpanded)
            case .markdown(let markdownData):
                MarkdownView(markdownData: markdownData)
            case .attachments(let attachmentData):
                AttachmentView(attachmentData: attachmentData)
            }
        }
    }
}