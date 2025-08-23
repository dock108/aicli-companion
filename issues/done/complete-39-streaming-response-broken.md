# Issue #39: Streaming Responses Broken After Fallback Message Changes

**Priority**: Critical  
**Component**: Server - Message Delivery  
**Beta Blocker**: Yes (core functionality broken)  
**Discovered**: 2025-08-23  
**Status**: In Progress  

## Problem Description

After implementing fallback messages for Issue #36 (long-running APNS failures), streaming responses are completely broken. The server immediately returns empty responses or sends fallback messages instead of waiting for Claude's actual response to stream in.

## Root Cause Analysis

### What Broke It

When we added fallback message handling in Issue #36:
```javascript
// If content is still empty after all extraction attempts, send completion notification
if (!content || content.trim().length === 0) {
  const fallbackContent = '✅ Operation completed. Check the app for details.';
  // Send fallback immediately...
}
```

This code doesn't account for the fact that **streaming responses ALWAYS return empty initially** because:
1. `sendPrompt()` with `streaming: true` returns immediately
2. The actual content comes through stream chunks over time
3. The process runner accumulates text and only returns it when streaming completes

### Timeline of Breaking Changes

1. **Original Working State**: Streaming responses would wait for completion before sending
2. **Issue #36 Fix**: Added fallback for empty responses to handle long-running operations
3. **Broken State**: Fallback triggers immediately for ALL empty responses, including normal streaming
4. **Attempted Fix**: Tried to skip fallback for streaming, but broke the response flow entirely

## Current Symptoms

- User sends "Hello" to Claude
- Server immediately responds with empty content or fallback message
- Claude's actual response never reaches the user
- iOS app shows "APNS delivery failed" or receives fallback message

## Solution Approach

### The Fix

1. **Properly detect streaming responses**: Check `result?.source === 'streaming'` or `result?.streaming === true`
2. **Extract accumulated text correctly**: Streaming returns accumulated text as `result.result` not `result.accumulatedText`
3. **Only send content when available**: Don't send empty responses or fallbacks for streaming
4. **Let streaming complete naturally**: The process runner will accumulate and return the full response

### Key Insight

The process runner returns streaming results with:
```javascript
resolve({
  result: accumulatedText.trim(), // The actual content
  sessionId: foundSessionId,
  responses,
  success: true,
  source: 'accumulated_text', // Flag indicating this came from accumulation
});
```

## Implementation

### 1. Fix Content Extraction (chat.js)

```javascript
// After getting result from sendPrompt...

// Primary content extraction
let content = '';
if (result?.response?.result) {
  content = result.response.result;
} else if (result?.result) {
  content = result.result;
}

// For streaming responses, the content is in result.result
if (!content && result?.source === 'accumulated_text' && result?.result) {
  content = result.result;
}

// Only proceed if we have content
if (content && content.trim().length > 0) {
  // Send via APNS...
} else {
  // Don't send fallback for streaming responses
  if (result?.source === 'streaming' || result?.source === 'accumulated_text') {
    // Normal for initial streaming response
    logger.info('Streaming response pending or empty', { requestId });
  } else {
    // Only log for non-streaming empty responses
    logger.warn('Non-streaming response was empty', { requestId });
  }
  
  // Return success without sending anything
  return res.json({
    success: true,
    sessionId: claudeSessionId,
    message: 'Processing',
    deliveryMethod: 'apns',
  });
}
```

### 2. Ensure Process Runner Returns Content

The process runner should already be accumulating text correctly from stream chunks. We just need to ensure it's being returned properly.

## Testing Requirements

1. Send simple message "Hello" - should get Claude's response
2. Send complex message requiring tools - should get full response
3. Send message that triggers timeout - should get stall alert (not instant fallback)
4. Kill operation mid-stream - should terminate cleanly

## Related Issues

- **Issue #36**: Long-running APNS failures - introduced the regression
- **Issue #35**: Claude responses slow/missing - original timeout handling
- **Issue #30**: Stall detection - should handle truly stalled operations

## Status

**Current Status**: Fixed  
**Last Updated**: 2025-08-23  
**Fix Applied**: Updated chat.js to properly extract accumulated text from streaming responses

### What Was Fixed
1. Check for `result.result` when `source === 'accumulated_text'` or `source === 'streaming'`
2. Extract accumulated text before checking if content is empty
3. Never send fallback messages for streaming responses
4. Let stall detection handle truly stuck operations
5. Fixed missing `aicliService` reference in kill endpoint