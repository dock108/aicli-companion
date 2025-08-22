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

The server had multiple hardcoded timeouts that were too short for complex Claude operations:
1. **chat.js**: 5-minute timeout (300000ms) for Claude processing
2. **aicli-process-runner.js**: 2-minute timeout (120000ms) per message interaction

These timeouts would interrupt legitimate long-running Claude operations that can take 15-20+ minutes.

## Solution Implemented ✅ (UPDATED)

### 1. ~~Increased Timeout Values~~ REMOVED ALL TIMEOUTS
**File: `/server/src/routes/chat.js`**
- ~~Changed timeout to 30 minutes~~ **REMOVED timeout entirely**
- No more `PROCESSING_TIMEOUT` or timeout promises
- Claude can run indefinitely

**File: `/server/src/services/aicli-process-runner.js`**
- ~~Changed timeout to 30 minutes~~ **REMOVED timeout handler**
- No setTimeout calls for message processing
- Claude responses wait indefinitely

### 2. Configuration Removed
**File: `/server/.env.example`**
- ~~Added `CLAUDE_PROCESSING_TIMEOUT`~~ **REMOVED timeout config**
- Added comment: "NO TIMEOUT - Claude operations run as long as needed"

### 3. Final Implementation
```javascript
// Before (chat.js)
const PROCESSING_TIMEOUT = parseInt(process.env.CLAUDE_PROCESSING_TIMEOUT || '1800000');
const timeoutPromise = new Promise(...);
const result = await Promise.race([resultPromise, timeoutPromise]);

// After - NO TIMEOUT
const result = await aicliService.sendPrompt(...);
```

```javascript
// Before (aicli-process-runner.js)
setTimeout(timeoutHandler, 1800000);

// After - NO TIMEOUT
// Activity monitoring will detect stalls (Issue #28)
```

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

**Current Status**: RESOLVED ✅  
**Last Updated**: 2025-08-22 (Updated to remove timeouts entirely)  
**Resolved**: 2025-08-22

## Result

**UPDATE**: Completely removed all artificial timeouts. Claude operations can now run indefinitely without any server-imposed time limits. Timeout detection will only come from activity monitoring (Issue #28) which can detect when Claude has actually stalled without sending data, rather than using arbitrary time limits.

## Related Issues

- **Issue #28**: Activity monitoring will detect actual stalls
- **Issue #30**: Handle cases where Claude stops without responding