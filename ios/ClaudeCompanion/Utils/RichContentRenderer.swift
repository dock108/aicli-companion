import SwiftUI
import Foundation

// MARK: - Rich Content Rendering

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
            }
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let codeData: CodeBlockData
    @State private var showActions = false
    @State private var showCopyConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with language and filename
            if let language = codeData.language ?? codeData.filename?.fileExtensionToLanguage() {
                HStack {
                    Text(language.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    if let filename = codeData.filename {
                        Text(filename)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Interactive buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            UIPasteboard.general.string = codeData.code
                            showCopyConfirmation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopyConfirmation = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                                if showCopyConfirmation {
                                    Text("Copied")
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(showCopyConfirmation ? .green : .secondary)
                        }
                        
                        Menu {
                            Button("Share Code") {
                                shareCode()
                            }
                            
                            if let filename = codeData.filename {
                                Button("Save to Files") {
                                    saveToFiles(filename: filename)
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .opacity(showActions ? 1 : 0.3)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeData.code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            showActions.toggle()
        }
        .onLongPressGesture {
            UIPasteboard.general.string = codeData.code
            showCopyConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopyConfirmation = false
            }
        }
        .onAppear {
            showActions = true // Always show on mobile
        }
    }
    
    private func shareCode() {
        let activityController = UIActivityViewController(
            activityItems: [codeData.code],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
    
    private func saveToFiles(filename: String) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        
        do {
            try codeData.code.write(to: tempURL, atomically: true, encoding: .utf8)
            
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL])
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(documentPicker, animated: true)
            }
        } catch {
            print("Failed to save file: \(error)")
        }
    }
}

// MARK: - File Content View

struct FileContentView: View {
    let fileData: FileContentData
    @Binding var isExpanded: Bool
    @State private var showActions = false
    private let maxCollapsedLines = 20
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileData.filename)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(fileData.filePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(fileData.lineCount) lines")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Quick actions
                HStack(spacing: 8) {
                    Button(action: {
                        UIPasteboard.general.string = fileData.content
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Menu {
                        Button("Share File") {
                            shareFile()
                        }
                        Button("Save to Files") {
                            saveFileToFiles()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(showActions ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            if isExpanded || fileData.lineCount <= maxCollapsedLines {
                // Full content
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(fileData.content.components(separatedBy: .newlines).enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 30, alignment: .trailing)
                                
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(maxHeight: isExpanded ? .infinity : 300)
            } else {
                // Collapsed preview
                let previewLines = fileData.content.components(separatedBy: .newlines).prefix(5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 30, alignment: .trailing)
                            
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    }
                    
                    Text("... \(fileData.lineCount - 5) more lines")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color.blue.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
        .onAppear {
            showActions = true
        }
    }
    
    private func shareFile() {
        let activityController = UIActivityViewController(
            activityItems: [fileData.content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
    
    private func saveFileToFiles() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileData.filename)
        
        do {
            try fileData.content.write(to: tempURL, atomically: true, encoding: .utf8)
            
            let documentPicker = UIDocumentPickerViewController(forExporting: [tempURL])
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(documentPicker, animated: true)
            }
        } catch {
            print("Failed to save file: \(error)")
        }
    }
}

// MARK: - Command Output View

struct CommandOutputView: View {
    let commandData: CommandOutputData
    @Binding var isExpanded: Bool
    @State private var showActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(commandData.command)
                        .font(.caption)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                    
                    if let workingDir = commandData.workingDirectory {
                        Text(workingDir)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let exitCode = commandData.exitCode {
                    Text("Exit: \(exitCode)")
                        .font(.caption2)
                        .foregroundColor(exitCode == 0 ? .green : .red)
                }
                
                // Quick actions
                HStack(spacing: 8) {
                    Button(action: {
                        UIPasteboard.general.string = commandData.output
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Menu {
                        Button("Share Output") {
                            shareCommandOutput()
                        }
                        Button("Copy Command") {
                            UIPasteboard.general.string = commandData.command
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(showActions ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Output content
            if isExpanded || commandData.output.count < 500 {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(commandData.output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: isExpanded ? .infinity : 200)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(commandData.output.prefix(300)) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                    
                    Text("Output truncated. Tap to expand.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color.green.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
        .onAppear {
            showActions = true
        }
    }
    
    private func shareCommandOutput() {
        let content = "Command: \(commandData.command)\n\nOutput:\n\(commandData.output)"
        let activityController = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
}

// MARK: - Tool Result View

struct ToolResultView: View {
    let toolData: ToolResultData
    @Binding var isExpanded: Bool
    @State private var showActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: toolData.success ? "checkmark.circle" : "xmark.circle")
                    .foregroundColor(toolData.success ? .green : .red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(toolData.toolName)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if let error = toolData.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                if let duration = toolData.duration {
                    Text("\(Int(duration * 1000))ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Quick actions
                HStack(spacing: 8) {
                    Button(action: {
                        UIPasteboard.general.string = toolData.output
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Menu {
                        Button("Share Result") {
                            shareToolResult()
                        }
                        if toolData.success {
                            Button("Use Output") {
                                // TODO: Context menu for using tool output
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(showActions ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Output content
            if isExpanded || toolData.output.count < 300 {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(toolData.output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: isExpanded ? .infinity : 150)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(toolData.output.prefix(200)) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                    
                    Text("Output truncated. Tap to expand.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color.orange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
        .onAppear {
            showActions = true
        }
    }
    
    private func shareToolResult() {
        let content = "Tool: \(toolData.toolName)\nStatus: \(toolData.success ? "Success" : "Failed")\n\nOutput:\n\(toolData.output)"
        let activityController = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
}

// MARK: - Markdown View

struct MarkdownView: View {
    let markdownData: MarkdownData
    @State private var showActions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with actions
            HStack {
                Text("Markdown")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: {
                        UIPasteboard.general.string = markdownData.markdown
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Menu {
                        Button("Share Markdown") {
                            shareMarkdown()
                        }
                        Button("Copy as Text") {
                            UIPasteboard.general.string = markdownData.markdown
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(showActions ? 1 : 0.3)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // Simple markdown rendering for now
            // TODO: Integrate proper markdown rendering library
            Text(markdownData.markdown)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            showActions = true
        }
    }
    
    private func shareMarkdown() {
        let activityController = UIActivityViewController(
            activityItems: [markdownData.markdown],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
}

// MARK: - Utility Extensions

extension String {
    func fileExtensionToLanguage() -> String? {
        let ext = (self as NSString).pathExtension.lowercased()
        
        switch ext {
        case "swift": return "Swift"
        case "js", "jsx": return "JavaScript"
        case "ts", "tsx": return "TypeScript"
        case "py": return "Python"
        case "java": return "Java"
        case "kt": return "Kotlin"
        case "go": return "Go"
        case "rs": return "Rust"
        case "c": return "C"
        case "cpp", "cc", "cxx": return "C++"
        case "h", "hpp": return "Header"
        case "css": return "CSS"
        case "html": return "HTML"
        case "xml": return "XML"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        case "md": return "Markdown"
        case "sh": return "Shell"
        case "sql": return "SQL"
        case "php": return "PHP"
        case "rb": return "Ruby"
        default: return nil
        }
    }
}