# Issue #14: Message Processing Fails Silently with Large Messages or Special Characters

**Priority**: High  
**Component**: Server - Message Processing / Error Handling  
**Beta Blocker**: Yes (Silent failures are unacceptable UX)  
**Discovered**: 2025-08-21
**Status**: Awaiting error logs

## Problem Description

When certain messages are sent, the server appears to fail processing but no error is returned to the iOS app, leaving users with no feedback about what went wrong. This may be related to message size or special characters causing silent failures in the processing pipeline.

## Investigation Areas

1. Check server message size limits and buffer handling for large messages
2. Investigate special character encoding issues (Unicode, emojis, escape sequences)
3. Review error handling pipeline - ensure ALL errors propagate back to client
4. Add comprehensive error boundaries around message processing
5. Implement proper error responses via APNS when processing fails
6. Add detailed logging for message processing failures
7. Check if Claude CLI has message size limits that aren't being handled
8. Review JSON parsing/stringification for edge cases
9. Ensure WebSocket and HTTP error responses reach the iOS app
10. Add timeout handling with proper error messages

## Expected Behavior

When message processing fails for any reason, the iOS app should receive a clear error message explaining what went wrong (e.g., "Message too large", "Invalid characters", "Processing timeout"). Never fail silently.

## Files to Investigate

- `server/src/services/aicli-message-handler.js` (message processing pipeline)
- `server/src/services/push-notification.js` (error response delivery)
- `server/src/middleware/error-handler.js` (global error handling)
- `server/src/services/websocket-message-handlers.js` (WebSocket error paths)
- `server/src/utils/validation.js` (input validation and sanitization)
- `ios/Sources/AICLICompanion/Services/WebSocketService.swift` (client error handling)

## Error Scenarios to Test

- Very large messages (>100KB)
- Messages with special Unicode characters
- Messages with unescaped quotes or backslashes
- Rapid successive messages that might overflow buffers
- Messages sent during server restart/reload
- Network interruptions during message processing

## Required Improvements

- Add message size validation with clear limits
- Implement proper character encoding/escaping
- Add error telemetry to track failure patterns
- Create error recovery mechanisms
- Add user-facing error messages for all failure modes

## Status

**Current Status**: COMPLETED ✅  
**Last Updated**: 2025-08-21

## Implemented Solutions

### 1. Message Size Validation (✅ Complete)
- Added `validateMessageContent()` method in ValidationUtils
- Validates message size in bytes (not just character count)
- Default limit: 100KB (configurable via MAX_MESSAGE_SIZE env var)
- Warning threshold: 50KB (configurable via WARN_MESSAGE_SIZE env var)
- Returns detailed validation results with errors and warnings

### 2. Character Encoding Validation (✅ Complete)
- Detects and handles invalid UTF-8 sequences
- Removes null bytes automatically with warning
- Validates control characters and special characters
- Warns about unescaped quotes/backslashes for JSON safety
- Properly handles Unicode and emoji characters

### 3. Enhanced Error Boundaries (✅ Complete)
- Added try-catch blocks in message processing pipeline
- Error boundaries in AICLIMessageHandler.processResponse()
- Safe handling of malformed assistant responses
- Graceful degradation when content format is unexpected

### 4. Comprehensive Error Logging (✅ Complete)
- Enhanced error middleware with detailed logging
- Request IDs for error tracking
- Stack traces in development mode
- Error categorization by type (timeout, connection, memory, etc.)

### 5. APNS Error Delivery (✅ Complete)
- Enhanced sendErrorNotification() with error types
- User-friendly error messages based on error type
- Visual indicators (emojis) for different error categories
- Technical details included in development mode
- High priority delivery for error notifications

### 6. Timeout Handling (✅ Complete)
- Added configurable timeout for Claude processing (default 5 minutes)
- Uses Promise.race() for timeout enforcement
- Proper cleanup of timeout handles
- Specific timeout error messages to users

### 7. Error Types Handled (✅ Complete)
- **TIMEOUT**: Processing takes too long
- **CONNECTION_ERROR**: Can't connect to Claude
- **MEMORY_ERROR**: Server out of memory
- **RATE_LIMIT**: Too many requests
- **SERVICE_NOT_FOUND**: Claude CLI not found
- **VALIDATION_ERROR**: Invalid message content
- **PROCESSING_ERROR**: General processing failures

### 8. Test Suite Created (✅ Complete)
- Created test-error-handling.js for validation testing
- Tests large messages, special characters, Unicode
- Validates error responses and proper rejection
- Ensures graceful handling of edge cases

## Files Modified

1. `/server/src/utils/validation.js` - Added validateMessageContent() method
2. `/server/src/routes/chat.js` - Added message validation and timeout handling
3. `/server/src/services/push-notification.js` - Enhanced error notification delivery
4. `/server/src/middleware/error.js` - Comprehensive error handling middleware
5. `/server/src/services/aicli-message-handler.js` - Added error boundaries
6. `/server/test-error-handling.js` - Test suite for validation

## Verification

Run the test suite to verify all error scenarios are handled:
```bash
cd server
node test-error-handling.js
```

Server logs will now show detailed error information including:
- Request IDs for tracking
- Error types and categories
- User-friendly messages sent to iOS app
- Technical details for debugging