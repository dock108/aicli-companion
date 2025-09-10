# Issue 090825-1: Missing New Message Indicators on Main Screen

**Priority**: High  
**Component**: iOS App - Main Screen  
**Beta Blocker**: Yes (users cannot see when new messages arrive)  
**Discovered**: 2025-09-06  
**Status**: Resolved  
**Resolved**: 2025-09-08  

## Problem Description

The main screen lacks any indication of new messages, making it impossible to know when responses arrive without opening the chat. Users must manually check each conversation to see if there are new messages.

## Investigation Areas

1. Conversation list cell configuration for badge display
2. Core Data model for read/unread state tracking
3. Message arrival notification handling
4. CloudKit sync for read state across devices
5. Performance impact of preview text rendering

## Expected Behavior

Users should be able to see at a glance which conversations have new messages without opening them.

## Files to Investigate

- `ios/AICLICompanion/Views/MainView.swift` (conversation list display)
- `ios/AICLICompanion/Views/ConversationListItemView.swift` (individual cell configuration)
- `ios/AICLICompanion/Models/Conversation+CoreDataClass.swift` (add unread count property)
- `ios/AICLICompanion/Services/NotificationHandler.swift` (update unread state on message arrival)
- `ios/AICLICompanion/Services/CloudKitManager.swift` (sync read state)

## Root Cause Analysis

The app was not tracking unread message state. The ProjectRowView had commented-out code for unread indicators but lacked the underlying infrastructure to support it.

## Solution Implemented

Implemented a comprehensive unread message tracking system with the following components:

1. **Data Model Updates**: Added `unreadCount` and `lastReadMessageId` properties to the Conversation model
2. **Persistence Layer**: Added unread state management to MessagePersistenceService with methods to track and update unread counts
3. **UI Updates**: Updated ProjectRowView to display unread message badges and message previews
4. **Read State Management**: Messages are automatically marked as read when a conversation is opened in ChatView

### Code Changes

**Modified Files:**
1. `ios/Sources/AICLICompanion/Services/Persistence/ConversationModels.swift`
   - Added unreadCount and lastReadMessageId properties
   - Added markAsRead() and updateUnreadCount() methods
   - Added message preview properties to ConversationMetadata

2. `ios/Sources/AICLICompanion/MessagePersistenceService.swift`
   - Added UnreadState struct for tracking read/unread state
   - Implemented getUnreadCount(), markAsRead(), and getLastMessagePreview() methods

3. `ios/Sources/AICLICompanion/ProjectSelectionView.swift`
   - Uncommented and updated unread indicator badge display
   - Added message preview display with sender identification
   - Implemented loadUnreadState() and loadMessagePreview() methods

4. `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift`
   - Added automatic marking of messages as read in onAppear

## Testing Requirements

- Verify badge count accuracy
- Test message preview truncation
- Validate state persistence across app launches
- Test CloudKit sync of read/unread state
- Performance testing with many conversations
- Accessibility testing for visual indicators

### Manual Testing Steps
1. Send a message and close the conversation
2. Receive a response while on main screen
3. Verify badge/indicator appears
4. Open conversation and verify badge clears
5. Test with multiple conversations

### Test Scenarios
- [x] Badge appears for new messages
- [x] Preview text displays correctly
- [x] Read state persists across app launches
- [ ] CloudKit sync works across devices (deferred for future implementation)
- [x] Performance with 50+ conversations

## Status

**Current Status**: Resolved  
**Last Updated**: 2025-09-08

### Implementation Checklist
- [x] Root cause identified
- [x] Solution designed
- [x] Code changes made
- [x] Tests written
- [x] Manual testing completed
- [x] Code review passed (SwiftLint: 0 violations)
- [x] Deployed to beta

## Result

Successfully implemented new message indicators on the main screen with the following features:
- **Unread Badge**: Blue circular badge with unread count (capped at 99)
- **Message Preview**: Shows sender ("You:" or "Claude:") and first 100 characters of last message
- **Auto-Read**: Messages automatically marked as read when conversation is opened
- **Persistence**: Read/unread state persists across app launches
- **Performance**: Efficient loading with minimal impact on scroll performance

The implementation resolves the core issue where users had no way to know when Claude had replied without manually checking each conversation.