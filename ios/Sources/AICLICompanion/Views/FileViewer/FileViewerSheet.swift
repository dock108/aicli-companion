import SwiftUI
import Foundation

// MARK: - File Viewer Sheet

@available(iOS 17.0, macOS 14.0, *)
struct FileViewerSheet: View {
    let filePath: String
    let lineNumber: Int?
    @Environment(\.dismiss) var dismiss
    @State private var fileContentService = FileContentService.shared
    @State private var fileContent: FileContentData?
    @State private var duplicateWarning: DuplicateFileWarning?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showCopyConfirmation = false
    @State private var showDuplicateWarning = false
    @State private var jumpToLine = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(error)
                } else if let content = fileContent {
                    contentView(content)
                }
            }
            .navigationTitle(fileName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if let content = fileContent {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 16) {
                            if showCopyConfirmation {
                                Text("Copied!")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .transition(.opacity)
                            }
                            
                            Menu {
                                Button(action: {
                                    copyToClipboard(content.content)
                                }) {
                                    Label("Copy Content", systemImage: "doc.on.doc")
                                }
                                
                                Button(action: {
                                    copyToClipboard(filePath)
                                }) {
                                    Label("Copy Path", systemImage: "link")
                                }
                                
                                if lineNumber != nil {
                                    Button(action: {
                                        copyToClipboard("\(filePath):\(lineNumber!)")
                                    }) {
                                        Label("Copy Path with Line", systemImage: "number")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            print("📄 [FILE VIEWER] FileViewerSheet appeared for: \(filePath)")
            loadFileContent()
        }
        .alert("Duplicate Filenames Found", isPresented: $showDuplicateWarning) {
            Button("Ask Claude Code to Fix") {
                copyToClipboard(duplicateWarning?.suggestion ?? "")
                dismiss()
            }
            Button("View File Anyway", role: .cancel) {
                // Just dismiss the alert, keep the file viewer open
            }
        } message: {
            if let warning = duplicateWarning {
                Text(warning.message + "\n\nLocations:\n" + warning.duplicates.map { "• \($0.relativePath)" }.joined(separator: "\n"))
            }
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading \(fileName)...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Failed to Load File")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadFileContent()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func contentView(_ content: FileContentData) -> some View {
        VStack(spacing: 0) {
            // File info header
            fileInfoHeader(content)
            
            Divider()
            
            // File content with syntax highlighting
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        // Line numbers column
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(Array(contentLines.enumerated()), id: \.offset) { index, _ in
                                Text("\(index + 1)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: lineNumberWidth, alignment: .trailing)
                                    .padding(.vertical, 2)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                        .background(Color.secondary.opacity(0.05))
                        
                        // Code content column
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(contentLines.enumerated()), id: \.offset) { index, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.vertical, 2)
                                    .background(
                                        shouldHighlightLine(index + 1) ?
                                        Color.accentColor.opacity(0.2) : Color.clear
                                    )
                                    .id(index + 1)
                            }
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.bottom, 20)
                }
                .onAppear {
                    if let lineNumber = lineNumber, jumpToLine {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut) {
                                proxy.scrollTo(lineNumber, anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: jumpToLine) { _, shouldJump in
                    if shouldJump, let lineNumber = lineNumber {
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(lineNumber, anchor: .center)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            jumpToLine = false
                        }
                    }
                }
            }
        }
        .onAppear {
            if lineNumber != nil {
                jumpToLine = true
            }
        }
    }
    
    private func fileInfoHeader(_ content: FileContentData) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                    
                    Text(fileName)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    if let language = fileName.fileExtensionToLanguage() {
                        Text(language.capitalized)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                
                HStack {
                    Text("\(contentLines.count) lines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• \(ByteCountFormatter.string(fromByteCount: Int64(content.size), countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lineNumber = lineNumber {
                        Text("• Line \(lineNumber)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
            }
            
            Spacer()
            
            if lineNumber != nil {
                Button("Go to Line") {
                    jumpToLine = true
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }
    
    // MARK: - Computed Properties
    
    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }
    
    private var contentLines: [String] {
        fileContent?.content.components(separatedBy: .newlines) ?? []
    }
    
    private var lineNumberWidth: CGFloat {
        let maxDigits = String(contentLines.count).count
        return CGFloat(max(2, maxDigits)) * 8
    }
    
    private func shouldHighlightLine(_ lineNum: Int) -> Bool {
        guard let targetLine = lineNumber else { return false }
        return lineNum == targetLine
    }
    
    // MARK: - Actions
    
    private func loadFileContent() {
        print("📄 [FILE VIEWER] Starting to load content for: \(filePath)")
        isLoading = true
        error = nil
        
        Task {
            do {
                print("📄 [FILE VIEWER] Calling fetchFileContent for: \(filePath)")
                let result = try await fileContentService.fetchFileContent(path: filePath)
                await MainActor.run {
                    print("📄 [FILE VIEWER] ✅ Successfully loaded content for: \(filePath)")
                    self.fileContent = result.content
                    self.duplicateWarning = result.warning
                    self.isLoading = false
                    
                    // Show duplicate warning if present
                    if result.warning != nil {
                        self.showDuplicateWarning = true
                    }
                }
            } catch {
                await MainActor.run {
                    print("📄 [FILE VIEWER] ❌ Failed to load content for: \(filePath), error: \(error)")
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        
        withAnimation {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    FileViewerSheet(filePath: "src/example.swift", lineNumber: 42)
}
