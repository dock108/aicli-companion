# Issue #25: False Timeout Alerts for Long-Running Claude Operations

**Priority**: High  
**Component**: Server - Timeout Handling  
**Beta Blocker**: Yes (Interrupts legitimate long-running operations)  
**Discovered**: 2025-08-22  
**Status**: New  

## Problem Description

The server is sending timeout error responses even when Claude is legitimately working on complex, long-running tasks. Claude operations can take 15-20 minutes for critical updates or multi-step processes, but the server appears to be timing out prematurely and sending error notifications to the user. This interrupts the workflow and creates confusion about whether Claude is still working.

## Investigation Areas

1. Review current timeout settings in server code
2. Check if timeout is hardcoded or configurable
3. Investigate if timeout errors are coming from server or Claude CLI
4. Determine if WebSocket has separate timeout from HTTP requests
5. Check if there's a keep-alive mechanism during long operations
6. Review how server determines if Claude is still processing
7. Investigate if timeout can be disabled or set to much higher value
8. Check if Claude CLI provides progress indicators we're not using

## Expected Behavior

- Server should NOT timeout while Claude is actively processing
- Only timeout if Claude CLI itself has stopped responding or crashed
- Long-running operations (15-20+ minutes) should complete without interruption
- If Claude sends a timeout, pass it through; don't generate our own
- Consider progress indicators or heartbeat to show Claude is still working

## Files to Investigate

- `server/src/routes/chat.js` (timeout configuration)
- `server/src/services/aicli-message-handler.js` (processing timeout)
- `server/src/services/aicli-process-runner.js` (Claude CLI timeout handling)
- `server/src/config/server-config.js` (timeout settings)
- Check for any Promise.race() with timeout promises
- Look for setTimeout or timeout options in fetch/axios calls

## Root Cause Analysis

The server likely has a default timeout (probably 5 minutes) that's too short for complex Claude operations. Need to either:
1. Remove artificial timeouts entirely
2. Make timeout configurable and set very high (30+ minutes)
3. Only timeout on actual process death, not time elapsed

## Solution Approach

### 1. Remove Artificial Timeouts
- Let Claude CLI manage its own timeouts
- Server should wait indefinitely for Claude response
- Only timeout on actual connection loss

### 2. Progress Indication
- Send periodic "still processing" updates to client
- Use Claude's streaming output as proof of life
- Don't assume timeout based on time alone

### 3. Configuration Options
- Add CLAUDE_TIMEOUT env var (default: none or very high)
- Allow per-request timeout override
- Document timeout behavior clearly

## Testing Requirements

### Manual Testing Steps
1. Send request that takes 15+ minutes
2. Verify no timeout occurs
3. Test with various long-running operations
4. Verify real timeouts still detected (kill Claude process)

### Test Scenarios
- [ ] 20-minute operation completes successfully
- [ ] No false timeout alerts during processing
- [ ] Real process crashes still detected
- [ ] Progress indicators work if implemented

## Technical Notes

- Current timeout might be in Promise.race() or setTimeout
- May need to differentiate between connection timeout and processing timeout
- Consider WebSocket ping/pong for connection health
- Don't confuse network timeout with processing timeout

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22