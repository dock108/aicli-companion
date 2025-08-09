# AICLI Companion API Documentation

## Overview

The AICLI Companion Server provides a RESTful API for iOS clients to interact with AI assistants through Claude CLI. The server uses HTTP endpoints with Apple Push Notification Service (APNS) for message delivery.

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

Check server health and Claude CLI availability.

**Endpoint**: `GET /health`  
**Authentication**: None required

**Response**:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "aicliCodeAvailable": true,
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
- `projectPath` (optional): Working directory for Claude
- `sessionId` (optional): Existing session ID to continue conversation
- `deviceToken` (required): APNS device token for push notifications

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

### Get All Sessions

Retrieve all active sessions.

**Endpoint**: `GET /api/sessions`  
**Authentication**: Required

**Response**:
```json
{
  "sessions": [
    {
      "sessionId": "session-123",
      "workingDirectory": "/path/to/project",
      "createdAt": "2025-08-09T10:00:00.000Z",
      "lastActivity": "2025-08-09T10:05:00.000Z",
      "messageCount": 5
    }
  ]
}
```

### Get Session Status

Check the status of a specific session.

**Endpoint**: `GET /api/sessions/:sessionId/status`  
**Authentication**: Required

**Response**:
```json
{
  "sessionId": "session-123",
  "status": "active",
  "lastActivity": "2025-08-09T10:05:00.000Z"
}
```

### Keep Session Alive

Prevent a session from timing out.

**Endpoint**: `POST /api/sessions/:sessionId/keepalive`  
**Authentication**: Required

**Response**:
```json
{
  "success": true,
  "sessionId": "session-123",
  "expiresAt": "2025-08-09T11:00:00.000Z"
}
```

### Check Session Expiry

Check if a session has expired.

**Endpoint**: `GET /api/sessions/:sessionId/expired`  
**Authentication**: Required

**Response**:
```json
{
  "expired": false,
  "sessionId": "session-123",
  "expiresAt": "2025-08-09T11:00:00.000Z"
}
```

### Get Claude Sessions

Get all sessions managed by Claude CLI.

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

### Cleanup Claude Sessions

Clean up expired or orphaned Claude sessions.

**Endpoint**: `POST /api/sessions/claude/cleanup`  
**Authentication**: Required

**Response**:
```json
{
  "success": true,
  "cleaned": 3,
  "message": "Cleaned up 3 expired sessions"
}
```

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

Check Claude CLI availability and configuration.

**Endpoint**: `GET /api/aicli/status`  
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
- `CLAUDE_EXECUTABLE_PATH`: Path to Claude CLI (default: auto-detect)
- `SESSION_TIMEOUT`: Session timeout in milliseconds (default: 3600000)
- `MESSAGE_QUEUE_MAX_SIZE`: Max queued messages per session (default: 100)
- `APNS_CERT_PATH`: Path to APNS certificate
- `APNS_KEY_PATH`: Path to APNS key
- `APNS_PRODUCTION`: Use production APNS (default: false)

---

**Last Updated**: 2025-08-09  
**API Version**: 1.0.0