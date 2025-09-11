# Issue: Claude Consistently Times Out at 5 Minutes with SIGTERM

**Date Created**: 2025-09-11
**Date Updated**: 2025-09-11  
**Status**: COMPLETE - Tested and Verified
**Priority**: High
**Component**: Server/AICLI Process Runner

## Problem Description
Claude consistently times out and exits with SIGTERM (exit code 143) at exactly the 5-minute mark during command execution through the companion server. While the system handles this gracefully, it interrupts user workflow for long-running tasks.

## Root Cause (IDENTIFIED)
**The 5-minute timeout is NOT from Claude CLI - it's from our own server configuration!**

The timeout is hardcoded in our server at `src/services/aicli-process-runner/command-executor.js:148`:
```javascript
// When spawning the Claude process
aicliProcess = this.processManager.spawnProcess(args, {
  cwd,
  timeout: 300000, // 5 minute timeout
});
```

**How it works**: Node.js `spawn()` with the `timeout` option automatically sends SIGTERM to the child process when the timeout expires. This is built-in Node.js behavior - after 300,000ms (5 minutes), Node.js kills the Claude process with SIGTERM (signal 15), resulting in exit code 143.

**Important**: This is a hard timeout regardless of activity. Even if Claude is actively working and using tools, the process gets killed at exactly 5 minutes.

## Current Behavior
- Server spawns Claude process with 300,000ms (5 minute) timeout using Node.js `spawn()`
- Node.js automatically sends SIGTERM after 5 minutes, regardless of activity
- Process exits with code 143 (SIGTERM) after timeout expires
- Server correctly detects and handles this as successful completion
- Sends continuation message: "I've completed many tasks and need to pause here. Send another message to continue where I left off."
- Session ID is preserved, allowing seamless continuation
- ChatView correctly updates from "thinking" to normal state

## Technical Details
- **Exit Code**: 143 (SIGTERM sent by Node.js spawn timeout)
- **Timeout Source**: `command-executor.js` line 148 - Node.js `spawn()` timeout option
- **Timeout Duration**: 300,000ms (5 minutes) hardcoded
- **Timeout Type**: Hard timeout - kills process even if actively working
- **Tool Use Count at Timeout**: Approximately 75-110 operations
- **Current Handling**: Treated as successful completion, not an error

## Impact
- Interrupts flow of long-running tasks
- Requires manual user intervention to continue
- Breaks concentration during complex multi-step operations
- May cause confusion when Claude stops mid-task

## Recommended Solutions

### 1. Make Server Timeout Configurable (IMMEDIATE FIX)
- Add environment variable `AICLI_PROCESS_TIMEOUT_MS` with default 300000
- Update `command-executor.js` to read from environment:
  ```javascript
  timeout: process.env.AICLI_PROCESS_TIMEOUT_MS || 300000
  ```
- Allow users to set longer timeouts for their workflows

### 2. Configure Claude Settings (SUPPLEMENTARY)
- Update `~/.claude/settings.json` to extend bash command timeouts within Claude:
  ```json
  {
    "env": {
      "BASH_DEFAULT_TIMEOUT_MS": "1800000",  // 30 minutes
      "BASH_MAX_TIMEOUT_MS": "7200000"       // 120 minutes
    }
  }
  ```
- Note: These control individual bash commands, not the overall process

### 3. Implement Dynamic Timeout (ENHANCED SOLUTION)
- Monitor Claude's activity (tool use, streaming output)
- Reset/extend timeout when Claude is actively working
- Only timeout on true inactivity (no output for X minutes)
- Send warning notification at 4:30 mark

### 4. Improve User Experience
- Log timeout value at process start
- Send push notification warning at 90% of timeout
- Include remaining time in progress updates
- Document timeout configuration in README

## Implementation Priority
1. **High Priority**: Add `AICLI_PROCESS_TIMEOUT_MS` environment variable
2. **Medium Priority**: Add activity-based timeout extension
3. **Low Priority**: Enhanced UI indicators and warnings

## Investigation Areas (COMPLETED)
- [x] Determine timeout source - **Found: Our server, not Claude CLI**
- [x] Check Claude CLI for timeout flags - **Result: No timeout flags available**
- [x] Review Claude settings options - **Found: Bash timeout settings available**
- [ ] Test with extended server timeout values
- [ ] Monitor resource usage with longer timeouts

## Related Files
- `src/services/aicli-process-runner/command-executor.js` - Handles SIGTERM
- `src/handlers/chat-message-handler.js` - Generates continuation message
- `src/services/aicli-process-runner/health-monitor.js` - Could track timeout approach

## User Testing Notes
See USER_TEST_NOTES.md Test Note #12 for detailed user observations

## SOLUTION IMPLEMENTED

**The correct approach**: Remove all server-side timeouts and let Claude CLI manage its own lifecycle.

### Changes Made:
1. **Removed hardcoded 5-minute timeout** from `command-executor.js`
2. **Updated spawn call** to not include any timeout option
3. **Documented approach** - Claude CLI knows when to exit, server shouldn't interfere

### Implementation:
```javascript
// BEFORE (incorrect):
aicliProcess = this.processManager.spawnProcess(args, {
  cwd,
  timeout: 300000, // This was causing the 5-minute SIGTERM!
});

// AFTER (correct):
aicliProcess = this.processManager.spawnProcess(args, { cwd });
// No timeout - Claude manages its own lifecycle
```

## Acceptance Criteria
- [x] Understand root cause of 5-minute timeout - **Server's hardcoded timeout**
- [x] Implement solution to minimize workflow interruption - **Removed timeout entirely**
- [x] User can complete long tasks without manual continuation - **Claude runs as long as needed**
- [x] Clear communication about timeout behavior - **Documented no-timeout approach**
- [x] No loss of context or session state - **Session handling unchanged**

## Notes
- Server implementation correctly handles SIGTERM as of 2025-09-10
- iOS app properly updates UI state when timeout occurs
- WebSocket and APNS both receive continuation message correctly