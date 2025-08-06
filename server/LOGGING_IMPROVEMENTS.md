# Logging Improvements Summary

## Overview
Implemented a structured logging system to replace 330+ console.log statements across the server, making it easier to debug parallel session issues.

## Logger Features

### Logger Utility (`src/utils/logger.js`)
- **Log Levels**: debug, info, warn, error (controlled by LOG_LEVEL env var)
- **Session Context**: Automatically includes sessionId in all logs
- **Request Tracking**: Includes requestId for tracing message flow
- **Child Loggers**: Create loggers with default context
- **Smart Helpers**: 
  - `logger.stream()` - Reduces stream operation verbosity
  - `logger.chunk()` - Only logs every 10th chunk or final chunks
  - `logger.session()` - Standardized session operation logging

### Log Format
```
2024-01-15T10:30:45.123Z 📘 [INFO] [ModuleName] [Session: abc12345] [Req: def67890] Message content {"extra": "context"}
```

## Files Refactored

### ✅ websocket-message-handlers.js
- **Before**: 51 console.log statements
- **After**: Structured logging with session context
- **Key Improvements**:
  - All handlers use sessionLogger with automatic session context
  - Reduced verbosity for routine operations
  - Clear error context for debugging

### ✅ aicli-process-runner.js  
- **Before**: 46 console.log statements (worst offender!)
- **After**: Clean, contextual logging
- **Key Improvements**:
  - Replaced 15+ lines of verbose startup logs with 2 structured logs
  - Stream chunks only log at debug level
  - Process monitoring logs include session context

## Usage Examples

### Set Log Level
```bash
# Production (less verbose)
LOG_LEVEL=info npm start

# Development (see everything)
LOG_LEVEL=debug npm start
```

### Filtering Logs
```bash
# See only logs for a specific session
npm start | grep "Session: abc12345"

# See only errors
LOG_LEVEL=error npm start

# See logs for specific module
npm start | grep "[AICLI]"
```

## Benefits for Parallel Sessions

1. **Session Isolation**: Every log includes session ID, making it easy to filter
2. **Reduced Noise**: Stream chunks and routine operations at debug level
3. **Request Tracking**: Follow a message through the system with request ID
4. **Performance**: Only compute/format logs when needed (level checking)

## Next Steps

- [ ] Refactor aicli-session-manager.js (38 console.logs)
- [ ] Refactor remaining high-traffic services
- [ ] Add session debugging endpoint
- [ ] Create iOS Logger utility
- [ ] Add log aggregation/filtering tools