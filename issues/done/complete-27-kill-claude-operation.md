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

**Current Status**: ✅ Completed (Full Stack)  
**Last Updated**: 2025-08-23

## Solution Summary

The kill/cancel functionality has been **fully implemented** on both server and iOS sides. Users can now terminate running Claude operations with a tap of the stop button that appears during processing.

### ✅ What Was Implemented (Server-Side)

#### 1. **Kill Endpoint** (`/api/chat/kill`)
```javascript
POST /api/chat/kill
{
  "sessionId": "session-id",
  "deviceToken": "device-token", // optional
  "reason": "User requested cancellation" // optional
}
```

Response:
```javascript
{
  "success": true,
  "sessionId": "session-id",
  "message": "Session terminated successfully",
  "processKilled": true,
  "sessionCleaned": true,
  "timestamp": "2025-08-23T..."
}
```

#### 2. **Process Tracking & Killing** (`aicli-process-runner.js`)
- Tracks all active Claude processes in `activeProcesses` Map
- `killProcess(sessionId, reason)` method:
  - Sends SIGINT first (graceful shutdown)
  - Waits 2 seconds for graceful termination
  - Sends SIGKILL if process doesn't terminate
  - Cleans up process tracking
  - Emits `processKilled` event

#### 3. **Session Termination** (`aicli-session-manager.js`)
- `terminateSession(sessionId, reason)` method:
  - Removes session from all tracking maps
  - Clears message buffers
  - Clears project session mappings
  - Emits `sessionTerminated` event
  - Returns whether session existed

#### 4. **Orchestration** (`aicli.js`)
- `killSession(sessionId, reason)` method:
  - Kills the Claude process
  - Terminates the session
  - Clears message buffers
  - Returns comprehensive result

#### 5. **Push Notifications**
- Sends notification when session is terminated
- Uses existing `sendAutoResponseControlNotification` with `action: 'stop'`
- Includes termination reason

### ✅ How It Works

1. **Client Request**: iOS app sends kill request with sessionId
2. **Process Termination**: Server finds and kills the Claude process
3. **Session Cleanup**: All session data is cleared
4. **User Notification**: Push notification confirms termination
5. **Ready State**: System ready for new conversation immediately

### ✅ Safety Features

- **Graceful Shutdown**: Tries SIGINT before SIGKILL
- **Timeout Protection**: 2-second grace period for cleanup
- **Complete Cleanup**: Removes all session traces
- **Event Emissions**: Other components notified of termination
- **Error Handling**: Graceful failures if session not found

### ✅ What Was Implemented (iOS Side)

#### 1. **Stop Button UI** (`ChatInputBar.swift`)
- Added `isProcessing` and `onStopProcessing` parameters
- Shows red stop button (`stop.circle.fill`) when processing
- Smooth transition animation between send and stop buttons
- Haptic feedback on tap

#### 2. **Confirmation Dialog** (`ChatView.swift`)
- Alert dialog: "Stop Claude?"
- Clear warning message about session termination
- Cancel and "Stop Work" (destructive) buttons
- Calls `confirmStopProcessing` on confirmation

#### 3. **Kill Operations** (`ChatViewModel.swift`)
- `killSession` method calls server endpoint
- Clears loading and waiting states
- Updates project state to not processing
- `addSystemMessage` adds termination notice to chat

#### 4. **Network Integration** (`MessageOperations.swift`)
- `killSession` method sends POST to `/api/chat/kill`
- Includes device token for push notifications
- Clears session ID on successful kill
- Proper error handling

#### 5. **Session Management** (`SessionManager.swift`, `AICLIService.swift`)
- `getSessionId` retrieves stored session ID for project
- Session ID cleared after successful kill
- Proper cleanup of session state

### ✅ Files Modified

**Server-side:**
- **`server/src/routes/chat.js`**: Added `/api/chat/kill` endpoint
- **`server/src/services/aicli.js`**: Added `killSession` orchestration method
- **`server/src/services/aicli-process-runner.js`**: Added process tracking and `killProcess` method
- **`server/src/services/aicli-session-manager.js`**: Added `terminateSession` and `clearSessionBuffer` methods

**iOS-side:**
- **`ios/.../ChatInputBar.swift`**: Added stop button UI with processing state
- **`ios/.../ChatView.swift`**: Added confirmation dialog and stop processing logic
- **`ios/.../ChatViewModel.swift`**: Added `killSession` and `addSystemMessage` methods
- **`ios/.../MessageOperations.swift`**: Added `killSession` network call
- **`ios/.../SessionManager.swift`**: Added `getSessionId` method
- **`ios/.../AICLIService.swift`**: Added public `killSession` and `getSessionId` methods

The full-stack implementation is **production-ready** and provides users with complete control to terminate any running Claude operation.