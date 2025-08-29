import SwiftUI
import Foundation

// MARK: - Message Content Rendering Components

@available(iOS 17.0, macOS 14.0, *)
struct MessageContentRenderer {
    // MARK: - User Bubble Rendering
    
    static func userBubble(for message: Message, colorScheme: ColorScheme, clipboardManager: ClipboardManager) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Attachments (if any)
            if let attachments = MessageAttachmentHandler.getAttachments(from: message) {
                MessageAttachmentList(
                    attachments: attachments,
                    onTap: { attachment in
                        MessageAttachmentHandler.handleAttachmentTap(attachment)
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            
            // Message text (if any)
            let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                Text(trimmedContent)
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
            }
        }
        .contextMenu {
            Button(action: {
                clipboardManager.copyToClipboard(message.content)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                shareMessage(message)
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
    
    // MARK: - AI Bubble Rendering
    
    static func aiBubble(for message: Message, colorScheme: ColorScheme, clipboardManager: ClipboardManager) -> some View {
        AIBubbleContent(message: message, colorScheme: colorScheme, clipboardManager: clipboardManager)
    }
}

// MARK: - AI Bubble Content Component

@available(iOS 17.0, macOS 14.0, *)
private struct AIBubbleContent: View {
    let message: Message
    let colorScheme: ColorScheme
    let clipboardManager: ClipboardManager
    
    @State private var selectedFilePath: String?
    @State private var selectedLineNumber: Int?
    @State private var showFileViewer = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Message content
            VStack(alignment: .leading, spacing: 0) {
                // Render formatted content with file path click handling
                let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let parsedContent = MarkdownParser.parseMarkdown(trimmedContent)
                
                Text(parsedContent)
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        // Check if this is a file path URL with our custom scheme
                        if url.scheme == "aicli-file" {
                            // Extract the path from the URL host and path components
                            // The URL format is aicli-file://path/to/file
                            let fullPath = url.absoluteString
                                .replacingOccurrences(of: "aicli-file://", with: "")
                                .components(separatedBy: "#")[0] // Remove fragment if present
                            
                            print("📄 [FILE LINK] File path tapped: \(fullPath)")
                            
                            // Extract line number if present
                            var lineNumber: Int?
                            if let fragment = url.fragment, let line = Int(fragment) {
                                lineNumber = line
                            }
                            
                            // Resolve and open the file
                            let resolvedPath = resolveFilePath(fullPath)
                            print("📄 [FILE LINK] Resolved path: \(resolvedPath)")
                            
                            selectedFilePath = resolvedPath
                            selectedLineNumber = lineNumber
                            showFileViewer = true
                            
                            return .handled
                        }
                        return .systemAction(url)
                    })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Colors.bgCard(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
            )
            
            // Attachments (if any)
            if let attachments = MessageAttachmentHandler.getAttachments(from: message) {
                MessageAttachmentList(
                    attachments: attachments,
                    onTap: { attachment in
                        MessageAttachmentHandler.handleAttachmentTap(attachment)
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        .contextMenu {
            Button(action: {
                clipboardManager.copyToClipboard(message.content)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                clipboardManager.copyToClipboard(MarkdownParser.extractPlainText(from: message.content))
            }) {
                Label("Copy Plain Text", systemImage: "doc.plaintext")
            }
            
            Button(action: {
                MessageContentRenderer.shareMessage(message)
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .sheet(isPresented: $showFileViewer) {
            if let filePath = selectedFilePath {
                FileViewerSheet(filePath: filePath, lineNumber: selectedLineNumber)
                    .onAppear {
                        print("📄 [SHEET] Presenting FileViewerSheet for: \(filePath)")
                    }
            } else {
                Text("No file selected")
                    .onAppear {
                        print("📄 [SHEET] ❌ No file path set for sheet presentation")
                    }
            }
        }
        .onChange(of: showFileViewer) { _, newValue in
            print("📄 [SHEET STATE] showFileViewer changed to: \(newValue)")
        }
    }
    
    // MARK: - Path Resolution Helper
    
    private func resolveFilePath(_ filePath: String) -> String {
        // If it's already an absolute path, return as-is
        if filePath.hasPrefix("/") {
            return filePath
        }
        
        // Try to get the current project path
        guard let projectStateManager = try? DependencyContainer.shared.projectStateManager,
              let currentProject = projectStateManager.currentProject else {
            // Fallback: return the original path and let server handle it
            return filePath
        }
        
        let projectPath = currentProject.path
        
        // If the file path contains directory separators, try it as a relative path first
        if filePath.contains("/") {
            let resolvedPath = (projectPath as NSString).appendingPathComponent(filePath)
            return resolvedPath
        }
        
        // For just filenames, we'll pass the filename and let the server search for it
        // The server is better positioned to do efficient file system searches
        // But we'll provide the project path as working directory context
        return filePath
    }
}


// MARK: - Helper Functions Extension

@available(iOS 17.0, macOS 14.0, *)
extension MessageContentRenderer {
    static func shareMessage(_ message: Message) {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        let activityController = UIActivityViewController(
            activityItems: [message.content],
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                      y: rootViewController.view.bounds.midY,
                                      width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        rootViewController.present(activityController, animated: true)
        
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
        #endif
    }
}

// MessageAttachmentList is imported from AttachmentPreview.swift

// MARK: - Typography Support
// Uses Typography from DesignSystem/Typography.swift
// Uses Colors from DesignSystem/Colors.swift
// Uses ClipboardManager from ClipboardManager.swift
