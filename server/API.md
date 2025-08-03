# Claude Companion Server API Documentation

## Overview

The Claude Companion Server provides a WebSocket and REST API for integrating Claude CLI with mobile and web applications. All API endpoints require authentication unless specified otherwise.

## Authentication

### Auth Token
- Set via environment variable: `AUTH_TOKEN`
- Pass in WebSocket connection: `ws://localhost:3001/ws?token=YOUR_TOKEN`
- Pass in REST headers: `Authorization: Bearer YOUR_TOKEN`

## REST API Endpoints

### Health Check

```
GET /health
```

No authentication required. Returns server health status.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "claudeCodeAvailable": true,
  "timestamp": "2024-01-03T14:50:00.000Z"
}
```

### Session Management

#### List All Sessions
```
GET /api/sessions
```

Returns all active sessions across all projects.

**Response:**
```json
{
  "sessions": [
    {
      "sessionId": "uuid-here",
      "workingDirectory": "/path/to/project",
      "isActive": true,
      "createdAt": 1234567890000,
      "lastActivity": 1234567890000
    }
  ]
}
```

#### Get Session Status
```
GET /api/sessions/:sessionId
```

Returns detailed information about a specific session.

**Response:**
```json
{
  "sessionId": "uuid-here",
  "workingDirectory": "/path/to/project",
  "isActive": true,
  "isProcessing": false,
  "createdAt": 1234567890000,
  "lastActivity": 1234567890000,
  "conversationStarted": true
}
```

#### Continue Session (iOS)
```
POST /api/sessions/continue
```

Allows iOS clients to reconnect to an existing session after app backgrounding.

**Request Body:**
```json
{
  "sessionId": "existing-session-id",
  "workingDirectory": "/path/to/project"
}
```

**Response:**
```json
{
  "success": true,
  "sessionId": "existing-session-id",
  "message": "Session continued",
  "workingDirectory": "/path/to/project"
}
```

### Project Management

#### List Projects
```
GET /api/projects
```

Lists available projects in the configured root directory.

**Response:**
```json
{
  "projects": [
    {
      "name": "my-project",
      "path": "/Users/name/Projects/my-project",
      "hasSession": true,
      "sessionId": "uuid-here"
    }
  ]
}
```

#### Start Project Session
```
POST /api/projects/:name/start
```

Starts a new Claude session for a project.

**Request Body:**
```json
{
  "initialPrompt": "Help me understand this codebase",
  "skipPermissions": false
}
```

**Response:**
```json
{
  "sessionId": "new-session-id",
  "success": true,
  "message": "Session ready for commands",
  "reused": false
}
```

### Claude Status

#### Get Claude Status
```
GET /api/claude/status
```

Returns Claude CLI availability and version information.

**Response:**
```json
{
  "available": true,
  "version": "0.1.0",
  "executable": "/usr/local/bin/claude"
}
```

#### Test Claude
```
POST /api/claude/test
```

Tests Claude CLI with a simple prompt.

**Request Body:**
```json
{
  "prompt": "Hello, Claude!"
}
```

### Telemetry

#### Get Metrics
```
GET /api/telemetry
```

Returns comprehensive telemetry metrics.

**Response:**
```json
{
  "timestamp": 1234567890000,
  "websocket": {
    "activeConnections": 5,
    "totalMessages": {
      "sent": 1000,
      "received": 950,
      "failed": 10
    },
    "reconnections": 15
  },
  "sessions": {
    "created": 50,
    "resumed": 20,
    "expired": 5,
    "active": 10,
    "duplicatesPrevented": 15
  },
  "messages": {
    "queued": 100,
    "delivered": 95,
    "expired": 5,
    "filtered": 10
  },
  "performance": {
    "avgMessageProcessingTime": 25.5,
    "avgQueueDeliveryTime": 150.2
  }
}
```

#### Get Connection Metrics
```
GET /api/telemetry/connection/:clientId
```

Returns metrics for a specific WebSocket connection.

#### Reset Metrics
```
POST /api/telemetry/reset
```

Resets all telemetry metrics (admin only).

### Push Notifications

#### Get Push Notification Stats
```
GET /api/push-notifications/stats
```

Returns push notification statistics.

**Response:**
```json
{
  "configuredDevices": 10,
  "badTokens": 2,
  "isConfigured": true,
  "retryingTokens": 1
}
```

#### Send Test Notification
```
POST /api/push-notifications/test
```

Sends a test push notification to a specific client.

**Request Body:**
```json
{
  "clientId": "client-id",
  "message": "Test notification message"
}
```

#### Clear Bad Tokens
```
DELETE /api/push-notifications/bad-tokens
```

Clears the bad device tokens cache.

## WebSocket API

### Connection

Connect to the WebSocket server:
```
ws://localhost:3001/ws?token=YOUR_TOKEN
```

Include the `x-device-id` header for reconnection support.

### Message Format

All WebSocket messages follow this format:

```json
{
  "type": "messageType",
  "timestamp": "ISO-8601-timestamp",
  "requestId": "unique-request-id",
  "data": {
    // Message-specific data
  }
}
```

### Client-to-Server Messages

#### Send Command
```json
{
  "type": "sendCommand",
  "requestId": "unique-id",
  "data": {
    "sessionId": "session-id",
    "prompt": "Your command to Claude"
  }
}
```

#### Subscribe to Events
```json
{
  "type": "subscribe",
  "requestId": "unique-id",
  "data": {
    "events": ["assistantMessage", "streamData", "sessionStatus"]
  }
}
```

#### Register Device for Push Notifications
```json
{
  "type": "registerDevice",
  "requestId": "unique-id",
  "data": {
    "deviceToken": "apns-device-token",
    "deviceInfo": "ios"
  }
}
```

#### Mark Session as Backgrounded/Foregrounded
```json
{
  "type": "sessionBackgrounded",
  "requestId": "unique-id",
  "data": {
    "sessionId": "session-id"
  }
}
```

```json
{
  "type": "sessionForegrounded",
  "requestId": "unique-id",
  "data": {
    "sessionId": "session-id"
  }
}
```

### Server-to-Client Messages

#### Welcome Message
Sent immediately after connection:
```json
{
  "type": "welcome",
  "timestamp": "ISO-8601-timestamp",
  "data": {
    "clientId": "your-client-id",
    "serverVersion": "1.0.0",
    "claudeCodeVersion": "0.1.0",
    "capabilities": ["chat", "streaming", "permissions", "file-operations", "session-management"],
    "maxSessions": 5
  }
}
```

#### Assistant Message
Claude's response:
```json
{
  "type": "assistantMessage",
  "timestamp": "ISO-8601-timestamp",
  "data": {
    "sessionId": "session-id",
    "content": "Claude's response here",
    "isStreaming": false
  }
}
```

#### Stream Data
Streaming response chunks:
```json
{
  "type": "streamData",
  "timestamp": "ISO-8601-timestamp",
  "data": {
    "sessionId": "session-id",
    "chunk": {
      "type": "content",
      "data": {
        "content": "Partial response..."
      }
    }
  }
}
```

#### Error Message
```json
{
  "type": "error",
  "timestamp": "ISO-8601-timestamp",
  "data": {
    "sessionId": "session-id",
    "error": "Error description",
    "code": "ERROR_CODE",
    "details": {}
  }
}
```

## Error Codes

- `INVALID_SESSION` - Session ID is invalid or expired
- `SESSION_LIMIT` - Maximum session limit reached
- `PERMISSION_DENIED` - Operation not permitted
- `CLAUDE_UNAVAILABLE` - Claude CLI is not available
- `INVALID_REQUEST` - Malformed request
- `AUTHENTICATION_REQUIRED` - Missing or invalid auth token

## Rate Limits

- WebSocket connections: 100 per IP
- Messages per second: 10 per client
- Sessions per client: 5 concurrent
- Push notifications: 100 per hour per device

## Best Practices

1. **Session Management**
   - Reuse sessions for the same project
   - Close sessions when done
   - Use session continuation for mobile apps

2. **WebSocket Connection**
   - Send periodic ping messages to keep connection alive
   - Handle reconnection with exponential backoff
   - Include device ID for automatic session restoration

3. **Message Handling**
   - Filter empty stream chunks on client side
   - Handle message queue delivery metadata
   - Implement proper error handling for all message types

4. **Push Notifications**
   - Register device token on app launch
   - Handle token updates and refreshes
   - Implement proper badge management

## Changelog

### v1.0.0 (Current)
- Initial release with full feature set
- Session deduplication
- WebSocket reconnection support
- Push notification improvements
- Comprehensive telemetry
- Message queue reliability