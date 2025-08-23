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

**Current Status**: ✅ Completed  
**Last Updated**: 2025-08-23

## Solution Summary

Stall detection has been **fully implemented** with automatic push notifications to alert users when Claude stops responding.

### ✅ What Was Implemented

#### 1. **Activity Monitoring in Health Monitor** (`aicli-process-runner.js`)
- Tracks `lastActivityTime` for every Claude output
- Checks for stalls every 30 seconds
- Configurable stall threshold via `CLAUDE_STALL_THRESHOLD` (default: 2 minutes)
- Differentiates between stalled process and dead process

#### 2. **Push Notification Alerts** (`push-notification.js`)
- New `sendStallAlert` method for stall-specific notifications
- Different alerts for:
  - ⚠️ "Claude May Have Stalled" - process alive but silent
  - ❌ "Claude Process Stopped" - process died unexpectedly
- Shows last known activity and duration of silence

#### 3. **Device Token Propagation**
- Device token passed through entire call chain:
  - `chat.js` → `aicli.js` → `aicli-process-runner.js`
- Enables direct push notifications to the requesting device
- Falls back gracefully if no device token available

#### 4. **Configurable Behavior**
```bash
# Stall detection threshold in milliseconds
CLAUDE_STALL_THRESHOLD=120000  # Default: 2 minutes

# Auto-kill stalled processes after 2 warnings
CLAUDE_AUTO_KILL_STALLED=false  # Default: false (alert only)
```

#### 5. **Event System**
- Emits `processStall` event with detailed stall information
- Emits `processDeath` event when process dies
- Allows other components to react to stalls

### ✅ How It Works

1. **Activity Recording**: Every output from Claude updates `lastActivityTime`
2. **Stall Detection**: Every 30 seconds, checks if silence exceeds threshold
3. **User Notification**: Sends push notification with actionable information
4. **Process Health**: Detects if process died vs just stalled
5. **Auto-Recovery**: Optional auto-kill after multiple stall warnings

### ✅ User Experience

When Claude stalls, users receive:
```
⚠️ Claude May Have Stalled
No output for 2 minutes. Last activity: Using Edit tool
[Wait Longer] [Stop Claude] [Check Status]
```

When Claude process dies:
```
❌ Claude Process Stopped
Claude process unexpectedly stopped. Last activity: Generating response
[Start New Session] [View Logs]
```

### ✅ Files Modified

- **`server/src/services/aicli-process-runner.js`**: Added stall detection to health monitor
- **`server/src/services/push-notification.js`**: Added sendStallAlert method
- **`server/src/services/aicli.js`**: Added device token propagation
- **`server/src/routes/chat.js`**: Pass device token to AICLI service

The stall detection system is now **production-ready** and provides comprehensive monitoring of Claude's processing state.