import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Attachment View Components

@available(iOS 16.0, macOS 13.0, *)
struct AttachmentView: View {
    let attachmentData: AttachmentsData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "paperclip")
                    .foregroundColor(.orange)
                
                Text("Attachments (\(attachmentData.attachments.count))")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            // Attachments list
            LazyVStack(spacing: 6) {
                ForEach(attachmentData.attachments) { attachment in
                    AttachmentItemView(attachment: attachment)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct AttachmentItemView: View {
    let attachment: AttachmentInfo
    @State private var showActions = false
    @State private var showCopyConfirmation = false
    @State private var thumbnail: Image?
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            Group {
                if let thumbnail = thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: fileIcon)
                        .font(.title2)
                        .foregroundColor(fileIconColor)
                        .frame(width: 40, height: 40)
                        .background(fileIconColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Text(attachment.mimeType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
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
                
                if attachment.base64Data != nil {
                    Button {
                        copyToClipboard()
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
                
                if attachment.url != nil {
                    Button {
                        openURL()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .opacity(showActions ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showActions = hovering
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private var fileIcon: String {
        let ext = (attachment.name as NSString).pathExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "wmv":
            return "video"
        case "mp3", "wav", "aac", "flac", "m4a":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "xls", "xlsx":
            return "tablecells"
        case "ppt", "pptx":
            return "presentation"
        case "txt", "rtf":
            return "doc.plaintext"
        case "zip", "rar", "7z", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }
    
    private var fileIconColor: Color {
        let ext = (attachment.name as NSString).pathExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic":
            return .blue
        case "mp4", "mov", "avi", "mkv", "wmv":
            return .purple
        case "mp3", "wav", "aac", "flac", "m4a":
            return .green
        case "pdf":
            return .red
        case "doc", "docx", "txt", "rtf":
            return .blue
        case "xls", "xlsx":
            return .green
        case "ppt", "pptx":
            return .orange
        case "zip", "rar", "7z", "tar", "gz":
            return .gray
        default:
            return .secondary
        }
    }
    
    private func loadThumbnail() {
        guard let thumbnailBase64 = attachment.thumbnailBase64,
              let data = Data(base64Encoded: thumbnailBase64) else { return }
        
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            thumbnail = Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            thumbnail = Image(nsImage: nsImage)
        }
        #endif
    }
    
    private func copyToClipboard() {
        guard let base64Data = attachment.base64Data,
              let data = Data(base64Encoded: base64Data) else { return }
        
        #if os(iOS)
        if attachment.mimeType.hasPrefix("image/") {
            if let image = UIImage(data: data) {
                UIPasteboard.general.image = image
            }
        } else {
            UIPasteboard.general.setData(data, forPasteboardType: attachment.mimeType)
        }
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if attachment.mimeType.hasPrefix("image/") {
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        } else {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(attachment.mimeType))
        }
        #endif
    }
    
    private func openURL() {
        guard let urlString = attachment.url,
              let url = URL(string: urlString) else { return }
        
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
