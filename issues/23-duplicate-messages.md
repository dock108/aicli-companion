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

[To be determined after investigation]

## Solution Implemented

### 1. Message Deduplication
- Implement proper message ID checking
- Prevent duplicate additions to UI

### 2. Reconnection Handling
- Fix reconnection message restoration
- Prevent multiple restore operations

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

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22