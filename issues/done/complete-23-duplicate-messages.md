# Issue #23: Duplicate Messages Added to UI on Reconnect/Connection Re-establishment

**Priority**: High  
**Component**: iOS App - WebSocket/Message Handling  
**Beta Blocker**: Yes (Poor user experience, confusing)  
**Discovered**: 2025-08-21  
**Status**: New  

## Problem Description

Messages appear to be duplicated in the UI when the WebSocket connection is re-established or during reconnection scenarios. This creates a confusing user experience with duplicate messages appearing in the chat.

## Investigation Areas

1. Check WebSocket reconnection logic for duplicate message fetching
2. Verify message deduplication in MessagePersistenceService
3. Review how messages are restored from local storage on reconnect
4. Check if server is resending message history on reconnection
5. Ensure message IDs are properly used for deduplication
6. Review the WebSocket message handler for duplicate processing
7. Check if reconnection triggers multiple "restore" operations
8. Verify that message observers aren't being registered multiple times

## Expected Behavior

When connection is re-established, no duplicate messages should appear. Each message should appear exactly once in the UI, regardless of connection state changes.

## Files to Investigate

- `ios/Sources/AICLICompanion/Services/WebSocketService.swift` (reconnection logic)
- `ios/Sources/AICLICompanion/Services/MessagePersistenceService.swift` (deduplication)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (message handling)
- `ios/Sources/AICLICompanion/Services/Chat/ChatSessionManager.swift` (session restoration)
- `server/src/services/websocket-message-handlers.js` (server-side message handling)
- `server/src/services/websocket-reconnection.js` (reconnection behavior)

## Symptoms Observed

- Messages get added multiple times to the UI on reconnect
- Possible during connection re-establishment scenarios
- May be related to session restoration logic

## Root Cause Analysis

The issue was caused by a race condition between:
1. Messages being loaded from disk via `loadMessages()`
2. Messages being added via push notifications

When `loadMessages()` was called (e.g., during refresh), it would replace the entire message array with messages from disk. However, if a push notification had already:
- Saved the message to disk (via PushNotificationService)
- Added it to the UI array (via ChatNotificationHandler)

Then calling `loadMessages()` would load that same message from disk again, creating a duplicate.

## Solution Implemented

### 1. Added Refresh Parameter to LoadMessages
Modified `ChatMessageManager.loadMessages()` to accept an `isRefresh` parameter:
- When `isRefresh=false` (default): Replace all messages (for project switching)
- When `isRefresh=true`: Merge messages, filtering out duplicates by ID

### 2. Updated Refresh Logic
Modified ChatView pull-to-refresh to use `isRefresh=true` to prevent duplicates during refresh scenarios.

### 3. Maintained Existing Deduplication
The existing duplicate checks in `appendMessage()` remain in place as an additional safeguard.

## Testing Requirements

### Manual Testing Steps
1. Connect to server normally
2. Force disconnect (stop server)
3. Reconnect (restart server)
4. Verify no duplicate messages

### Test Scenarios
- [ ] Normal reconnection
- [ ] Multiple rapid reconnections
- [ ] Network interruption recovery
- [ ] Session restoration

## Files Modified

1. `/ios/Sources/AICLICompanion/Views/Chat/ViewModels/ChatMessageManager.swift`
   - Added `isRefresh` parameter to `loadMessages()`
   - Implemented merge logic for refresh scenarios

2. `/ios/Sources/AICLICompanion/Views/Chat/ViewModels/ChatViewModel.swift`
   - Updated to pass through `isRefresh` parameter

3. `/ios/Sources/AICLICompanion/Views/Chat/ChatView.swift`
   - Updated pull-to-refresh to use `isRefresh=true`

## Status

**Current Status**: Resolved  
**Last Updated**: 2025-08-22  
**Solution**: Implemented smart message merging during refresh to prevent duplicates while maintaining proper project switching behavior