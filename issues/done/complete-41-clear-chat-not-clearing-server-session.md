# Issue #41: Clear Chat Not Clearing Server Session Mapping

**Priority**: High  
**Component**: Server & iOS Integration  
**Beta Blocker**: Yes (confusing UX - cleared chat still uses old session)  
**Discovered**: 2025-08-23  
**Status**: New  

## Problem Description

When a user clears the chat in the iOS app, it only clears local data but doesn't notify the server. The server maintains a project → session mapping that persists, causing the next message to resume the old session instead of starting fresh.

## Symptoms

1. User clears chat in iOS app
2. Local messages are cleared ✅
3. Local session ID is cleared ✅
4. User sends new message
5. Server finds existing project → session mapping
6. Message is sent with `--resume` to old session ❌
7. Claude continues the previous conversation instead of starting fresh

## Root Cause

The iOS app's `clearCurrentSession()` function has outdated logic:
```swift
// HTTP doesn't need to send clearChat to server - sessions are managed by the server
// Just clear the local messages and session data
```

This comment is incorrect. The server DOES need to be notified to clear its internal mappings.

## Server-Side Evidence

From logs when sending "Hello" after clearing chat:
```
📌 Project /Users/michaelfuscoletti/Desktop/mini-golf-break → Session 91dd0f01-95f5-4153-89ff-3c318b4e5bca
📋 Found existing session 91dd0f01-95f5-4153-89ff-3c318b4e5bca, sending to existing session
Using --resume with session ID
```

## Existing Infrastructure

The server already has the proper endpoint and logic:

1. **DELETE /api/sessions/:sessionId** - Kills a session
2. **sessionManager.killSession()** - Terminates and cleans up
3. **Lines 611-617 in aicli-session-manager.js** - Clears project mapping:
```javascript
// Find and clear project session mapping
for (const [projectPath, sid] of this.projectSessions.entries()) {
  if (sid === sessionId) {
    this.projectSessions.delete(projectPath);
    break;
  }
}
```

## Solution

### Option 1: Call Kill Session Endpoint (Recommended)
When clearing chat, call the existing kill session endpoint:

```swift
private func clearCurrentSession() {
    guard let project = selectedProject else { return }
    
    // Kill the server session first if one exists
    if let sessionId = aicliService.getSessionId(for: project.path) {
        aicliService.killSession(sessionId, projectPath: project.path) { _ in
            // Continue with local cleanup regardless of server response
        }
    }
    
    // Continue with existing local cleanup...
    viewModel.clearSession()
    // ... rest of existing code
}
```

### Option 2: Add Dedicated Clear Endpoint
Create a new endpoint specifically for clearing without terminating:
- POST /api/projects/:projectPath/clear
- Removes project → session mapping only
- Leaves session alive for other potential uses

### Option 3: Clear on Next Message
Server could detect when iOS sends no sessionId and clear old mapping:
- If projectPath exists in mapping but request has no sessionId
- Clear the old mapping and start fresh
- Less explicit but more forgiving

## Implementation Steps

1. **Update ChatView.swift**:
   - Modify `clearCurrentSession()` to call kill session endpoint
   - Wait for response before local cleanup (or do in parallel)

2. **Test Scenarios**:
   - Clear chat → Send message → Should start new session
   - Clear chat while Claude is processing → Should stop processing
   - Clear chat with no active session → Should handle gracefully

3. **Optional Enhancement**:
   - Add a specific "clear" endpoint that's lighter than kill
   - Could preserve session for resume but clear project mapping

## Files to Modify

1. `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift`
   - Update `clearCurrentSession()` function
   - Remove incorrect comment about HTTP not needing server notification

2. (Optional) `server/src/routes/chat.js`
   - Add POST /api/chat/clear endpoint if going with Option 2

## Testing Requirements

1. **Clear Chat Flow**:
   - Send messages to establish session
   - Clear chat
   - Send new message
   - Verify new session ID in server logs
   - Verify Claude doesn't reference previous conversation

2. **Server State Verification**:
   - Check server logs show project mapping cleared
   - Verify `projectSessions.delete(projectPath)` is called
   - Confirm new session created after clear

3. **Edge Cases**:
   - Clear chat with no session
   - Clear chat during active processing
   - Clear chat with network issues

## Success Criteria

1. ✅ Clearing chat removes server's project → session mapping
2. ✅ Next message after clear starts a fresh session
3. ✅ Claude doesn't reference previous conversation after clear
4. ✅ Server logs show proper session lifecycle
5. ✅ No orphaned sessions in server memory

## Related Issues

- **Issue #40**: Stop button (uses same kill session infrastructure)
- **Issue #27**: Kill/Cancel operations (related endpoint)

## Status

**Current Status**: Complete  
**Last Updated**: 2025-08-23  
**Implementation**: Updated clearCurrentSession to call killSession(sendNotification: false) for silent cleanup
**Enhancement**: Added sendNotification parameter - clear chat silent, stop button sends APNS
**Notes**: Build successful, ready for production