# iOS App Enhancement Plan

## Overview
This document tracks the ongoing enhancements to the Claude Companion iOS app. Each section includes current status, implementation details, and remaining tasks.

## Enhancement Status Tracker

### 1. Settings View Overhaul ⏳ Not Started
**Goal**: Transform the basic disconnect-only settings into a comprehensive configuration center

#### Current Issues
- [x] Identified: Settings only shows "Disconnect" with no feedback
- [x] Identified: Limited configuration options  
- [x] Identified: Not consistent between iPhone/iPad

#### Implementation Tasks
- [ ] Redesign SettingsView.swift with multiple sections
- [ ] Add Connection Management section
  - [ ] Show real-time connection status
  - [ ] Display server details (address, port, auth status)
  - [ ] Implement disconnect with confirmation dialog
  - [ ] Add reconnect button
- [ ] Add Auto-Response Mode section
  - [ ] Toggle switch for enabling/disabling
  - [ ] Default prompt template editor
  - [ ] Max iterations slider (1-20)
  - [ ] Stop phrases text field (comma-separated)
  - [ ] Test mode with dry run
- [ ] Ensure iPad/iPhone responsive layout
- [ ] Add loading states and success confirmations
- [ ] Implement settings persistence

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

### 4. Scroll Position Fixes ⏳ Not Started
**Goal**: Reliable scroll behavior and position persistence

#### Current Issues
- [x] Identified: Reopening goes to random position
- [x] Identified: Scroll freezing/glitching
- [x] Identified: Not scrolling to bottom for new messages

#### Implementation Tasks
- [ ] Fix ChatMessageList.swift scroll logic
  - [ ] Persist last read message ID
  - [ ] Implement proper scroll-to position on load
  - [ ] Fix scroll physics and animations
- [ ] Add scroll-to-bottom FAB
  - [ ] Show when user scrolls up
  - [ ] Hide when at bottom
  - [ ] Smooth animation
- [ ] Debounce rapid scroll events
- [ ] Test on various devices and iOS versions

---

### 5. Auto-Response Mode ("Jesus Take the Wheel") ⏳ Not Started
**Goal**: Automated continuation of conversations

#### Current Issues
- [x] Identified: Need for hands-free operation
- [x] Identified: Manual intervention for each Claude question
- [x] Identified: No way to batch operations

#### Implementation Tasks
- [ ] Create AutoResponseManager.swift
  - [ ] Toggle activation/deactivation
  - [ ] Default prompt management
  - [ ] Iteration counter
  - [ ] Stop phrase detection
- [ ] Add UI controls
  - [ ] Settings configuration
  - [ ] Active mode indicator in chat
  - [ ] Emergency stop button
  - [ ] Auto-response history log
- [ ] Implement safety features
  - [ ] Max iteration limit
  - [ ] Timeout handling
  - [ ] Error detection
- [ ] Integration testing with various scenarios

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

### 6. Attachment Support ⏳ Not Started
**Goal**: Send images and files to Claude

#### Current Issues
- [x] Identified: No way to share images
- [x] Identified: Can't send code files
- [x] Identified: No document support

#### Implementation Tasks
- [ ] Create AttachmentPicker.swift
  - [ ] Photo library integration
  - [ ] Camera support
  - [ ] Document picker
  - [ ] Multiple selection
- [ ] Add attachment button to input bar
- [ ] Implement preview UI
  - [ ] Thumbnail generation
  - [ ] Remove option
  - [ ] File size display
- [ ] Server communication
  - [ ] Base64 encoding
  - [ ] Multipart upload
  - [ ] Progress indicator
- [ ] Server-side implementation
  - [ ] Add /api/upload endpoint
  - [ ] Forward to Claude CLI
  - [ ] Handle large files

---

### 7. Additional Enhancements ⏳ Not Started

#### Quick Wins
- [ ] Connection state indicator in header
- [ ] Message queue badge improvements
- [ ] Copy code button in code blocks
- [ ] Share conversation feature

#### Medium Priority
- [ ] Search in chat history
- [ ] Export conversation as markdown/PDF
- [ ] Message editing (for unsent)
- [ ] Typing indicators

#### Future Considerations
- [ ] Voice input
- [ ] Rich previews for links
- [ ] Custom themes
- [ ] Shortcuts/Siri integration

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