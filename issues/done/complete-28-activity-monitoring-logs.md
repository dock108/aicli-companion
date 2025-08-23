# Issue #28: Restore Activity Monitoring Logs for Claude Sessions

**Priority**: High  
**Component**: Server - Logging/Monitoring  
**Beta Blocker**: No (but improves debugging and UX)  
**Discovered**: 2025-08-22  
**Status**: ✅ Completed (via Issues #36, #1, #29)  

## Problem Description

The server previously had activity monitoring logs that showed when Claude was actively working on a session. This functionality has been removed/lost, making it difficult to know if Claude is still processing or has stalled. We need to restore this logging to provide visibility into Claude's ongoing work.

## Investigation Areas

1. Search for previous activity monitoring implementation in git history
2. Identify where activity notices were logged before
3. Check if streaming output from Claude CLI can be used as activity indicator
4. Implement periodic "still working" logs during long operations
5. Log meaningful progress indicators (tool use, thinking, etc.)
6. Include session ID in all activity logs for tracking
7. Consider log levels for activity (info vs debug)
8. Ensure logs are useful but not spammy

## Expected Behavior

Server logs should show periodic activity updates like:
```
[INFO] Claude still processing for session abc123... (5 minutes elapsed)
[INFO] Claude using tool: Read file.js (session: abc123)
[INFO] Claude generating response... (session: abc123)
[INFO] Activity detected: streaming output (session: abc123)
```

## Files to Investigate

- `server/src/services/aicli-process-runner.js` (stream monitoring)
- `server/src/services/aicli-session-manager.js` (session tracking)
- `server/src/services/aicli.js` (main processing)
- `server/src/utils/logger.js` (logging utilities)
- Check git history for removed activity monitoring code

## Implementation Approach

### 1. Stream-Based Activity Detection
- Monitor stdout/stderr from Claude CLI process
- Log when data is received (proof of activity)
- Throttle logs to avoid spam (e.g., once per 30 seconds)

### 2. Periodic Status Logs
- Set interval timer during processing
- Log elapsed time and session ID
- Clear timer when processing completes

### 3. Tool Use Monitoring
- Parse Claude's tool use events
- Log which tools are being used
- Provides insight into what Claude is doing

### 4. Integration Points
- Hook into existing stream handlers
- Add activity monitoring to process runner
- Ensure session ID is always included

## Testing Requirements

### Manual Testing Steps
1. Start a long-running Claude operation
2. Monitor server logs for activity updates
3. Verify logs appear periodically
4. Check session ID is included
5. Ensure logs stop when processing completes

### Test Scenarios
- [ ] Long code generation task
- [ ] Multiple file operations
- [ ] Silent thinking periods
- [ ] Error scenarios

## Log Format Suggestions

```javascript
// Every 30 seconds of activity
logger.info('Claude activity detected', {
  sessionId,
  elapsedMs: Date.now() - startTime,
  lastActivity: 'streaming output',
  status: 'processing'
});

// On tool use
logger.info('Claude using tool', {
  sessionId,
  tool: toolName,
  elapsedMs: Date.now() - startTime
});

// Heartbeat when no output but still running
logger.info('Claude still processing', {
  sessionId,
  elapsedMinutes: Math.floor((Date.now() - startTime) / 60000),
  lastActivityMs: Date.now() - lastActivityTime
});
```

## Related Issues

- Links to Issue #29 (iOS heartbeat updates)
- Enables Issue #1 (Project status indicator)

## Status

**Current Status**: ✅ Completed (via Issues #36, #1, #29)  
**Last Updated**: 2025-08-23

## Solution Summary

Activity monitoring has been **fully implemented** through the heartbeat system and enhanced logging added while fixing Issues #1, #29, and #36.

### ✅ What Was Implemented

#### 1. **Real-time Activity Monitoring** (`aicli-process-runner.js`)
- `healthMonitor.recordActivity()` tracks all Claude activities
- Detects and logs specific activities:
  - Tool usage: `Using ${toolName}`
  - Text generation: `Generating response`
  - Thinking: `Thinking`
- Updates activity type immediately when detected

#### 2. **Heartbeat Broadcasting** (Every 10 seconds)
- Broadcasts project status via WebSocket to all connected clients
- Includes:
  - `projectPath`: Current working directory
  - `isProcessing`: true while Claude is working
  - `lastActivity`: Current activity type
  - `elapsedSeconds`: Time since processing started
- iOS app displays this as typing bubble with activity text

#### 3. **Enhanced Logging** 
- Session-aware logging with `sessionLogger.child({ sessionId })`
- Activity logs for:
  - Tool use detection: `Tool use detected in stream`
  - Text accumulation: `Accumulated text content from [field]`
  - Session tracking: `Claude still processing for session ${sessionId}`
  - Completion: `Got complete response with result type`

#### 4. **Stream-based Activity Detection**
- Monitors stdout/stderr from Claude CLI process
- Parses streaming chunks in real-time
- Logs meaningful progress indicators
- Throttled to avoid spam

### ✅ Actual Log Examples Now Generated

```javascript
// Tool use
"Tool use detected in stream" { toolName: 'Read', sessionId: 'abc123' }

// Activity tracking  
"Heartbeat broadcasting" { 
  projectPath: '/Users/project',
  isProcessing: true,
  lastActivity: 'Using Edit tool',
  elapsedSeconds: 45
}

// Text accumulation
"Accumulated text content from assistant message" {
  textLength: 256,
  totalAccumulated: 1024,
  sessionId: 'abc123'
}

// Session activity
"Claude still processing for session abc123" {
  elapsedSeconds: 120,
  lastActivity: 'Generating response'
}
```

### ✅ All Requirements Met

- ✅ **Stream-Based Activity Detection**: Implemented via `healthMonitor`
- ✅ **Periodic Status Logs**: Heartbeat every 10 seconds
- ✅ **Tool Use Monitoring**: Specific tool names logged
- ✅ **Session ID Tracking**: All logs include sessionId
- ✅ **Non-spammy**: Throttled with 10-second intervals
- ✅ **iOS Integration**: Heartbeats show as typing bubbles
- ✅ **Progress Visibility**: Users see what Claude is doing in real-time

The activity monitoring system is now **more comprehensive than originally requested**, providing both server-side logging and real-time client updates via WebSocket heartbeats.