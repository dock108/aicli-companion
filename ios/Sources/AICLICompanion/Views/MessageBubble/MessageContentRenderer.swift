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
        VStack(alignment: .leading, spacing: 8) {
            // Message content
            VStack(alignment: .leading, spacing: 0) {
                // Render formatted content
                // Trim trailing whitespace/newlines before parsing
                let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(MarkdownParser.parseMarkdown(trimmedContent))
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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
                shareMessage(message)
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private static func shareMessage(_ message: Message) {
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