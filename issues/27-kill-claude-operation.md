# Issue #27: Kill/Cancel Running Claude Operations from iOS

**Priority**: High (long-term)  
**Component**: iOS App/Server - Process Control  
**Beta Blocker**: No (but important for user control)  
**Discovered**: 2025-08-22  
**Status**: New  

## Problem Description

Users need a way to stop/cancel long-running Claude operations from the iOS app, similar to pressing Ctrl+C in a terminal. Currently, if Claude is processing a complex task, users have no way to interrupt it without killing the server or force-quitting the app. Initial implementation can wipe the session and start fresh, as long as users are warned about this.

## Investigation Areas

1. Add a "Stop" or "Cancel" button in iOS UI during processing
2. Implement server endpoint to kill Claude CLI process
3. Send kill signal to Claude process (SIGINT/SIGTERM)
4. Handle cleanup after killing process
5. Reset session state appropriately
6. Show warning dialog before killing ("This will end your current session")
7. Consider showing elapsed time during processing
8. Future: Implement graceful interruption without session loss

## Expected Behavior

- Show "Stop" button while Claude is processing
- Tapping Stop shows warning: "This will end your current session and stop all work. Continue?"
- On confirmation, kills Claude process immediately
- Clears session and starts fresh
- Shows message in chat: "Session terminated by user"
- Ready for new conversation immediately

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/Chat/ChatInputView.swift` (add stop button)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (stop command)
- `server/src/routes/chat.js` (add kill endpoint)
- `server/src/services/aicli-process-runner.js` (process killing logic)
- `server/src/services/aicli-session-manager.js` (session cleanup)

## Implementation Approach

### 1. iOS UI Changes
- Add stop button (red X or square icon) during processing
- Show confirmation alert before killing
- Update UI state after kill

### 2. Server Kill Endpoint
```javascript
POST /api/chat/kill
{
  "sessionId": "...",
  "requestId": "..."
}
```

### 3. Process Management
- Send SIGINT first (graceful)
- SIGKILL after timeout if needed
- Clean up session state
- Return confirmation to client

### 4. Session Handling (Initial)
- Clear session completely
- Start fresh conversation
- Show clear indication of reset

## Future Enhancements

- Graceful interruption that preserves session context
- "Pause" vs "Stop" options
- Resume capability after pause
- Save partial work before killing

## Testing Requirements

### Manual Testing Steps
1. Start long-running operation
2. Tap stop button
3. Confirm warning dialog
4. Verify process stops immediately
5. Verify can start new conversation

### Test Scenarios
- [ ] Stop during code generation
- [ ] Stop during file operations
- [ ] Stop during multi-step tasks
- [ ] Cancel the stop dialog
- [ ] Multiple stops in succession
- [ ] Stop with network issues

## UI/UX Considerations

- Stop button only visible during processing
- Clear visual difference from send button
- Warning dialog must be clear about consequences
- Consider haptic feedback on stop
- Show "Stopping..." state while killing

## Warning Dialog Text

```
Stop Claude?

This will immediately stop Claude's current work and end your session. 
You'll need to start a new conversation.

[Cancel] [Stop Work]
```

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22