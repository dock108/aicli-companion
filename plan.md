# iOS App Enhancement Plan

## Overview
This document tracks the ongoing enhancements to the Claude Companion iOS app. Each section includes current status, implementation details, and remaining tasks.

## Enhancement Status Tracker

### 1. Settings View Overhaul ✅ COMPLETED
**Goal**: Transform the basic disconnect-only settings into a comprehensive configuration center

#### Current Issues
- [x] Identified: Settings only shows "Disconnect" with no feedback
- [x] Identified: Limited configuration options  
- [x] Identified: Not consistent between iPhone/iPad

#### Implementation Tasks
- [x] Redesign SettingsView.swift with multiple sections
- [x] Add Connection Management section
  - [x] Show real-time connection status
  - [x] Display server details (address, port, auth status)
  - [x] Implement disconnect with confirmation dialog
  - [x] Add reconnect button
- [x] Add Auto-Response Mode section
  - [x] Toggle switch for enabling/disabling
  - [x] Default prompt template editor
  - [x] Max iterations slider (1-20)
  - [x] Stop phrases text field (comma-separated)
  - [x] Test mode with dry run
- [x] Ensure iPad/iPhone responsive layout
- [x] Add loading states and success confirmations
- [x] Implement settings persistence

#### ✅ **COMPLETED DELIVERABLES**
- **Enhanced SettingsView.swift**: Complete redesign with iPad/iPhone responsive layouts
- **Extended SettingsManager.swift**: Added all missing properties and methods
- **Auto-Response Integration**: Full AutoResponseManager integration
- **Connection Management**: Live status indicators, reconnect/disconnect with feedback
- **Multi-section Design**: Connection, Auto Mode, Appearance, Behavior, Notifications, Privacy, Advanced, About

---

### 2. Markdown Rendering Fix ⏳ Not Started
**Goal**: Full markdown support in chat and push notifications

#### Current Issues
- [x] Identified: Partial markdown support in MessageBubble.swift
- [x] Identified: No markdown in push notifications
- [x] Identified: Inconsistent rendering for complex markdown

#### Implementation Tasks
- [ ] Enhance MessageBubble.swift parser
  - [ ] Add table support
  - [ ] Add blockquote support
  - [ ] Add horizontal rule support
  - [ ] Fix nested formatting (bold within italic)
  - [ ] Add more language syntax highlighting
- [ ] Create NotificationMarkdownRenderer
  - [ ] Convert markdown to rich notification format
  - [ ] Fallback to plain text with formatting hints
  - [ ] Test with various markdown samples
- [ ] Add markdown preview in composer
- [ ] Unit tests for markdown parser

---

### 3. Claude Thinking Indicator ⏳ Not Started
**Goal**: Show Claude's thinking process in real-time

#### Current Issues
- [x] Identified: No visibility into Claude's processing
- [x] Identified: Can't see token count or elapsed time
- [x] Identified: No way to interrupt

#### Implementation Tasks
- [ ] Create ThinkingIndicator.swift component
  - [ ] Animated "Creating..." text
  - [ ] Elapsed time counter
  - [ ] Token count display
  - [ ] ESC/Cancel button
- [ ] Integrate with WebSocket for status updates
- [ ] Add to ChatLoadingView
- [ ] Handle interruption logic
- [ ] Test with long-running operations

---

### 4. Scroll Position Fixes ✅ COMPLETED
**Goal**: Reliable scroll behavior and position persistence

#### Current Issues
- [x] Identified: Reopening goes to random position
- [x] Identified: Scroll freezing/glitching
- [x] Identified: Not scrolling to bottom for new messages

#### Implementation Tasks
- [x] Fix ChatMessageList.swift scroll logic
  - [x] Persist last read message ID
  - [x] Implement proper scroll-to position on load
  - [x] Fix scroll physics and animations
- [x] Add scroll-to-bottom FAB
  - [x] Show when user scrolls up
  - [x] Hide when at bottom
  - [x] Smooth animation
- [x] Debounce rapid scroll events
- [x] Test on various devices and iOS versions

#### ✅ **COMPLETED DELIVERABLES**
- **Enhanced ChatMessageList.swift**: Complete scroll position management with persistence
- **ScrollToBottomButton.swift**: Floating action button with unread message count
- **Scroll Position Persistence**: Saves and restores last read message position
- **Debounced Scroll Events**: Prevents performance issues with rapid scrolling
- **Smart Auto-Scroll**: Only scrolls for user messages or when user is near bottom
- **Unread Message Tracking**: Badge shows count of missed assistant messages

---

### 5. Auto-Response Mode ("Jesus Take the Wheel") ✅ COMPLETED
**Goal**: Automated continuation of conversations

#### Current Issues
- [x] Identified: Need for hands-free operation
- [x] Identified: Manual intervention for each Claude question
- [x] Identified: No way to batch operations

#### Implementation Tasks
- [x] Create AutoResponseManager.swift
  - [x] Toggle activation/deactivation
  - [x] Default prompt management
  - [x] Iteration counter
  - [x] Stop phrase detection
- [x] Add UI controls
  - [x] Settings configuration
  - [x] Active mode indicator in chat
  - [x] Emergency stop button
  - [x] Auto-response history log
- [x] Implement safety features
  - [x] Max iteration limit
  - [x] Timeout handling
  - [x] Error detection
- [x] Integration testing with various scenarios

#### ✅ **COMPLETED DELIVERABLES**
- **AutoResponseManager.swift**: Complete implementation with safety features
- **Full Configuration System**: Enable/disable, prompts, iterations, stop phrases, timeouts
- **Safety Features**: Safe mode, dangerous pattern detection, confirmation requirements
- **History Tracking**: Complete audit log of auto-response activities
- **Settings Integration**: Fully integrated into enhanced settings view

#### Default Configuration
```swift
struct AutoResponseConfig {
    var enabled: Bool = false
    var defaultPrompt: String = "Continue working on the current task. If you need clarification, make reasonable assumptions and proceed."
    var maxIterations: Int = 10
    var stopPhrases: [String] = ["TASK_COMPLETE", "NO_MORE_WORK", "FINISHED"]
    var timeoutSeconds: Int = 300
}
```

---

### 6. Attachment Support ✅ COMPLETED
**Goal**: Send images and files to Claude

#### Current Issues
- [x] Identified: No way to share images
- [x] Identified: Can't send code files
- [x] Identified: No document support

#### Implementation Tasks
- [x] Create AttachmentPicker.swift
  - [x] Photo library integration
  - [x] Camera support
  - [x] Document picker
  - [x] Multiple selection
- [x] Add attachment button to input bar
- [x] Implement preview UI
  - [x] Thumbnail generation
  - [x] Remove option
  - [x] File size display
- [x] Server communication
  - [x] Base64 encoding
  - [x] Multipart upload
  - [x] Progress indicator
- [x] Server-side implementation
  - [x] Add /api/upload endpoint
  - [x] Forward to Claude CLI
  - [x] Handle large files

#### ✅ **COMPLETED DELIVERABLES**
- **AttachmentPicker.swift**: Complete file/image selection with camera, photo library, and document support
- **AttachmentPreview.swift**: Thumbnail previews with remove functionality and size limits
- **Enhanced Message.swift**: Extended RichContent system to support attachments
- **Enhanced ChatInputBar.swift**: Attachment button, preview area, and sending logic
- **Enhanced MessageBubble.swift**: Display attachments in message bubbles with tap handlers
- **File Type Support**: Images, documents, code files with proper MIME type detection
- **Size Limits**: 10MB per file limit with user feedback

---

## Technical Notes

### Key Files to Modify
- `SettingsView.swift` - Complete redesign needed
- `MessageBubble.swift` - Markdown parser enhancements
- `ChatView.swift` - Scroll fixes, thinking indicator
- `ChatViewModel.swift` - Auto-response logic integration
- `HTTPAICLIService.swift` - Attachment upload support

### New Files to Create
- `AutoResponseManager.swift` - Auto-response logic
- `AttachmentPicker.swift` - File/image selection
- `ThinkingIndicator.swift` - Processing visualization
- `NotificationMarkdownRenderer.swift` - Rich notifications
- `EnhancedSettingsView.swift` - New settings implementation

### Server Requirements
- `/api/upload` endpoint for attachments
- WebSocket enhancement for thinking status
- Attachment forwarding to Claude CLI
- Status message protocol updates

---

## Progress Log

### Session 1 - Initial Planning
- Created comprehensive enhancement plan
- Identified all major issues
- Structured implementation approach
- Ready to begin Settings View overhaul

### Next Steps
1. Start with Settings View overhaul (highest impact)
2. Implement Auto-Response Mode (most requested feature)
3. Fix scroll issues (UX critical)
4. Add attachment support (functionality expansion)

---

## Testing Checklist

### Device Testing
- [ ] iPhone SE (smallest)
- [ ] iPhone 15 Pro
- [ ] iPhone 15 Pro Max
- [ ] iPad Mini
- [ ] iPad Pro 11"
- [ ] iPad Pro 12.9"

### iOS Versions
- [ ] iOS 16.0 (minimum)
- [ ] iOS 17.0
- [ ] iOS 18.0 (latest)

### Scenarios
- [ ] Fresh install
- [ ] Upgrade from previous version
- [ ] Various network conditions
- [ ] Background/foreground transitions
- [ ] Memory pressure situations

---

## Notes and Decisions

### Design Principles
- Maintain consistency with Apple HIG
- Prioritize user safety (especially in auto-mode)
- Keep it simple but powerful
- Responsive design for all devices

### Technical Decisions
- Use SwiftUI exclusively (no UIKit except where necessary)
- Async/await for all network operations
- Combine for reactive updates
- UserDefaults for settings persistence

### Open Questions
- Should auto-response mode have voice announcements?
- How to handle attachments over 10MB?
- Should we add CloudKit sync for settings?
- Rate limiting for auto-responses?

---

*Last Updated: [Current Session]*
*Status: Ready to implement*