# Issue #3: Message Queue Management Per Chat Session

**Priority**: High  
**Component**: Server - Message Processing  
**Beta Blocker**: No  
**Discovered**: 2025-08-19  
**Status**: New  

## Problem Description

Implement a message queue system that handles multiple messages per chat session. Currently, rapid successive messages may cause race conditions or lost messages.

## Investigation Areas

1. Create a queue management system that maintains message order per session
2. Ensure messages are processed sequentially within each session
3. Allow parallel processing across different sessions
4. Add queue status visibility to track pending messages
5. Implement proper error handling for queue overflow scenarios
6. Add metrics for queue depth and processing time
7. **Priority Queue Support for Auto-Reply System**:
   - Messages that should queue BEFORE auto-replies (user interventions, stop commands)
   - Messages that should queue AFTER auto-replies (continuation messages, follow-ups)
   - Configuration for priority levels and queue positioning

## Expected Behavior

Users should be able to send multiple messages quickly without losing any, and each message should be processed in the order sent while maintaining session context.

**Priority Queue Behavior**:
- When auto-reply is active and generating responses, high-priority user messages (like "stop") should immediately queue before the next auto-reply
- Low-priority messages (like auto-generated follow-ups) should queue after all pending auto-replies
- The system should maintain proper ordering within each priority level

## Files to Investigate

- `server/src/services/message-queue.js` (to be created)
- `server/src/services/websocket-message-handlers.js`
- `server/src/services/aicli-session-manager.js`
- `ios/Sources/AICLICompanion/Services/MessageQueueService.swift` (to be created)

## Solution Implemented

### 1. Queue Architecture
- Per-session message queues
- Sequential processing within sessions
- Parallel processing across sessions

### 2. Priority Queue System (⏳ In Progress)
- **High Priority (Queue Before Auto-Replies)**:
  - User manual interventions
  - Stop/cancel commands
  - Emergency overrides
  - Configuration changes
- **Normal Priority (Standard Queue)**:
  - Regular user messages
  - Standard commands
- **Low Priority (Queue After Auto-Replies)**:
  - Auto-generated continuation messages
  - Follow-up queries from auto-reply system
  - Cleanup/maintenance messages

### 3. Error Handling
- Queue overflow protection
- Dead letter queue for failed messages
- Retry mechanism with backoff

### 4. Configuration Structure
```javascript
{
  "messageQueue": {
    "priorities": {
      "HIGH": 0,    // Process immediately, before auto-replies
      "NORMAL": 1,  // Standard processing order
      "LOW": 2      // Process after auto-replies
    },
    "autoReplyConfig": {
      "allowInterruption": true,  // High priority can interrupt
      "queuePosition": "AFTER_NORMAL" // Where auto-replies sit
    }
  }
}
```

## Testing Requirements

### Manual Testing Steps
1. Send multiple messages rapidly
2. Verify order preservation
3. Test with multiple concurrent sessions
4. Monitor queue metrics

### Test Scenarios
- [ ] Rapid message sending
- [ ] Multiple session handling
- [ ] Queue overflow behavior
- [ ] Error recovery
- [ ] High priority message interruption of auto-replies
- [ ] Low priority message queuing after auto-replies
- [ ] Priority escalation for stop commands
- [ ] Mixed priority message ordering

## Status

**Current Status**: Planning - Priority Queue Design  
**Last Updated**: 2025-08-29

### Planning Notes

**Integration with Issue #4 (Auto-Reply System)**:
- Priority queue is essential for auto-reply control
- High priority messages can interrupt auto-reply loops
- Low priority allows auto-replies to batch follow-ups
- Provides foundation for intelligent message flow control