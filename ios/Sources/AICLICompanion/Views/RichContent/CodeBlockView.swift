import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Code Block View Component

@available(iOS 16.0, macOS 13.0, *)
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    if let filename = codeData.filename {
                        Text(filename)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if showCopyConfirmation {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                    
                    Button {
                        copyToClipboard(codeData.code)
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
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeData.code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showActions = hovering
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
    }
}

// MARK: - File Extension Language Mapping

extension String {
    func fileExtensionToLanguage() -> String? {
        let ext = self.lowercased()
        let mapping: [String: String] = [
            "swift": "swift",
            "js": "javascript",
            "ts": "typescript",
            "jsx": "javascript",
            "tsx": "typescript",
            "py": "python",
            "java": "java",
            "kt": "kotlin",
            "rs": "rust",
            "go": "go",
            "cpp": "cpp",
            "c": "c",
            "h": "c",
            "hpp": "cpp",
            "cs": "csharp",
            "php": "php",
            "rb": "ruby",
            "sh": "bash",
            "zsh": "bash",
            "fish": "fish",
            "ps1": "powershell",
            "sql": "sql",
            "html": "html",
            "css": "css",
            "scss": "scss",
            "sass": "sass",
            "less": "less",
            "xml": "xml",
            "json": "json",
            "yaml": "yaml",
            "yml": "yaml",
            "toml": "toml",
            "ini": "ini",
            "conf": "conf",
            "md": "markdown",
            "tex": "latex",
            "r": "r",
            "matlab": "matlab",
            "m": "matlab"
        ]
        
        if let dotIndex = self.lastIndex(of: ".") {
            let extensionWithoutDot = String(self[self.index(after: dotIndex)...])
            return mapping[extensionWithoutDot.lowercased()]
        }
        
        return mapping[ext]
    }
}