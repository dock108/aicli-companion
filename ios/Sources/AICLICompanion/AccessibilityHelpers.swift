import SwiftUI

// MARK: - Accessibility Identifiers

struct AccessibilityIdentifiers {
    // MARK: - Chat View
    static let chatView = "chat_view"
    static let messageInput = "message_input_field"
    static let sendButton = "send_message_button"
    static let fileBrowserButton = "file_browser_button"
    static let messagesScrollView = "messages_scroll_view"

    // MARK: - Message Bubbles
    static let messageBubble = "message_bubble"
    static let userMessage = "user_message"
    static let assistantMessage = "assistant_message"
    static let systemMessage = "system_message"
    static let toolMessage = "tool_message"

    // MARK: - Navigation
    static let conversationHistoryButton = "conversation_history_button"
    static let settingsButton = "settings_button"
    static let workflowButton = "workflow_button"
    static let fileBrowserSheet = "file_browser_sheet"

    // MARK: - Workflow
    static let workflowSuggestion = "workflow_suggestion"
    static let gitStatusCard = "git_status_card"
    static let buildSystemCard = "build_system_card"
    static let testResultsCard = "test_results_card"

    // MARK: - File Management
    static let fileRow = "file_row"
    static let directoryRow = "directory_row"
    static let fileSearchField = "file_search_field"
    static let recentFilesBar = "recent_files_bar"

    // MARK: - Conversation Management
    static let conversationRow = "conversation_row"
    static let favoriteButton = "favorite_conversation_button"
    static let archiveButton = "archive_conversation_button"
    static let exportButton = "export_conversation_button"
    static let deleteButton = "delete_conversation_button"

    // MARK: - Export
    static let exportFormatButton = "export_format_button"
    static let bulkExportSheet = "bulk_export_sheet"
    static let exportShareButton = "export_share_button"
}

// MARK: - Accessibility Labels

struct AccessibilityLabels {
    // MARK: - Actions
    static let sendMessage = "Send message to Claude"
    static let openFileBrowser = "Open file browser"
    static let openConversationHistory = "Open conversation history"
    static let openSettings = "Open settings"
    static let openWorkflow = "Open development workflow"

    // MARK: - Messages
    static func messageFrom(_ sender: String, at time: String) -> String {
        "Message from \(sender) at \(time)"
    }

    static func toolResult(_ toolName: String, success: Bool) -> String {
        "Tool \(toolName) \(success ? "completed successfully" : "failed")"
    }

    // MARK: - File Management
    static func fileItem(_ name: String, type: String, size: String?) -> String {
        var label = "\(type): \(name)"
        if let size = size {
            label += ", size: \(size)"
        }
        return label
    }

    static func directoryItem(_ name: String, itemCount: Int) -> String {
        "Directory: \(name), contains \(itemCount) items"
    }

    // MARK: - Workflow
    static func workflowSuggestion(_ title: String, priority: String) -> String {
        "\(priority) priority workflow suggestion: \(title)"
    }

    static func gitStatus(_ branch: String, changes: Int) -> String {
        "Git repository on branch \(branch) with \(changes) changes"
    }

    static func buildResult(_ success: Bool, duration: String) -> String {
        "Build \(success ? "successful" : "failed"), duration: \(duration)"
    }

    // MARK: - Conversation Management
    static func conversationItem(_ title: String, messageCount: Int, lastUpdated: String) -> String {
        "Conversation: \(title), \(messageCount) messages, last updated \(lastUpdated)"
    }

    static func conversationAction(_ action: String, title: String) -> String {
        "\(action) conversation: \(title)"
    }
}

// MARK: - Accessibility Hints

struct AccessibilityHints {
    // MARK: - Navigation
    static let sendMessage = "Double tap to send your message to Claude"
    static let openFileBrowser = "Double tap to browse and select files from your project"
    static let openWorkflow = "Double tap to view development workflow suggestions and actions"

    // MARK: - Messages
    static let messageOptions = "Long press for message options like copy and share"
    static let toolMessage = "Contains tool execution results and output"

    // MARK: - File Management
    static let selectFile = "Double tap to select this file for Claude analysis"
    static let navigateDirectory = "Double tap to open this directory"
    static let fileActions = "Long press for file actions like watch and analyze"

    // MARK: - Workflow
    static let executeWorkflowAction = "Double tap to execute this workflow command"
    static let viewWorkflowDetails = "Double tap to view detailed workflow information"

    // MARK: - Conversation Management
    static let selectConversation = "Double tap to open this conversation"
    static let conversationActions = "Long press for conversation actions like favorite, archive, and export"
    static let bulkSelect = "In selection mode, double tap to toggle selection"
}

// MARK: - Accessibility View Modifiers

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct AccessibleMessage: ViewModifier {
    let sender: String
    let content: String
    let timestamp: Date
    let hasRichContent: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AccessibilityLabels.messageFrom(sender, at: DateFormatter.timeOnly.string(from: timestamp)))
            .accessibilityValue(self.content)
            .accessibilityHint(hasRichContent ? AccessibilityHints.toolMessage : AccessibilityHints.messageOptions)
            .accessibilityIdentifier(AccessibilityIdentifiers.messageBubble)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct AccessibleButton: ViewModifier {
    let label: String
    let hint: String
    let identifier: String

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(.isButton)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct AccessibleFileItem: ViewModifier {
    let file: FileItem

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AccessibilityLabels.fileItem(
                file.name,
                type: file.type.rawValue,
                size: file.size != nil ? ByteCountFormatter.string(fromByteCount: file.size!, countStyle: .file) : nil
            ))
            .accessibilityHint(file.type == .directory ? AccessibilityHints.navigateDirectory : AccessibilityHints.selectFile)
            .accessibilityIdentifier(file.type == .directory ? AccessibilityIdentifiers.directoryRow : AccessibilityIdentifiers.fileRow)
            .accessibilityAddTraits(file.type == .directory ? .isButton : .isButton)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct AccessibleConversation: ViewModifier {
    let conversation: Conversation
    let isSelectMode: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AccessibilityLabels.conversationItem(
                conversation.title,
                messageCount: conversation.messages.count,
                lastUpdated: conversation.updatedAt.formatted(.relative(presentation: .named))
            ))
            .accessibilityHint(isSelectMode ? AccessibilityHints.bulkSelect : AccessibilityHints.selectConversation)
            .accessibilityIdentifier(AccessibilityIdentifiers.conversationRow)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - View Extensions

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
extension View {
    func accessibleMessage(sender: String, content: String, timestamp: Date, hasRichContent: Bool = false) -> some View {
        self.modifier(AccessibleMessage(sender: sender, content: content, timestamp: timestamp, hasRichContent: hasRichContent))
    }

    func accessibleButton(label: String, hint: String, identifier: String) -> some View {
        self.modifier(AccessibleButton(label: label, hint: hint, identifier: identifier))
    }

    func accessibleFileItem(_ file: FileItem) -> some View {
        self.modifier(AccessibleFileItem(file: file))
    }

    func accessibleConversation(_ conversation: Conversation, isSelectMode: Bool = false) -> some View {
        self.modifier(AccessibleConversation(conversation: conversation, isSelectMode: isSelectMode))
    }
}

// MARK: - Voice Over Helpers

struct VoiceOverHelpers {
    static func announceMessageReceived() {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(notification: .announcement, argument: "New message received from Claude")
        }
        #endif
    }

    static func announceToolStarted(_ toolName: String) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIAccessibility.post(notification: .announcement, argument: "Starting tool: \(toolName)")
        }
        #endif
    }

    static func announceToolCompleted(_ toolName: String, success: Bool) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let status = success ? "completed successfully" : "failed"
            UIAccessibility.post(notification: .announcement, argument: "Tool \(toolName) \(status)")
        }
        #endif
    }

    static func announceConversationSwitched(_ title: String) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIAccessibility.post(notification: .announcement, argument: "Switched to conversation: \(title)")
        }
        #endif
    }

    static func announceWorkingDirectoryChanged(_ directory: String) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let shortPath = (directory as NSString).lastPathComponent
            UIAccessibility.post(notification: .announcement, argument: "Working directory changed to \(shortPath)")
        }
        #endif
    }

    static func announceExportCompleted(_ format: String, conversationCount: Int) {
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let message = conversationCount == 1 ?
                "Conversation exported as \(format)" :
                "\(conversationCount) conversations exported as \(format)"
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        #endif
    }
}

// MARK: - Dynamic Type Support

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
extension Font {
    static func scaledSystem(_ style: Font.TextStyle, design: Font.Design = .default) -> Font {
        return .system(style, design: design)
    }

    static func scaledCustom(_ name: String, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        return .custom(name, size: size, relativeTo: style)
    }
}

// MARK: - Reduced Motion Support

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ReducedMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation
    let fallback: Animation?

    init(animation: Animation, fallback: Animation? = nil) {
        self.animation = animation
        self.fallback = fallback
    }

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? fallback : animation, value: UUID())
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
extension View {
    func respectReducedMotion(animation: Animation, fallback: Animation? = nil) -> some View {
        self.modifier(ReducedMotionModifier(animation: animation, fallback: fallback))
    }
}
