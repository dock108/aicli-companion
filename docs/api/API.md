# AICLI Companion API Documentation

## Overview

The AICLI Companion Server provides a RESTful API for iOS clients to interact with AI assistants through Claude Code CLI. The server uses HTTP endpoints with Apple Push Notification Service (APNS) for message delivery.

**Base URL**: `http://localhost:3001`

## Authentication

All API endpoints (except `/health`) require authentication using a Bearer token.

### Authentication Methods

1. **Authorization Header** (Recommended)
```http
Authorization: Bearer YOUR_AUTH_TOKEN
```

2. **Query Parameter** (For WebSocket connections)
```
?token=YOUR_AUTH_TOKEN
```

The auth token is configured via the `AUTH_TOKEN` environment variable.

## Core Endpoints

### Health Check

Check server health and Claude Code CLI availability.

**Endpoint**: `GET /health`  
**Authentication**: None required

**Response**:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "claudeCodeAvailable": true,
  "timestamp": "2025-08-09T10:00:00.000Z"
}
```

### Chat API

Send messages to Claude and receive responses via APNS.

**Endpoint**: `POST /api/chat`  
**Authentication**: Required

**Request Body**:
```json
{
  "message": "Your message to Claude",
  "projectPath": "/path/to/project",
  "sessionId": "optional-session-id",
  "deviceToken": "apns-device-token"
}
```

**Parameters**:
- `message` (required): The message to send to Claude
- `projectPath` (required): Working directory for the project (used to maintain conversation context)
- `sessionId` (optional): Session ID from previous response (usually not needed - server tracks this)
- `deviceToken` (required): APNS device token for push notifications

**Session Handling**:
- For new conversations: Don't send sessionId, Claude will generate one
- For continuing conversations: Server automatically uses the correct session for the project
- iOS clients can simply send projectPath and let the server handle session management

**Response**:
```json
{
  "success": true,
  "requestId": "REQ_1234567890",
  "message": "Message queued for processing"
}
```

**Note**: Responses are delivered asynchronously via push notifications to the registered device.

## Session Management

### How Sessions Work

The server automatically manages Claude session IDs behind the scenes:

1. **First Message**: When a client sends a message without a session ID, Claude generates a new session ID
2. **Subsequent Messages**: The server tracks the latest session ID per project and uses `--resume` to continue conversations
3. **Session ID Changes**: Claude returns a new session ID with each response, which the server automatically tracks
4. **Client Simplicity**: iOS clients don't need to manage session IDs - just send the project path

### Session Architecture

- **Server-Managed**: The server maintains a `projectPath → sessionId` mapping
- **Transparent Updates**: Session IDs change with each Claude response, handled automatically
- **Per-Project Context**: Each project maintains its own conversation context
- **Stateless Requests**: Each message is processed independently using `claude --print`

### Get All Sessions

Retrieve metadata about active sessions (primarily for debugging).

**Endpoint**: `GET /api/sessions`  
**Authentication**: Required

**Response**:
```json
{
  "sessions": [
    {
      "sessionId": "current-session-id", 
      "workingDirectory": "/path/to/project",
      "createdAt": "2025-08-09T10:00:00.000Z",
      "lastActivity": "2025-08-09T10:05:00.000Z",
      "messageCount": 5
    }
  ]
}
```

**Note**: Session IDs change frequently as Claude generates new ones. This endpoint shows current mappings.

### Get Claude Sessions

Get information about Claude CLI's internal sessions.

**Endpoint**: `GET /api/sessions/claude`  
**Authentication**: Required

**Response**:
```json
{
  "sessions": [
    {
      "id": "claude-session-123",
      "path": "/path/to/project",
      "lastAccessed": "2025-08-09T10:00:00.000Z"
    }
  ]
}
```

### Deprecated Endpoints

The following endpoints are deprecated as sessions are now managed automatically:
- `GET /api/sessions/:sessionId/status` - Session status tracked internally
- `POST /api/sessions/:sessionId/keepalive` - Not needed with per-message spawning
- `GET /api/sessions/:sessionId/expired` - Expiry handled by Claude CLI
- `POST /api/sessions/claude/cleanup` - Cleanup automatic

## Project Management

### List Projects

Get available project directories.

**Endpoint**: `GET /api/projects`  
**Authentication**: Required

**Query Parameters**:
- `path` (optional): Parent directory to search (defaults to home directory)

**Response**:
```json
{
  "projects": [
    {
      "name": "project-1",
      "path": "/Users/username/projects/project-1",
      "type": "directory",
      "hasGit": true,
      "hasPackageJson": true
    }
  ]
}
```

## Device Management

### Register Device

Register a device for push notifications.

**Endpoint**: `POST /api/devices/register`  
**Authentication**: Required

**Request Body**:
```json
{
  "deviceId": "device-unique-id",
  "token": "apns-device-token",
  "platform": "ios"
}
```

**Response**:
```json
{
  "success": true,
  "deviceId": "device-unique-id",
  "registered": true
}
```

### Unregister Device

Remove a device from push notifications.

**Endpoint**: `POST /api/devices/unregister`  
**Authentication**: Required

**Request Body**:
```json
{
  "deviceId": "device-unique-id"
}
```

**Response**:
```json
{
  "success": true,
  "deviceId": "device-unique-id",
  "unregistered": true
}
```

## Claude CLI Status

### Get Claude Status

Check Claude Code CLI availability and configuration.

**Endpoint**: `GET /api/claude/status`  
**Authentication**: Required

**Response**:
```json
{
  "available": true,
  "version": "1.0.55",
  "executable": "/usr/local/bin/claude",
  "permissions": {
    "mode": "default",
    "allowedTools": ["Read", "Write", "Edit"],
    "skipPermissions": false
  }
}
```

## Push Notifications

### Send Test Notification

Send a test push notification to a registered device.

**Endpoint**: `POST /api/push-notifications/test`  
**Authentication**: Required

**Request Body**:
```json
{
  "deviceId": "device-unique-id",
  "message": "Test notification message"
}
```

**Response**:
```json
{
  "success": true,
  "sent": true,
  "deviceId": "device-unique-id"
}
```

### Get Push Notification Stats

Get statistics about push notifications.

**Endpoint**: `GET /api/push-notifications/stats`  
**Authentication**: Required

**Response**:
```json
{
  "sent": 145,
  "failed": 3,
  "pending": 2,
  "devices": 5,
  "lastSent": "2025-08-09T10:00:00.000Z"
}
```

## Telemetry

### Get Telemetry Data

Retrieve server telemetry and metrics.

**Endpoint**: `GET /api/telemetry`  
**Authentication**: Required

**Response**:
```json
{
  "uptime": 3600,
  "memory": {
    "used": 123456789,
    "total": 8589934592
  },
  "sessions": {
    "active": 3,
    "total": 15
  },
  "messages": {
    "sent": 234,
    "received": 230
  },
  "timestamp": "2025-08-09T10:00:00.000Z"
}
```

## Error Responses

All endpoints return consistent error responses:

```json
{
  "success": false,
  "error": "Error message description",
  "code": "ERROR_CODE"
}
```

Common HTTP status codes:
- `200 OK`: Success
- `400 Bad Request`: Invalid request parameters
- `401 Unauthorized`: Missing or invalid auth token
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

## Rate Limiting

API endpoints are rate-limited to prevent abuse:
- Default: 100 requests per minute per IP
- Chat endpoint: 30 requests per minute per IP

Rate limit headers are included in responses:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1691577600
```

## Message Flow

1. iOS app sends message via `POST /api/chat`
2. Server queues message for processing
3. Server executes Claude CLI with message
4. Claude response is sent via APNS to device token
5. iOS app receives push notification with response
6. iOS app displays response in chat interface

## Configuration

Server configuration via environment variables:

- `PORT`: Server port (default: 3001)
- `AUTH_TOKEN`: Authentication token (required)
- `CLAUDE_EXECUTABLE_PATH`: Path to Claude Code CLI (default: auto-detect)
- `SESSION_TIMEOUT`: Session timeout in milliseconds (default: 3600000)
- `MESSAGE_QUEUE_MAX_SIZE`: Max queued messages per session (default: 100)
- `APNS_CERT_PATH`: Path to APNS certificate
- `APNS_KEY_PATH`: Path to APNS key
- `APNS_PRODUCTION`: Use production APNS (default: false)

---

**Last Updated**: 2025-08-18  
**API Version**: 1.0.0