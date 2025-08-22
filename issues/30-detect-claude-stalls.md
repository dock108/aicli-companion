# Issue #30: Detect When Claude Stalls Without Sending Data

**Priority**: High  
**Component**: Server - Process Monitoring  
**Beta Blocker**: Yes (Users need to know if Claude stopped)  
**Discovered**: 2025-08-22  
**Status**: New  

## Problem Description

Now that we've removed all artificial timeouts (Issue #25), we need a way to detect when Claude has actually stalled or stopped processing without sending any response back. This should be based on actual activity monitoring rather than arbitrary time limits. Users need to be alerted when Claude stops without completing the task.

## Investigation Areas

1. Monitor Claude CLI process for activity (stdout/stderr output)
2. Track last activity timestamp during processing
3. Define "stall" as no output for X seconds (configurable, maybe 2-3 minutes)
4. Detect if Claude process died/crashed
5. Send alert to user when stall detected
6. Differentiate between "thinking" and "stalled"
7. Allow for silent periods during complex operations
8. Implement recovery suggestions for users

## Expected Behavior

- Monitor Claude's output stream for activity
- If no output for 2-3 minutes, consider it potentially stalled
- Send warning to user: "Claude appears to have stopped responding"
- Provide options: Wait longer, Kill process, Start new session
- Detect actual process death immediately

## Files to Investigate

- `server/src/services/aicli-process-runner.js` (activity monitoring)
- `server/src/services/aicli-session-manager.js` (stall detection)
- `server/src/services/push-notification.js` (stall alerts)
- `server/src/utils/process-monitor.js` (new - process health monitoring)

## Implementation Approach

### 1. Activity Tracker
```javascript
class ActivityMonitor {
  constructor(sessionId, processRef) {
    this.lastActivityTime = Date.now();
    this.sessionId = sessionId;
    this.process = processRef;
    this.checkInterval = null;
    this.stallThreshold = 120000; // 2 minutes default
  }
  
  recordActivity() {
    this.lastActivityTime = Date.now();
  }
  
  startMonitoring(onStallCallback) {
    this.checkInterval = setInterval(() => {
      const silentDuration = Date.now() - this.lastActivityTime;
      if (silentDuration > this.stallThreshold) {
        onStallCallback(this.sessionId, silentDuration);
      }
    }, 30000); // Check every 30 seconds
  }
  
  stopMonitoring() {
    clearInterval(this.checkInterval);
  }
}
```

### 2. Process Health Check
```javascript
// Check if process is still alive
if (!claudeProcess.killed && claudeProcess.exitCode === null) {
  // Process is running but not producing output
  logger.warn('Claude process alive but silent', { 
    sessionId, 
    silentDuration 
  });
} else {
  // Process died
  logger.error('Claude process died unexpectedly', { 
    sessionId,
    exitCode: claudeProcess.exitCode 
  });
}
```

### 3. User Notification
```javascript
// Send stall alert via APNS
await pushNotificationService.sendStallAlert({
  deviceToken,
  sessionId,
  requestId,
  message: 'Claude appears to have stopped responding',
  silentDuration: Math.floor(silentDuration / 1000),
  options: ['Wait', 'Stop', 'Restart']
});
```

## Configuration

```bash
# Stall detection threshold in milliseconds
# Default: 120000 (2 minutes of silence = potential stall)
CLAUDE_STALL_THRESHOLD=120000

# Whether to auto-kill stalled processes
# Default: false (alert user instead)
CLAUDE_AUTO_KILL_STALLED=false
```

## Testing Requirements

### Manual Testing Steps
1. Start a Claude operation
2. Simulate stall (pause stdout)
3. Verify stall detected after threshold
4. Check user receives alert
5. Test recovery options

### Test Scenarios
- [ ] Normal processing (no false positives)
- [ ] Actual stall detection
- [ ] Process crash detection
- [ ] Silent thinking periods
- [ ] Recovery from stall

## Stall vs Normal Operation

### Normal Silent Periods
- Claude thinking/planning
- Reading large files
- Processing complex logic

### Actual Stalls
- Process deadlock
- Claude CLI crash
- Infinite loop
- Network issues

## User Alert Message

```
⚠️ Claude Activity Alert

Claude hasn't produced any output for 2 minutes.
This might mean:
• Claude is thinking deeply about the problem
• The process has stalled
• Claude has encountered an error

Options:
[Wait Longer] [Stop Claude] [Check Status]
```

## Related Issues

- **Issue #25**: Removed artificial timeouts
- **Issue #28**: Activity monitoring logs
- **Issue #29**: Heartbeat updates

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22