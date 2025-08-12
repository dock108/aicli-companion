import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Preview component for attachments before sending
@available(iOS 16.0, macOS 13.0, *)
struct AttachmentPreview: View {
    let attachments: [AttachmentData]
    let onRemove: (AttachmentData) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(attachments) { attachment in
                        AttachmentThumbnail(
                            attachment: attachment,
                            onRemove: { onRemove(attachment) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Colors.bgCard(for: colorScheme).opacity(0.5))
            )
        }
    }
}

/// Individual attachment thumbnail with remove button
@available(iOS 16.0, macOS 13.0, *)
struct AttachmentThumbnail: View {
    let attachment: AttachmentData
    let onRemove: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var thumbnailImage: Image?
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Colors.bgCard(for: colorScheme))
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
                
                // Content
                if let thumbnailImage = thumbnailImage {
                    // Image thumbnail
                    thumbnailImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Document icon
                    Image(systemName: iconForAttachment(attachment))
                        .font(.system(size: 24))
                        .foregroundColor(Colors.accentPrimaryEnd)
                }
                
                // Remove button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
            }
            
            // File info
            VStack(spacing: 2) {
                Text(attachment.name)
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(attachment.formattedSize)
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
            .frame(width: 60)
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard attachment.isImage else { return }
        
        #if os(iOS)
        if let uiImage = UIImage(data: attachment.data) {
            thumbnailImage = Image(uiImage: uiImage)
        }
        #endif
    }
    
    private func iconForAttachment(_ attachment: AttachmentData) -> String {
        let name = attachment.name.lowercased()
        
        if attachment.isImage {
            return "photo"
        }
        
        if name.contains("pdf") {
            return "doc.richtext"
        }
        
        // Code file icons
        if name.hasSuffix(".swift") {
            return "swift"
        } else if name.hasSuffix(".js") || name.hasSuffix(".ts") {
            return "doc.text.below.ecg"
        } else if name.hasSuffix(".py") {
            return "terminal"
        } else if name.hasSuffix(".json") {
            return "curlybraces"
        } else if name.hasSuffix(".md") {
            return "doc.plaintext"
        } else if name.hasSuffix(".txt") {
            return "doc.text"
        } else if name.hasSuffix(".zip") {
            return "archivebox"
        }
        
        return "doc"
    }
}

// MARK: - Attachment List for Messages

/// Display attachments in a message bubble
@available(iOS 16.0, macOS 13.0, *)
struct MessageAttachmentList: View {
    let attachments: [AttachmentData]
    let onTap: ((AttachmentData) -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attachments) { attachment in
                    MessageAttachmentRow(
                        attachment: attachment,
                        onTap: onTap != nil ? { onTap!(attachment) } : nil
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Individual attachment row in message
@available(iOS 16.0, macOS 13.0, *)
struct MessageAttachmentRow: View {
    let attachment: AttachmentData
    let onTap: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    @State private var thumbnailImage: Image?
    
    var body: some View {
        Button(action: onTap ?? {}) {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let thumbnailImage = thumbnailImage {
                        thumbnailImage
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Colors.bgBase(for: colorScheme))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: iconForAttachment(attachment))
                                .font(.system(size: 16))
                                .foregroundColor(Colors.accentPrimaryEnd)
                        }
                    }
                }
                
                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text(attachment.formattedSize + " • " + attachment.mimeType)
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Spacer()
                
                // Download/View icon
                if onTap != nil {
                    Image(systemName: attachment.isImage ? "eye" : "arrow.down.circle")
                        .font(.system(size: 16))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Colors.bgBase(for: colorScheme).opacity(0.3))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(onTap == nil)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard attachment.isImage else { return }
        
        #if os(iOS)
        if let uiImage = UIImage(data: attachment.data) {
            thumbnailImage = Image(uiImage: uiImage)
        }
        #endif
    }
    
    private func iconForAttachment(_ attachment: AttachmentData) -> String {
        let name = attachment.name.lowercased()
        
        if attachment.isImage {
            return "photo"
        }
        
        if name.contains("pdf") {
            return "doc.richtext"
        }
        
        // Code file icons
        if name.hasSuffix(".swift") {
            return "swift"
        } else if name.hasSuffix(".js") || name.hasSuffix(".ts") {
            return "doc.text.below.ecg"
        } else if name.hasSuffix(".py") {
            return "terminal"
        } else if name.hasSuffix(".json") {
            return "curlybraces"
        } else if name.hasSuffix(".md") {
            return "doc.plaintext"
        } else if name.hasSuffix(".txt") {
            return "doc.text"
        } else if name.hasSuffix(".zip") {
            return "archivebox"
        }
        
        return "doc"
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Attachment Preview") {
    VStack(spacing: 20) {
        AttachmentPreview(
            attachments: [
                AttachmentData(
                    id: UUID(),
                    type: .image,
                    name: "screenshot.png",
                    data: Data(),
                    mimeType: "image/png",
                    size: 1024000
                ),
                AttachmentData(
                    id: UUID(),
                    type: .document,
                    name: "README.md",
                    data: Data(),
                    mimeType: "text/markdown",
                    size: 2048
                )
            ],
            onRemove: { _ in }
        )
        
        MessageAttachmentList(
            attachments: [
                AttachmentData(
                    id: UUID(),
                    type: .document,
                    name: "project_spec.pdf",
                    data: Data(),
                    mimeType: "application/pdf",
                    size: 5120000
                )
            ],
            onTap: { _ in }
        )
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}
