# Claude Companion WebSocket Protocol

## Overview

The Claude Companion WebSocket protocol enables real-time communication between the iOS mobile app and the companion server. This protocol supports bidirectional messaging for Claude Code interactions, session management, and real-time streaming responses.

## Connection

### WebSocket URL
```
ws://server-address:port/ws?token=AUTH_TOKEN
```

### Authentication
- **Query Parameter**: `?token=AUTH_TOKEN` for initial auth
- **Header Alternative**: `Authorization: Bearer AUTH_TOKEN`
- Connection rejected with code 1008 if authentication fails

### Connection Flow
1. Client establishes WebSocket connection with auth token
2. Server validates token and sends welcome message
3. Client can begin sending requests
4. Server maintains session state per connection

## Message Format

All messages are JSON objects with the following base structure:

```json
{
  "type": "message_type",
  "requestId": "unique-request-id",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": { ... }
}
```

### Common Fields
- **type** (string): Message type identifier
- **requestId** (string): Unique identifier for request/response correlation
- **timestamp** (string): ISO 8601 timestamp
- **data** (object): Message-specific payload

## Client → Server Messages

### 1. Ask (One-time Query)
Send a single prompt to Claude Code and get a complete response.

```json
{
  "type": "ask",
  "requestId": "req_12345",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "prompt": "List files in current directory",
    "workingDirectory": "/Users/user/project",
    "options": {
      "format": "json",
      "timeout": 30000
    }
  }
}
```

### 2. Stream Start
Begin a streaming conversation session.

```json
{
  "type": "streamStart",
  "requestId": "req_12346",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "prompt": "Help me debug this code",
    "workingDirectory": "/Users/user/project",
    "options": {
      "sessionName": "Debug Session",
      "preserveContext": true
    }
  }
}
```

### 3. Stream Send
Send a message to an existing streaming session.

```json
{
  "type": "streamSend",
  "requestId": "req_12347",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "sessionId": "session_uuid",
    "prompt": "Continue with the next step"
  }
}
```

### 4. Permission Response
Respond to a permission prompt from Claude Code.

```json
{
  "type": "permission",
  "requestId": "req_12348",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "sessionId": "session_uuid",
    "response": "y",
    "remember": false
  }
}
```

### 5. Stream Close
Close an active streaming session.

```json
{
  "type": "streamClose",
  "requestId": "req_12349",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "sessionId": "session_uuid",
    "reason": "user_requested"
  }
}
```

### 6. Ping
Heartbeat message to maintain connection.

```json
{
  "type": "ping",
  "requestId": "req_12350",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {}
}
```

### 7. Subscribe
Subscribe to specific events or session updates.

```json
{
  "type": "subscribe",
  "requestId": "req_12351",
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "events": ["sessionUpdates", "serverStatus"],
    "sessionIds": ["session_uuid"]
  }
}
```

## Server → Client Messages

### 1. Welcome
Sent immediately after successful connection.

```json
{
  "type": "welcome",
  "requestId": null,
  "timestamp": "2025-07-18T10:30:00Z",
  "data": {
    "clientId": "client_uuid",
    "serverVersion": "1.0.0",
    "claudeCodeVersion": "1.0.55",
    "capabilities": ["streaming", "permissions", "multiSession"],
    "maxSessions": 5
  }
}
```

### 2. Ask Response
Complete response to a one-time query.

```json
{
  "type": "askResponse",
  "requestId": "req_12345",
  "timestamp": "2025-07-18T10:30:01Z",
  "data": {
    "success": true,
    "response": {
      "type": "result",
      "subtype": "success",
      "result": "Response content here",
      "sessionId": "session_uuid",
      "duration": 2500,
      "cost": 0.05,
      "usage": {
        "inputTokens": 10,
        "outputTokens": 50
      }
    }
  }
}
```

### 3. Stream Started
Confirmation that streaming session was created.

```json
{
  "type": "streamStarted",
  "requestId": "req_12346",
  "timestamp": "2025-07-18T10:30:01Z",
  "data": {
    "sessionId": "session_uuid",
    "sessionName": "Debug Session",
    "workingDirectory": "/Users/user/project"
  }
}
```

### 4. Stream Data
Real-time streaming data from Claude Code.

```json
{
  "type": "streamData",
  "requestId": null,
  "timestamp": "2025-07-18T10:30:02Z",
  "data": {
    "sessionId": "session_uuid",
    "streamType": "assistant_message",
    "content": {
      "type": "text",
      "text": "I'll help you debug the code..."
    },
    "isComplete": false
  }
}
```

### 5. Stream Tool Use
Claude Code tool usage during streaming.

```json
{
  "type": "streamToolUse",
  "requestId": null,
  "timestamp": "2025-07-18T10:30:03Z",
  "data": {
    "sessionId": "session_uuid",
    "toolName": "Read",
    "toolInput": {
      "file_path": "/Users/user/project/app.js"
    },
    "status": "executing"
  }
}
```

### 6. Permission Request
Claude Code requesting permission from user.

```json
{
  "type": "permissionRequest",
  "requestId": null,
  "timestamp": "2025-07-18T10:30:04Z",
  "data": {
    "sessionId": "session_uuid",
    "prompt": "Allow Claude to edit app.js?",
    "options": ["y", "n"],
    "default": "n",
    "timeout": 30000
  }
}
```

### 7. Stream Complete
Streaming response completed.

```json
{
  "type": "streamComplete",
  "requestId": null,
  "timestamp": "2025-07-18T10:30:05Z",
  "data": {
    "sessionId": "session_uuid",
    "finalResult": "Debug analysis complete",
    "duration": 5000,
    "cost": 0.12,
    "usage": {
      "inputTokens": 25,
      "outputTokens": 120
    }
  }
}
```

### 8. Error
Error response for any failed operation.

```json
{
  "type": "error",
  "requestId": "req_12345",
  "timestamp": "2025-07-18T10:30:01Z",
  "data": {
    "code": "CLAUDE_UNAVAILABLE",
    "message": "Claude Code CLI not found",
    "details": {
      "originalError": "spawn claude ENOENT",
      "suggestion": "Ensure Claude Code is installed and in PATH"
    }
  }
}
```

### 9. Session Status
Status updates for active sessions.

```json
{
  "type": "sessionStatus",
  "requestId": null,
  "timestamp": "2025-07-18T10:30:01Z",
  "data": {
    "sessionId": "session_uuid",
    "status": "active",
    "lastActivity": "2025-07-18T10:29:45Z",
    "messageCount": 5,
    "totalCost": 0.25
  }
}
```

### 10. Pong
Response to ping message.

```json
{
  "type": "pong",
  "requestId": "req_12350",
  "timestamp": "2025-07-18T10:30:01Z",
  "data": {
    "serverTime": "2025-07-18T10:30:01Z"
  }
}
```

## Error Codes

### Connection Errors
- **1008**: Authentication failed
- **1011**: Server error
- **1012**: Server restarting

### Application Error Codes
- **CLAUDE_UNAVAILABLE**: Claude Code CLI not accessible
- **SESSION_NOT_FOUND**: Requested session doesn't exist
- **INVALID_REQUEST**: Malformed request data
- **RATE_LIMITED**: Too many requests
- **PERMISSION_DENIED**: Insufficient permissions
- **TIMEOUT**: Operation timed out
- **INTERNAL_ERROR**: Unexpected server error

## Session Management

### Session Lifecycle
1. **Creation**: `streamStart` creates new session
2. **Active**: Session accepts `streamSend` messages
3. **Idle**: No activity for configured timeout
4. **Closed**: Explicitly closed or timed out
5. **Error**: Session terminated due to error

### Session Limits
- **Free Tier**: 1 concurrent session
- **Premium**: 5 concurrent sessions
- **Timeout**: 30 minutes of inactivity
- **Maximum Duration**: 24 hours

## Real-time Features

### Streaming Response Types
- **Text Content**: Incremental text updates
- **Tool Usage**: Real-time tool execution status
- **Permission Prompts**: Interactive permission requests
- **Progress Updates**: Long-running operation status
- **Error States**: Real-time error notifications

### Message Ordering
- Each session maintains message sequence numbers
- Client should handle out-of-order delivery
- Server guarantees eventual consistency

## Security Considerations

### Authentication
- Token-based authentication required
- Tokens should be rotated regularly
- Failed auth attempts logged and rate limited

### Data Privacy
- No message content logged on server
- Session data purged after closure
- All communication encrypted in transit

### Rate Limiting
- 100 messages per minute per client
- 10 new sessions per hour per client
- Automatic backoff for rate exceeded

## Implementation Guidelines

### Client Implementation
- Implement exponential backoff for reconnection
- Handle graceful degradation for connection loss
- Queue messages during reconnection
- Implement proper error handling for all message types

### Server Implementation
- Validate all incoming messages
- Implement proper session isolation
- Handle Claude Code process lifecycle
- Provide detailed error messages for debugging

## Examples

### Complete Chat Flow
1. Client connects and receives welcome
2. Client sends `streamStart` with initial prompt
3. Server responds with `streamStarted`
4. Server streams `streamData` messages with responses
5. Claude requests permission via `permissionRequest`
6. Client responds with `permission` message
7. Server continues streaming until complete
8. Server sends `streamComplete` with final results

### Error Recovery
1. Connection lost during streaming
2. Client reconnects with same auth token
3. Client queries session status
4. Server provides current session state
5. Client resumes from last known state

This protocol provides a robust foundation for real-time communication between the mobile app and companion server while maintaining security and providing excellent user experience.