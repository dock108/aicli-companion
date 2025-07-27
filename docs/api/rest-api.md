# REST API Reference

The Claude Companion Server provides a RESTful HTTP API for one-time queries and session management.

## Base URL

```
http://localhost:3001/api
```

For production with TLS:
```
https://your-server.com/api
```

## Authentication

All API endpoints require authentication using a bearer token.

### Request Headers
```http
Authorization: Bearer YOUR_AUTH_TOKEN
```

### Query Parameter Alternative
```
GET /api/endpoint?token=YOUR_AUTH_TOKEN
```

## Common Response Format

### Success Response
```json
{
  "success": true,
  "data": {
    // Response data
  }
}
```

### Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      // Additional error context
    }
  }
}
```

## Endpoints

### Health Check

Check server health and availability.

**Endpoint:** `GET /health`

**Authentication:** Not required

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2025-07-27T10:30:00Z",
  "uptime": 3600
}
```

### Server Information

Get detailed server information and capabilities.

**Endpoint:** `GET /api/info`

**Response:**
```json
{
  "success": true,
  "data": {
    "version": "1.0.0",
    "claude": {
      "installed": true,
      "version": "1.0.55",
      "path": "/usr/local/bin/claude"
    },
    "capabilities": [
      "streaming",
      "permissions",
      "multiSession",
      "bonjour"
    ],
    "limits": {
      "maxSessions": 5,
      "sessionTimeout": 1800000,
      "maxMessageLength": 100000
    }
  }
}
```

### One-Time Query

Send a single prompt to Claude and receive a complete response.

**Endpoint:** `POST /api/ask`

**Request Body:**
```json
{
  "prompt": "What files are in the current directory?",
  "workingDirectory": "/Users/user/project",
  "options": {
    "timeout": 30000,
    "format": "markdown"
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "response": "Here are the files in the current directory:\n\n- `index.js` - Main application file\n- `package.json` - Node.js dependencies\n- `README.md` - Project documentation",
    "duration": 2500,
    "cost": 0.05,
    "usage": {
      "inputTokens": 15,
      "outputTokens": 45
    }
  }
}
```

### Start Streaming Session

Create a new streaming conversation session.

**Endpoint:** `POST /api/stream/start`

**Request Body:**
```json
{
  "prompt": "Help me debug this code",
  "workingDirectory": "/Users/user/project",
  "options": {
    "sessionName": "Debug Session",
    "preserveContext": true,
    "allowedTools": ["Read", "Write", "Edit"]
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "active",
    "createdAt": "2025-07-27T10:30:00Z",
    "workingDirectory": "/Users/user/project"
  }
}
```

### Send to Streaming Session

Continue an existing streaming conversation.

**Endpoint:** `POST /api/stream/:sessionId`

**Request Body:**
```json
{
  "prompt": "Show me the error in line 42",
  "options": {
    "timeout": 30000
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "queued": true,
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "messageId": "msg_12345"
  }
}
```

### Close Streaming Session

Terminate an active streaming session.

**Endpoint:** `DELETE /api/stream/:sessionId`

**Response:**
```json
{
  "success": true,
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "status": "closed",
    "duration": 300000,
    "messageCount": 15,
    "totalCost": 0.25
  }
}
```

### List Active Sessions

Get all active streaming sessions.

**Endpoint:** `GET /api/sessions`

**Response:**
```json
{
  "success": true,
  "data": {
    "sessions": [
      {
        "sessionId": "550e8400-e29b-41d4-a716-446655440000",
        "name": "Debug Session",
        "status": "active",
        "createdAt": "2025-07-27T10:30:00Z",
        "lastActivity": "2025-07-27T10:35:00Z",
        "messageCount": 5,
        "workingDirectory": "/Users/user/project"
      }
    ],
    "active": 1,
    "available": 4
  }
}
```

### Handle Permission Request

Respond to a Claude permission prompt.

**Endpoint:** `POST /api/permission/:sessionId`

**Request Body:**
```json
{
  "response": "y",
  "remember": false
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "accepted": true,
    "prompt": "Allow Claude to edit app.js?"
  }
}
```

### Claude Status

Check Claude CLI availability and configuration.

**Endpoint:** `GET /api/claude/status`

**Response:**
```json
{
  "success": true,
  "data": {
    "claude": {
      "installed": true,
      "version": "1.0.55",
      "path": "/usr/local/bin/claude",
      "available": true
    },
    "configuration": {
      "permissionMode": "default",
      "allowedTools": ["Read", "Write", "Edit"],
      "skipPermissions": false
    }
  }
}
```

### Test Claude CLI

Run a test prompt through Claude CLI.

**Endpoint:** `POST /api/claude/test`

**Request Body:**
```json
{
  "prompt": "Hello! Please respond with a brief greeting."
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "response": "Hello! I'm Claude, ready to help you with your coding tasks.",
    "duration": 1500,
    "claudeVersion": "1.0.55"
  }
}
```

## Error Codes

| Code | Description | HTTP Status |
|------|-------------|-------------|
| `AUTH_REQUIRED` | Missing authentication token | 401 |
| `AUTH_INVALID` | Invalid authentication token | 401 |
| `SESSION_NOT_FOUND` | Session ID doesn't exist | 404 |
| `SESSION_LIMIT` | Maximum sessions reached | 429 |
| `CLAUDE_UNAVAILABLE` | Claude CLI not accessible | 503 |
| `INVALID_REQUEST` | Malformed request data | 400 |
| `TIMEOUT` | Operation timed out | 504 |
| `INTERNAL_ERROR` | Server error occurred | 500 |

## Rate Limiting

Default rate limits:
- **Requests per minute**: 60
- **Sessions per hour**: 10
- **Concurrent sessions**: 5 (configurable)

Rate limit headers:
```http
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1627814400
```

## Best Practices

### Request Guidelines
1. Always include authentication token
2. Set appropriate timeouts for long operations
3. Handle errors gracefully
4. Implement exponential backoff for retries
5. Close sessions when done

### Security Recommendations
1. Use HTTPS in production
2. Rotate auth tokens regularly
3. Validate all input data
4. Monitor for unusual activity
5. Implement request signing (future)

### Performance Tips
1. Reuse sessions for conversations
2. Set reasonable timeout values
3. Implement client-side caching
4. Use streaming for real-time needs
5. Monitor session metrics

## Examples

### cURL Example
```bash
# One-time query
curl -X POST http://localhost:3001/api/ask \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "List files in current directory",
    "workingDirectory": "/Users/user/project"
  }'
```

### JavaScript Example
```javascript
// Using fetch API
const response = await fetch('http://localhost:3001/api/ask', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    prompt: 'List files in current directory',
    workingDirectory: '/Users/user/project'
  })
});

const data = await response.json();
console.log(data.data.response);
```

### Swift Example
```swift
let url = URL(string: "http://localhost:3001/api/ask")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("Bearer YOUR_TOKEN", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let body = [
    "prompt": "List files in current directory",
    "workingDirectory": "/Users/user/project"
]
request.httpBody = try JSONEncoder().encode(body)

let (data, _) = try await URLSession.shared.data(for: request)
let response = try JSONDecoder().decode(ApiResponse.self, from: data)
```

---

**Last Updated**: 2025-07-27