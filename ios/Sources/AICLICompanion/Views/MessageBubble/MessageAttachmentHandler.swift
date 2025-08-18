import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Message Attachment Handling

struct MessageAttachmentHandler {
    // MARK: - Attachment Extraction
    
    static func getAttachments(from message: Message) -> [AttachmentData]? {
        guard let richContent = message.richContent else { return nil }
        
        switch richContent.data {
        case .attachments(let attachmentData):
            return attachmentData.attachments.map { info in
                AttachmentData(
                    id: info.id,
                    type: attachmentTypeFromMimeType(info.mimeType),
                    name: info.name,
                    data: info.base64Data.flatMap { Data(base64Encoded: $0) } ?? Data(),
                    mimeType: info.mimeType,
                    size: info.size
                )
            }
        default:
            return nil
        }
    }
    
    // MARK: - Attachment Type Detection
    
    static func attachmentTypeFromMimeType(_ mimeType: String) -> AttachmentType {
        if mimeType.hasPrefix("image/") {
            return .image
        } else if mimeType.hasPrefix("video/") {
            return .video
        } else if mimeType.hasPrefix("audio/") {
            return .audio
        } else {
            return .document
        }
    }
    
    // MARK: - Attachment Actions
    
    static func handleAttachmentTap(_ attachment: AttachmentData) {
        switch attachment.type {
        case .image:
            showImageViewer(attachment)
        case .video, .audio:
            shareAttachment(attachment)
        case .document, .code:
            shareAttachment(attachment)
        }
    }
    
    private static func showImageViewer(_ attachment: AttachmentData) {
        // In a real implementation, this would present an image viewer
        // For now, we'll just share it
        shareAttachment(attachment)
    }
    
    private static func shareAttachment(_ attachment: AttachmentData) {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        // Create temporary file
        let tempURL = createTemporaryFile(for: attachment)
        
        let activityController = UIActivityViewController(
            activityItems: [tempURL],
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
        let tempURL = createTemporaryFile(for: attachment)
        let sharingService = NSSharingService(named: .sendViaAirDrop)
        sharingService?.perform(withItems: [tempURL])
        #endif
    }
    
    private static func createTemporaryFile(for attachment: AttachmentData) -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempURL = tempDirectory.appendingPathComponent(attachment.name)
        
        do {
            try attachment.data.write(to: tempURL)
        } catch {
            print("Failed to write temporary file: \(error)")
        }
        
        return tempURL
    }
}

// MARK: - Supporting Types
// Uses AttachmentData and AttachmentType from AttachmentPicker.swift
