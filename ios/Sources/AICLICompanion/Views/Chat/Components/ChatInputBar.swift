import SwiftUI

// MARK: - Constants
private let attachmentFileSizeLimit = 10 * 1024 * 1024 // 10MB in bytes

@available(iOS 16.0, macOS 13.0, *)
struct ChatInputBar: View {
    @Binding var messageText: String
    let isLoading: Bool
    let isIPad: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let colorScheme: ColorScheme
    let onSendMessage: ([AttachmentData]) -> Void
    
    // FEATURE: Simple send blocking logic
    let isSendBlocked: Bool
    
    // Processing state for showing stop button
    let isProcessing: Bool
    let onStopProcessing: (() -> Void)?
    
    @EnvironmentObject private var settings: SettingsManager
    @FocusState private var isInputFocused: Bool
    @State private var attachments: [AttachmentData] = []
    @State private var showingAttachmentPicker = false
    
    private var hasContent: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview (only show if feature is enabled and there are attachments)
            if settings.enableAttachments {
                AttachmentPreview(
                    attachments: attachments,
                    onRemove: removeAttachment
                )
                .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 20 : 16)
                .padding(.top, attachments.isEmpty ? 0 : 8)
                
                if !attachments.isEmpty {
                    Divider()
                        .background(Colors.strokeLight)
                }
            }
            
            Divider()
                .background(Colors.strokeLight)
            
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 12) {
                    // Attachment button (only show if feature flag is enabled)
                    if settings.enableAttachments {
                        Button(action: {
                            showingAttachmentPicker = true
                        }) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 28))
                                .foregroundColor(Colors.textSecondary(for: colorScheme))
                        }
                        // Allow attachments even while loading
                        .disabled(false)
                    }
                    
                    // Text input container
                    VStack(spacing: 0) {
                        TextField("Type a message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.textPrimary(for: colorScheme))
                            .accentColor(Colors.accentPrimaryStart)
                            .lineLimit(1...6)
                            .focused($isInputFocused)
                            .onSubmit {
                                if hasContent && !isSendBlocked {
                                    sendMessage()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Colors.bgCard(for: colorScheme))
                                    .strokeBorder(Colors.strokeLight, lineWidth: 1)
                            )
                            .onTapGesture {
                                isInputFocused = true
                            }
                    }
                    
                    // Send or Stop button
                    Group {
                        if isProcessing {
                            // Stop button when processing
                            Button(action: {
                                onStopProcessing?()
                            }) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.red, Color.red.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            // Send button when not processing
                            Button(action: sendMessage) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: (hasContent && !isSendBlocked)
                                                ? Colors.accentPrimary(for: colorScheme)
                                                : [Colors.textSecondary(for: colorScheme)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            // FEATURE: Simple send blocking - disable when blocked or no content
                            .disabled(!hasContent || isSendBlocked)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    // Animate the button transitions
                    .animation(.easeInOut(duration: 0.2), value: hasContent)
                    .animation(.easeInOut(duration: 0.2), value: isSendBlocked)
                    .animation(.easeInOut(duration: 0.2), value: isProcessing)
                }
            }
            .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 20 : 16)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showingAttachmentPicker) {
            if settings.enableAttachments {
                AttachmentPicker(
                    isPresented: $showingAttachmentPicker,
                    onAttachmentSelected: addAttachment
                )
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden) // We have our own drag indicator
                #endif
            }
        }
        .onChange(of: settings.enableAttachments) { enabled in
            // Clear attachments if feature is disabled
            if !enabled {
                attachments.removeAll()
            }
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        // Pass attachments to parent view
        onSendMessage(attachments)
        
        // Clear attachments after sending
        attachments.removeAll()
    }
    
    private func addAttachment(_ attachment: AttachmentData) {
        // Limit to 5 attachments
        guard attachments.count < 5 else { return }
        
        // Check file size (limit to 10MB per file)
        guard attachment.size <= attachmentFileSizeLimit else {
            // TODO: Show error alert
            print("❌ File too large: \(attachment.formattedSize)")
            return
        }
        
        attachments.append(attachment)
    }
    
    private func removeAttachment(_ attachment: AttachmentData) {
        attachments.removeAll { $0.id == attachment.id }
    }
}
