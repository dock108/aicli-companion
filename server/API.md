# Claude Companion Server API Documentation

## Overview

The Claude Companion Server provides a comprehensive WebSocket and REST API for integrating AICLI (Claude) with mobile and desktop applications. It features real-time streaming, session persistence, push notifications, and robust error handling.

## Base URL

```
http://localhost:3001
```

For TLS-enabled deployments:
```
https://your-server:3001
```

## Authentication

Authentication is required for all endpoints unless explicitly noted.

### Methods

1. **Bearer Token (REST API)**
   ```
   Authorization: Bearer YOUR_TOKEN
   ```

2. **Query Parameter (WebSocket)**
   ```
   ws://localhost:3001/ws?token=YOUR_TOKEN
   ```

3. **Environment Variable**
   ```bash
   AUTH_TOKEN=your-secure-token
   ```

### Token Generation

Tokens can be generated via:
- macOS companion app (stored in Keychain)
- Server startup (logged to console)
- Manual generation (UUID recommended)

## Service Discovery

The server broadcasts its presence via Bonjour/mDNS:

- **Service Type**: `_aiclicompanion._tcp`
- **TXT Records**: 
  - `version`: Server version
  - `auth`: Authentication required (true/false)
  - `port`: Server port
  - `token`: Auth token (if auth disabled)

## REST API Endpoints

### Health & Status

#### Health Check
```http
GET /health
```

**Authentication**: Not required

**Description**: Returns server health status and basic information.

**Response**: `200 OK`
```json
{
  "status": "healthy",
  "uptime": 123456,
  "version": "1.0.0",
  "aicliAvailable": true,
  "timestamp": "2025-01-05T12:00:00.000Z",
  "activeSessions": [
    {
      "sessionId": "uuid-here",
      "deviceName": "John's iPhone"
    }
  ]
}
```

#### Server Info
```http
GET /api/info
```

**Description**: Returns detailed server capabilities and configuration.

**Response**: `200 OK`
```json
{
  "version": "1.0.0",
  "capabilities": [
    "chat",
    "streaming",
    "permissions",
    "file-operations",
    "session-management",
    "push-notifications"
  ],
  "aicli": {
    "available": true,
    "version": "0.6.5",
    "executable": "/usr/local/bin/claude"
  },
  "config": {
    "authRequired": true,
    "tlsEnabled": false,
    "bonjourEnabled": true,
    "maxSessions": 5,
    "sessionTimeout": 86400000
  }
}
```

### Session Management

#### List All Sessions
```http
GET /api/sessions
```

**Description**: Returns all active sessions with detailed metadata.

**Query Parameters**:
- `active` (boolean): Filter only active sessions
- `projectPath` (string): Filter by project path

**Response**: `200 OK`
```json
{
  "sessions": [
    {
      "sessionId": "550e8400-e29b-41d4-a716-446655440000",
      "workingDirectory": "/Users/john/projects/my-app",
      "projectName": "my-app",
      "isActive": true,
      "isProcessing": false,
      "createdAt": 1704300000000,
      "lastActivity": 1704303600000,
      "messageCount": 42,
      "metadata": {
        "deviceId": "device-123",
        "clientVersion": "1.0.0",
        "platform": "ios"
      }
    }
  ],
  "total": 1,
  "active": 1
}
```

#### Get Session Details
```http
GET /api/sessions/:sessionId
```

**Description**: Returns comprehensive information about a specific session.

**Response**: `200 OK`
```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "workingDirectory": "/Users/john/projects/my-app",
  "projectName": "my-app",
  "isActive": true,
  "isProcessing": false,
  "createdAt": 1704300000000,
  "lastActivity": 1704303600000,
  "conversationStarted": true,
  "messageCount": 42,
  "buffer": {
    "size": 15360,
    "messages": 42
  },
  "process": {
    "pid": 12345,
    "uptime": 3600000,
    "memoryUsage": 52428800
  },
  "metadata": {
    "deviceId": "device-123",
    "clientVersion": "1.0.0",
    "platform": "ios",
    "lastCommand": "Help me understand this function"
  }
}
```

**Error Response**: `404 Not Found`
```json
{
  "error": "Session not found",
  "code": "SESSION_NOT_FOUND"
}
```

#### Continue Session
```http
POST /api/sessions/continue
```

**Description**: Allows clients (especially mobile) to reconnect to an existing session after disconnection.

**Request Body**:
```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "workingDirectory": "/Users/john/projects/my-app",
  "deviceId": "device-123",
  "metadata": {
    "clientVersion": "1.0.0",
    "platform": "ios"
  }
}
```

**Response**: `200 OK`
```json
{
  "success": true,
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "message": "Session continued successfully",
  "workingDirectory": "/Users/john/projects/my-app",
  "messageHistory": [
    {
      "role": "user",
      "content": "Previous message",
      "timestamp": 1704300000000
    },
    {
      "role": "assistant",
      "content": "Previous response",
      "timestamp": 1704300060000
    }
  ],
  "isNew": false
}
```

#### Get Message History
```http
GET /api/sessions/:sessionId/messages
```

**Description**: Retrieves message history for a session.

**Query Parameters**:
- `limit` (number): Maximum messages to return (default: 50)
- `offset` (number): Pagination offset (default: 0)
- `since` (timestamp): Messages after this timestamp

**Response**: `200 OK`
```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "messages": [
    {
      "id": "msg-123",
      "role": "user",
      "content": "Help me write a function",
      "timestamp": 1704300000000
    },
    {
      "id": "msg-124",
      "role": "assistant",
      "content": "I'll help you write a function...",
      "timestamp": 1704300060000,
      "metadata": {
        "toolsUsed": ["Write", "Read"],
        "processingTime": 5230
      }
    }
  ],
  "total": 42,
  "hasMore": true
}
```

### Project Management

#### List Projects
```http
GET /api/projects
```

**Description**: Lists available projects with session information.

**Query Parameters**:
- `includeHidden` (boolean): Include hidden directories
- `withSessions` (boolean): Only show projects with active sessions

**Response**: `200 OK`
```json
{
  "rootDirectory": "/Users/john/projects",
  "projects": [
    {
      "name": "my-app",
      "path": "/Users/john/projects/my-app",
      "hasSession": true,
      "sessionId": "550e8400-e29b-41d4-a716-446655440000",
      "sessionActive": true,
      "lastModified": 1704300000000,
      "size": 52428800,
      "metadata": {
        "hasGitRepo": true,
        "hasPackageJson": true,
        "hasReadme": true
      }
    },
    {
      "name": "another-project",
      "path": "/Users/john/projects/another-project",
      "hasSession": false,
      "lastModified": 1704200000000,
      "size": 10485760
    }
  ],
  "total": 2
}
```

#### Start Project Session
```http
POST /api/projects/:name/start
```

**Description**: Starts or reuses an AICLI session for a project.

**Request Body**:
```json
{
  "initialPrompt": "Help me understand this codebase",
  "skipPermissions": false,
  "allowedTools": ["Read", "Write", "Edit"],
  "metadata": {
    "deviceId": "device-123",
    "clientVersion": "1.0.0",
    "platform": "ios"
  }
}
```

**Response**: `200 OK`
```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "success": true,
  "message": "Session ready for commands",
  "reused": false,
  "workingDirectory": "/Users/john/projects/my-app",
  "projectName": "my-app",
  "permissions": {
    "skipPermissions": false,
    "allowedTools": ["Read", "Write", "Edit"]
  }
}
```

**Error Response**: `400 Bad Request`
```json
{
  "error": "Project not found",
  "code": "PROJECT_NOT_FOUND",
  "suggestion": "Check project name and ensure it exists in the configured directory"
}
```

### AICLI Integration

#### Get AICLI Status
```http
GET /api/aicli/status
```

**Description**: Returns AICLI availability and configuration.

**Response**: `200 OK`
```json
{
  "available": true,
  "version": "0.6.5",
  "executable": "/usr/local/bin/claude",
  "commands": ["claude", "aicli"],
  "environment": {
    "skipPermissions": false,
    "allowedTools": ["Read", "Write", "Edit", "Bash"]
  },
  "sessions": {
    "active": 3,
    "max": 5
  }
}
```

#### Test AICLI
```http
POST /api/aicli/test
```

**Description**: Tests AICLI with a simple prompt.

**Request Body**:
```json
{
  "prompt": "Say hello and tell me your version",
  "timeout": 10000
}
```

**Response**: `200 OK`
```json
{
  "success": true,
  "response": "Hello! I'm Claude, version 3.5...",
  "executionTime": 2345,
  "command": "claude --version"
}
```

#### One-time Query
```http
POST /api/aicli/ask
```

**Description**: Send a one-time query without creating a session.

**Request Body**:
```json
{
  "prompt": "What is the capital of France?",
  "context": "Geography question",
  "timeout": 30000
}
```

**Response**: `200 OK`
```json
{
  "response": "The capital of France is Paris.",
  "executionTime": 1234
}
```

### Telemetry & Monitoring

#### Get Comprehensive Metrics
```http
GET /api/telemetry
```

**Description**: Returns detailed telemetry data for monitoring and debugging.

**Query Parameters**:
- `period` (string): Time period (1h, 24h, 7d, 30d)
- `includeDetails` (boolean): Include detailed breakdowns

**Response**: `200 OK`
```json
{
  "timestamp": 1704303600000,
  "period": "24h",
  "uptime": 86400000,
  "websocket": {
    "activeConnections": 5,
    "totalConnections": 123,
    "uniqueClients": 45,
    "messages": {
      "sent": 10000,
      "received": 9500,
      "failed": 50,
      "avgSize": 2048
    },
    "reconnections": 150,
    "errors": {
      "authentication": 10,
      "timeout": 5,
      "protocol": 2
    }
  },
  "sessions": {
    "created": 500,
    "resumed": 200,
    "expired": 50,
    "active": 10,
    "duplicatesPrevented": 150,
    "averageDuration": 3600000,
    "byProject": {
      "my-app": 250,
      "another-project": 150
    }
  },
  "messages": {
    "queued": 1000,
    "delivered": 950,
    "expired": 50,
    "filtered": 100,
    "avgDeliveryTime": 150,
    "maxQueueSize": 500
  },
  "aicli": {
    "processesSpawned": 500,
    "processesCrashed": 5,
    "avgResponseTime": 2500,
    "toolUsage": {
      "Read": 2000,
      "Write": 500,
      "Edit": 1500,
      "Bash": 100
    }
  },
  "performance": {
    "cpu": {
      "usage": 15.5,
      "load": [1.2, 1.5, 1.8]
    },
    "memory": {
      "used": 268435456,
      "total": 8589934592,
      "percentage": 3.1
    },
    "avgMessageProcessingTime": 25.5,
    "avgQueueDeliveryTime": 150.2,
    "p95ResponseTime": 5000,
    "p99ResponseTime": 10000
  },
  "errors": {
    "total": 67,
    "byType": {
      "INVALID_SESSION": 20,
      "PERMISSION_DENIED": 15,
      "TIMEOUT": 10,
      "PROCESS_CRASH": 5
    }
  }
}
```

#### Get Client Metrics
```http
GET /api/telemetry/client/:clientId
```

**Description**: Returns detailed metrics for a specific client.

**Response**: `200 OK`
```json
{
  "clientId": "client-123",
  "deviceId": "device-123",
  "connection": {
    "status": "connected",
    "connectedAt": 1704300000000,
    "duration": 3600000,
    "reconnections": 2,
    "lastActivity": 1704303600000
  },
  "messages": {
    "sent": 100,
    "received": 95,
    "queued": 5,
    "avgLatency": 150
  },
  "sessions": [
    {
      "sessionId": "550e8400-e29b-41d4-a716-446655440000",
      "projectName": "my-app",
      "messageCount": 42,
      "duration": 3600000
    }
  ],
  "errors": {
    "total": 2,
    "recent": [
      {
        "timestamp": 1704302000000,
        "type": "TIMEOUT",
        "message": "Request timeout"
      }
    ]
  }
}
```

#### Export Metrics
```http
GET /api/telemetry/export
```

**Description**: Exports telemetry data in various formats.

**Query Parameters**:
- `format` (string): Export format (json, csv, prometheus)
- `period` (string): Time period to export

**Response**: `200 OK`
```
Content-Type: application/json or text/csv or text/plain
```

#### Reset Metrics
```http
POST /api/telemetry/reset
```

**Description**: Resets telemetry metrics (requires admin auth).

**Request Body**:
```json
{
  "confirm": true,
  "metrics": ["websocket", "sessions", "messages", "errors"]
}
```

**Response**: `200 OK`
```json
{
  "success": true,
  "message": "Metrics reset successfully",
  "resetCount": 4
}
```

### Push Notifications

#### Get Push Notification Statistics
```http
GET /api/push-notifications/stats
```

**Description**: Returns comprehensive push notification statistics.

**Response**: `200 OK`
```json
{
  "enabled": true,
  "provider": "apns",
  "statistics": {
    "sent": {
      "total": 1000,
      "successful": 950,
      "failed": 50
    },
    "devices": {
      "registered": 25,
      "active": 20,
      "badTokens": 3,
      "retrying": 2
    },
    "performance": {
      "avgDeliveryTime": 250,
      "p95DeliveryTime": 500,
      "queueSize": 5
    }
  },
  "recentActivity": [
    {
      "timestamp": 1704303600000,
      "deviceId": "device-123",
      "status": "delivered",
      "type": "task_complete"
    }
  ]
}
```

#### Send Test Notification
```http
POST /api/push-notifications/test
```

**Description**: Sends a test push notification to verify configuration.

**Request Body**:
```json
{
  "clientId": "client-123",
  "deviceToken": "optional-specific-token",
  "notification": {
    "title": "Test Notification",
    "body": "This is a test message",
    "sound": "default",
    "badge": 1,
    "data": {
      "sessionId": "550e8400-e29b-41d4-a716-446655440000",
      "action": "open_chat"
    }
  }
}
```

**Response**: `200 OK`
```json
{
  "success": true,
  "messageId": "apns-123456",
  "deviceToken": "token-hash",
  "deliveryTime": 234
}
```

#### Manage Device Tokens
```http
DELETE /api/push-notifications/tokens/invalid
```

**Description**: Removes invalid device tokens from the system.

**Query Parameters**:
- `force` (boolean): Force removal without grace period

**Response**: `200 OK`
```json
{
  "removed": 3,
  "tokens": [
    "abc123...",
    "def456...",
    "ghi789..."
  ],
  "remaining": 20
}
```

#### Update Device Token
```http
PUT /api/push-notifications/tokens/:deviceId
```

**Description**: Updates a device token (for token refresh).

**Request Body**:
```json
{
  "oldToken": "old-token-value",
  "newToken": "new-token-value",
  "platform": "ios"
}
```

**Response**: `200 OK`
```json
{
  "success": true,
  "deviceId": "device-123",
  "message": "Token updated successfully"
}
```

## WebSocket API

### Connection

#### Endpoint
```
ws://localhost:3001/ws?token=YOUR_TOKEN
```

For TLS:
```
wss://your-server:3001/ws?token=YOUR_TOKEN
```

#### Connection Headers
```http
GET /ws?token=YOUR_TOKEN HTTP/1.1
Host: localhost:3001
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
X-Device-ID: unique-device-identifier
X-Client-Version: 1.0.0
X-Platform: ios
```

#### Connection Process
1. Client connects with auth token
2. Server validates token
3. Server sends welcome message
4. Client subscribes to events
5. Bidirectional communication begins

#### Reconnection
Clients should implement automatic reconnection with:
- Exponential backoff (1s, 2s, 4s, 8s, max 30s)
- Device ID header for session restoration
- Jitter to prevent thundering herd

### Message Format

All WebSocket messages use a standardized format:

```typescript
interface WebSocketMessage {
  type: string;                    // Message type identifier
  timestamp: string;               // ISO-8601 timestamp
  requestId?: string;              // Client-generated request ID
  data: any;                       // Message payload
  error?: {                        // Error information (if applicable)
    code: string;
    message: string;
    details?: any;
  };
  metadata?: {                     // Optional metadata
    clientVersion?: string;
    platform?: string;
    [key: string]: any;
  };
}
```

#### Message Compression
Messages larger than 1KB are automatically compressed using permessage-deflate.

### Client-to-Server Messages

#### Send Command
Send a message to Claude within a session.

```json
{
  "type": "sendCommand",
  "requestId": "req-123",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "prompt": "Help me refactor this function",
    "context": {
      "previousMessageId": "msg-122",
      "isFollowUp": true
    }
  },
  "metadata": {
    "clientVersion": "1.0.0",
    "platform": "ios"
  }
}
```

**Acknowledgment**:
```json
{
  "type": "commandAck",
  "timestamp": "2025-01-05T12:00:00.100Z",
  "requestId": "req-123",
  "data": {
    "messageId": "msg-125",
    "status": "processing"
  }
}
```

#### Subscribe to Events
Subscribe to specific event types.

```json
{
  "type": "subscribe",
  "requestId": "req-124",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "events": [
      "assistantMessage",
      "streamData",
      "sessionStatus",
      "toolExecution",
      "error"
    ],
    "sessionIds": ["550e8400-e29b-41d4-a716-446655440000"]
  }
}
```

**Available Events**:
- `assistantMessage`: Complete Claude responses
- `streamData`: Streaming response chunks
- `sessionStatus`: Session state changes
- `toolExecution`: Tool usage notifications
- `error`: Error notifications
- `heartbeat`: Connection keep-alive
- `queueStatus`: Message queue updates

#### Register Device for Push Notifications
Register or update device token for push notifications.

```json
{
  "type": "registerDevice",
  "requestId": "req-125",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "deviceToken": "740f4707bebcf74f9b7c25d48e8c3a5e8c8f1e8c3a5e8c8f1e8c3a5e8c8f1e8c",
    "platform": "ios",
    "deviceInfo": {
      "model": "iPhone15,2",
      "osVersion": "17.2",
      "appVersion": "1.0.0",
      "locale": "en_US",
      "timezone": "America/New_York"
    },
    "preferences": {
      "enabled": true,
      "sounds": true,
      "taskComplete": true,
      "errors": true
    }
  }
}
```

**Response**:
```json
{
  "type": "deviceRegistered",
  "timestamp": "2025-01-05T12:00:00.100Z",
  "requestId": "req-125",
  "data": {
    "success": true,
    "deviceId": "device-123",
    "message": "Device registered for push notifications"
  }
}
```

#### Session Lifecycle Events
Notify server of app state changes for proper session management.

**Background**:
```json
{
  "type": "sessionBackgrounded",
  "requestId": "req-126",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "expectedDuration": "short",
    "enableNotifications": true
  }
}
```

**Foreground**:
```json
{
  "type": "sessionForegrounded",
  "requestId": "req-127",
  "timestamp": "2025-01-05T12:05:00Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "requestQueuedMessages": true,
    "requestMissedUpdates": true
  }
}
```

#### Get Message History
Request historical messages for a session.

```json
{
  "type": "getMessageHistory",
  "requestId": "req-128",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "limit": 50,
    "offset": 0,
    "since": "2025-01-05T00:00:00Z"
  }
}
```

#### Heartbeat
Keep connection alive during idle periods.

```json
{
  "type": "ping",
  "timestamp": "2025-01-05T12:00:00Z"
}
```

### Server-to-Client Messages

#### Welcome Message
Sent immediately after successful connection.

```json
{
  "type": "welcome",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "clientId": "client-123",
    "deviceId": "device-123",
    "serverVersion": "1.0.0",
    "aicliVersion": "0.6.5",
    "capabilities": [
      "chat",
      "streaming",
      "permissions",
      "file-operations",
      "session-management",
      "push-notifications",
      "message-queue",
      "telemetry"
    ],
    "limits": {
      "maxSessions": 5,
      "maxMessageSize": 1048576,
      "maxQueueSize": 1000
    },
    "config": {
      "authRequired": true,
      "tlsEnabled": false,
      "compressionEnabled": true
    },
    "restoredSessions": [
      {
        "sessionId": "550e8400-e29b-41d4-a716-446655440000",
        "projectName": "my-app",
        "messageCount": 42
      }
    ]
  }
}
```

#### Assistant Message
Complete response from Claude.

```json
{
  "type": "assistantMessage",
  "timestamp": "2025-01-05T12:00:05Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "messageId": "msg-125",
    "content": "I'll help you refactor this function. Let me first examine the current implementation...\n\n```javascript\nfunction processData(input) {\n  // Refactored code here\n}\n```\n\nThe main improvements include...",
    "isStreaming": false,
    "isComplete": true,
    "metadata": {
      "processingTime": 5230,
      "tokensUsed": 450,
      "toolsUsed": ["Read", "Edit"],
      "requestId": "req-123"
    }
  }
}
```

#### Stream Data
Streaming response chunks for real-time display.

```json
{
  "type": "streamData",
  "timestamp": "2025-01-05T12:00:01Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "messageId": "msg-125",
    "sequenceNumber": 1,
    "chunk": {
      "type": "content",
      "data": {
        "content": "I'll help you refactor this function. ",
        "isCode": false
      }
    },
    "metadata": {
      "requestId": "req-123",
      "isFirst": true,
      "estimatedCompletion": 5000
    }
  }
}
```

**Chunk Types**:
- `content`: Regular text content
- `code`: Code block with language
- `tool_use`: Tool execution notification
- `thinking`: Claude's reasoning process
- `section`: Document section marker

**Code Chunk Example**:
```json
{
  "chunk": {
    "type": "code",
    "data": {
      "language": "javascript",
      "content": "function processData(input) {\n",
      "filename": "utils.js",
      "lineStart": 42
    }
  }
}
```

**Tool Use Chunk**:
```json
{
  "chunk": {
    "type": "tool_use",
    "data": {
      "tool": "Read",
      "parameters": {
        "file": "src/utils.js"
      },
      "status": "executing"
    }
  }
}
```

#### Error Message
Error notifications with actionable information.

```json
{
  "type": "error",
  "timestamp": "2025-01-05T12:00:10Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "messageId": "msg-125",
    "error": "Session timeout - no activity for 24 hours",
    "code": "SESSION_TIMEOUT",
    "severity": "warning",
    "recoverable": true,
    "details": {
      "lastActivity": "2025-01-04T12:00:00Z",
      "timeout": 86400000
    },
    "suggestions": [
      "Start a new session",
      "Restore from saved state"
    ],
    "metadata": {
      "requestId": "req-123"
    }
  }
}
```

#### Session Status Update
Notifications about session state changes.

```json
{
  "type": "sessionStatus",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "active",
    "previousStatus": "idle",
    "reason": "User activity",
    "metadata": {
      "lastActivity": "2025-01-05T12:00:00Z",
      "messageCount": 43,
      "uptime": 3600000
    }
  }
}
```

#### Message History Response
Response to getMessageHistory request.

```json
{
  "type": "getMessageHistoryResponse",
  "timestamp": "2025-01-05T12:00:00Z",
  "requestId": "req-128",
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "messages": [
      {
        "id": "msg-123",
        "role": "user",
        "content": "Help me write a function",
        "timestamp": "2025-01-05T11:00:00Z"
      },
      {
        "id": "msg-124",
        "role": "assistant",
        "content": "I'll help you write a function...",
        "timestamp": "2025-01-05T11:00:05Z"
      }
    ],
    "total": 42,
    "offset": 0,
    "limit": 50,
    "hasMore": false
  }
}
```

#### Heartbeat
Server heartbeat for connection monitoring.

```json
{
  "type": "pong",
  "timestamp": "2025-01-05T12:00:00Z",
  "data": {
    "serverTime": 1704456000000,
    "latency": 15
  }
}
```

## Error Codes

### Session Errors
- `SESSION_NOT_FOUND` - Session ID doesn't exist
- `SESSION_EXPIRED` - Session exceeded timeout period
- `SESSION_LIMIT` - Maximum concurrent sessions reached
- `SESSION_INVALID_STATE` - Operation not allowed in current state
- `SESSION_DUPLICATE` - Session already exists for this project

### Authentication Errors
- `AUTH_REQUIRED` - Authentication token required
- `AUTH_INVALID` - Invalid authentication token
- `AUTH_EXPIRED` - Authentication token expired
- `AUTH_INSUFFICIENT` - Insufficient permissions

### Request Errors
- `INVALID_REQUEST` - Malformed request format
- `INVALID_PARAMETERS` - Invalid or missing parameters
- `REQUEST_TOO_LARGE` - Request exceeds size limit
- `RATE_LIMIT` - Too many requests

### System Errors
- `AICLI_UNAVAILABLE` - AICLI not found or not responding
- `AICLI_TIMEOUT` - AICLI process timeout
- `AICLI_CRASH` - AICLI process crashed
- `SERVER_ERROR` - Internal server error
- `RESOURCE_EXHAUSTED` - System resources exhausted

### WebSocket Errors
- `WS_PROTOCOL_ERROR` - WebSocket protocol violation
- `WS_MESSAGE_INVALID` - Invalid message format
- `WS_CONNECTION_LIMIT` - Too many connections

### Tool Errors
- `PERMISSION_DENIED` - Tool use not permitted
- `TOOL_EXECUTION_FAILED` - Tool failed to execute
- `FILE_NOT_FOUND` - Requested file doesn't exist
- `FILE_ACCESS_DENIED` - File access not permitted

## Rate Limits & Quotas

### Connection Limits
- **WebSocket Connections**: 100 per IP address
- **HTTP Requests**: 1000 per minute per IP
- **Concurrent Sessions**: 5 per client
- **Message Queue Size**: 1000 messages per session

### Message Limits
- **Messages per Second**: 10 per client
- **Message Size**: 1MB maximum
- **Stream Chunk Size**: 64KB maximum
- **Batch Operations**: 100 items maximum

### Resource Quotas
- **Session Duration**: 24 hours (configurable)
- **Message History**: 10,000 messages per session
- **File Storage**: 100MB per session
- **Process Memory**: 512MB per AICLI process

### Push Notification Limits
- **Notifications per Hour**: 100 per device
- **Notification Size**: 4KB maximum
- **Device Registrations**: 10 per user
- **Retry Attempts**: 3 with exponential backoff

### Rate Limit Headers
All responses include rate limit information:
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 950
X-RateLimit-Reset: 1704456000
Retry-After: 60
```

## SDKs and Client Libraries

### Official SDKs
- **iOS (Swift)**: Built into the iOS app
- **TypeScript/JavaScript**: `npm install @claude-companion/client`
- **Python**: `pip install claude-companion`

### Example Usage

**JavaScript/TypeScript**:
```typescript
import { ClaudeCompanionClient } from '@claude-companion/client';

const client = new ClaudeCompanionClient({
  url: 'http://localhost:3001',
  token: 'your-auth-token',
  deviceId: 'unique-device-id'
});

// Connect and subscribe
await client.connect();
client.on('assistantMessage', (data) => {
  console.log('Claude:', data.content);
});

// Send a message
const response = await client.sendMessage({
  sessionId: 'session-id',
  prompt: 'Help me understand this code'
});
```

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

## Versioning

The API follows semantic versioning. The current version is included in all responses:

```http
X-API-Version: 1.0.0
```

### Version History

#### v1.0.0 (2025-01-05)
- Initial stable release
- Complete WebSocket and REST API
- Session persistence and restoration
- Push notification support
- Message queue with delivery guarantees
- Comprehensive telemetry
- WebSocket reconnection support
- Session deduplication
- Stream chunk filtering

#### Future Versions
- v1.1.0: Planned support for multiple AI models
- v1.2.0: Webhook integrations
- v2.0.0: GraphQL API

## Support

### Resources
- **Documentation**: https://github.com/your-username/claude-companion
- **Issues**: https://github.com/your-username/claude-companion/issues
- **Discussions**: https://github.com/your-username/claude-companion/discussions

### Contact
- **Email**: support@claude-companion.dev
- **Discord**: [Join our community](https://discord.gg/claude-companion)