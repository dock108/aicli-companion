# Issue #28: Restore Activity Monitoring Logs for Claude Sessions

**Priority**: High  
**Component**: Server - Logging/Monitoring  
**Beta Blocker**: No (but improves debugging and UX)  
**Discovered**: 2025-08-22  
**Status**: New  

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

**Current Status**: New  
**Last Updated**: 2025-08-22