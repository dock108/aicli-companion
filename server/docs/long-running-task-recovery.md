# Long-Running Task Recovery

This document explains how the server handles long-running tasks when iOS clients disconnect due to background limitations.

## Problem

When the iOS app goes to background, the WebSocket connection disconnects. If a long-running task (> 5 minutes) is running on the server, by the time it completes, there are no connected clients to receive the results.

## Solution

We've implemented a three-part solution:

### 1. Message Queue Service

- **Location**: `src/services/message-queue.js`
- **Purpose**: Stores messages for disconnected clients
- **Features**:
  - In-memory storage (can be upgraded to Redis)
  - 24-hour TTL for messages
  - Automatic cleanup of expired messages
  - Per-client delivery tracking

### 2. Push Notifications

- **Enhanced**: `src/services/push-notification.js`
- **Features**:
  - Sends notification when long-running task completes
  - Different notification for success vs failure
  - Deep linking to reconnect to specific session
  - Custom sounds and categories

### 3. Automatic Message Delivery

When a client reconnects:
1. Server checks for queued messages
2. Delivers any pending messages for active sessions
3. Marks messages as delivered

## How It Works

### During Task Execution

1. Server detects long-running task (> 5 minutes)
2. Sends immediate status to client
3. Runs task in background
4. Sends periodic status updates

### When Client Disconnects

1. WebSocket detects disconnection
2. Any new messages are queued instead of lost
3. Queue stores messages with session ID

### On Task Completion

1. Server completes the task
2. If no clients connected, messages are queued
3. Push notification sent to registered devices
4. Results stored for later delivery

### When Client Reconnects

1. Client establishes WebSocket connection
2. Server checks for queued messages
3. Delivers all pending messages
4. Client receives results seamlessly

## Configuration

### Environment Variables

- `APNS_CERT_PATH`: Path to Apple Push Notification certificate
- `APNS_KEY_PATH`: Path to Apple Push Notification key
- `APNS_PASSPHRASE`: Certificate passphrase (optional)
- `APNS_BUNDLE_ID`: iOS app bundle identifier

### Message Queue Settings

- Default TTL: 24 hours
- Cleanup interval: 1 hour
- Storage: In-memory (upgradeable to Redis)

## Testing

Run the message queue tests:
```bash
npm test -- src/test/services/message-queue.test.js
```

## Future Enhancements

1. **Redis Storage**: Replace in-memory storage with Redis for persistence
2. **Message Priority**: Add priority levels for different message types
3. **Compression**: Compress large messages to save memory
4. **Analytics**: Track delivery rates and queue performance
5. **Retry Logic**: Implement exponential backoff for failed deliveries