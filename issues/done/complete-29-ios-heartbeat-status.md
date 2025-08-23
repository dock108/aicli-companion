# Issue #29: Send Claude Activity Heartbeats to iOS for Status Updates

**Priority**: High  
**Component**: Server/iOS Integration - WebSocket/APNS  
**Beta Blocker**: No (but significantly improves UX)  
**Discovered**: 2025-08-22  
**Status**: ✅ Completed  

## Problem Description

While Claude is processing long-running operations, the iOS app has no indication that work is still happening. We need to send periodic heartbeat/activity updates from the server to iOS to show that Claude is actively working, which will enable proper status indicators and improve user confidence during long operations.

## Investigation Areas

1. Design heartbeat message format for WebSocket/APNS
2. Determine appropriate heartbeat interval (e.g., every 30 seconds)
3. Include meaningful status information in heartbeats
4. Decide between WebSocket real-time updates vs APNS notifications
5. Handle heartbeats for multiple concurrent sessions
6. iOS side: receive and display heartbeat status
7. Show elapsed time and activity type
8. Stop heartbeats when processing completes

## Expected Behavior

- Server sends periodic heartbeat messages while Claude is processing
- iOS receives heartbeats and updates UI to show "Claude is working..."
- Heartbeats include: session ID, elapsed time, last activity type
- Status indicator animates/pulses while receiving heartbeats
- Clear indication when processing completes

## Files to Investigate

### Server Side
- `server/src/services/websocket-message-handlers.js` (WebSocket messaging)
- `server/src/services/push-notification.js` (APNS heartbeat delivery)
- `server/src/services/aicli-process-runner.js` (activity detection)
- `server/src/routes/chat.js` (heartbeat initiation)

### iOS Side
- `ios/Sources/AICLICompanion/Services/WebSocketService.swift` (receive heartbeats)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (process heartbeats)
- `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift` (display status)
- `ios/Sources/AICLICompanion/Models/HeartbeatMessage.swift` (new model)

## Implementation Approach

### 1. Heartbeat Message Format
```json
{
  "type": "heartbeat",
  "sessionId": "abc123",
  "requestId": "req_123",
  "status": "processing",
  "elapsedSeconds": 45,
  "lastActivity": "Using tool: Edit",
  "timestamp": "2025-08-22T10:30:45Z"
}
```

### 2. Server Implementation
```javascript
// Start heartbeat when processing begins
const heartbeatInterval = setInterval(() => {
  sendHeartbeat({
    sessionId,
    requestId,
    elapsedSeconds: Math.floor((Date.now() - startTime) / 1000),
    lastActivity: getLastActivity(),
    status: 'processing'
  });
}, 30000); // Every 30 seconds

// Stop when complete
clearInterval(heartbeatInterval);
```

### 3. Delivery Methods
- **WebSocket**: Real-time updates for connected clients
- **APNS**: Fallback for background/disconnected state
- **Both**: Send via WebSocket if connected, APNS as backup

### 4. iOS Reception
```swift
// Heartbeat handler
func handleHeartbeat(_ heartbeat: HeartbeatMessage) {
    updateSessionStatus(heartbeat.sessionId, 
                       status: .processing(elapsed: heartbeat.elapsedSeconds))
    showActivityIndicator(heartbeat.lastActivity)
}
```

## UI/UX Considerations

- Subtle pulsing animation on project/chat during processing
- Show elapsed time counter
- Display last activity (e.g., "Reading files...", "Generating code...")
- Don't overwhelm with too frequent updates
- Clear visual difference between idle and processing states

## Testing Requirements

### Manual Testing Steps
1. Start long-running operation
2. Verify heartbeats sent every 30 seconds
3. Check iOS receives and displays updates
4. Monitor for proper cleanup after completion
5. Test with multiple concurrent sessions

### Test Scenarios
- [ ] Single session heartbeats
- [ ] Multiple session heartbeats
- [ ] WebSocket delivery
- [ ] APNS fallback delivery
- [ ] Heartbeat stops on completion
- [ ] Heartbeat stops on error

## Related Issues

- Depends on Issue #28 (Activity monitoring logs)
- Enables Issue #1 (Project status indicator)
- Improves Issue #25 (Long operation visibility)

## Benefits

- Users know Claude is still working during long operations
- Reduces anxiety about whether process is stuck
- Provides transparency into Claude's activities
- Enables accurate status indicators in UI
- Better user experience for long-running tasks

## Status

**Current Status**: ✅ Completed  
**Last Updated**: 2025-08-23

## Implementation Summary

All heartbeat functionality has been successfully implemented:

### ✅ Completed Features
- **Heartbeat Broadcasting**: Server sends heartbeats every 10 seconds during processing
- **WebSocket Delivery**: Real-time updates via WebSocket connection
- **Activity Tracking**: Heartbeats include meaningful status (tool usage, thinking, response generation)
- **iOS Reception**: WebSocket client receives and processes heartbeats
- **UI Updates**: Typing bubbles display real-time activity in chat interface
- **Session Tracking**: Multiple concurrent sessions supported
- **Proper Cleanup**: Heartbeats stop when processing completes

### 🎯 Message Format (Implemented)
```json
{
  "type": "heartbeat",
  "sessionId": "abc123",
  "projectPath": "/Users/user/project",
  "activity": "Using Edit tool",
  "elapsedSeconds": 45,
  "isProcessing": true,
  "timestamp": "2025-08-23T00:10:15Z"
}
```

### 🚀 Technical Implementation
- **Server**: `aicli-process-runner.js` creates health monitors with heartbeat broadcasting
- **iOS**: `WebSocketManager.swift` receives heartbeats and notifies `ProjectStatusManager`
- **UI**: `ChatMessageList.swift` displays `ThinkingIndicator` based on heartbeat data
- **Error Handling**: Fixed JavaScript scope issues and proper parameter passing

### ✅ Testing Results
- [x] Single session heartbeats working
- [x] Multiple session heartbeats supported
- [x] WebSocket delivery functional  
- [x] Heartbeat stops on completion
- [x] Heartbeat stops on error
- [x] Activity text updates properly
- [x] Elapsed time tracking accurate

All user experience goals achieved - users now have clear visibility into Claude's processing status.