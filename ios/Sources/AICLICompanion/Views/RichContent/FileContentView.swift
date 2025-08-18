import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - File Content View Component

@available(iOS 16.0, macOS 13.0, *)
struct FileContentView: View {
    let fileData: FileContentData
    @Binding var isExpanded: Bool
    @State private var showActions = false
    @State private var showCopyConfirmation = false
    
    private let previewLines = 10
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileData.filename)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    HStack {
                        if let language = fileData.filename.fileExtensionToLanguage() {
                            Text(language.capitalized)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        Text("\(fileData.content.components(separatedBy: .newlines).count) lines")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• \(ByteCountFormatter.string(fromByteCount: Int64(fileData.size), countStyle: .file))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 8) {
                    if showCopyConfirmation {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                    
                    Button {
                        copyToClipboard(fileData.content)
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
                    
                    if needsExpandToggle {
                        Button {
                            withAnimation(.easeInOut) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if needsExpandToggle && !isExpanded {
                HStack {
                    Spacer()
                    Button("Show More") {
                        withAnimation(.easeInOut) {
                            isExpanded = true
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showActions = hovering
            }
        }
    }
    
    private var displayContent: String {
        if needsExpandToggle && !isExpanded {
            let lines = fileData.content.components(separatedBy: .newlines)
            if lines.count > previewLines {
                return lines.prefix(previewLines).joined(separator: "\n")
            }
        }
        return fileData.content
    }
    
    private var needsExpandToggle: Bool {
        let lineCount = fileData.content.components(separatedBy: .newlines).count
        return lineCount > previewLines
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