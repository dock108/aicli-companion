# Companion Server Architecture

The Claude Companion Server is a Node.js application that bridges mobile clients with the Claude Code CLI, providing a secure and scalable API gateway.

## Server Components

```
┌─────────────────────────────────────────────────┐
│              Companion Server                    │
├─────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  HTTP    │  │WebSocket │  │   Service    │  │
│  │  Server  │  │  Server  │  │  Discovery   │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │             │                │          │
│  ┌────▼─────────────▼────────────────▼───────┐  │
│  │         Request Router & Auth              │  │
│  └────────────────┬───────────────────────────┘  │
│                   │                               │
│  ┌────────────────▼───────────────────────────┐  │
│  │          Session Manager                   │  │
│  └────────────────┬───────────────────────────┘  │
│                   │                               │
│  ┌────────────────▼───────────────────────────┐  │
│  │      Claude Process Manager                │  │
│  └────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Core Features

### HTTP REST API
- **One-time queries**: Send prompts and receive complete responses
- **Session management**: Create, list, and manage streaming sessions
- **Health monitoring**: Server and Claude CLI status endpoints
- **Permission handling**: Respond to Claude permission prompts

### WebSocket API
- **Real-time streaming**: Bidirectional communication with clients
- **Session persistence**: Maintain conversation context
- **Event broadcasting**: Notify clients of session updates
- **Connection management**: Handle reconnections gracefully

### Service Discovery
- **Bonjour/mDNS**: Automatic server discovery on local networks
- **Service broadcasting**: Advertise server availability
- **Network details**: Include IP, port, and capabilities
- **Zero-configuration**: Works without manual setup

## Session Architecture

### Session Lifecycle

```
┌─────────┐     ┌──────────┐     ┌─────────┐     ┌────────┐
│ Created │────▶│  Active  │────▶│  Idle   │────▶│ Closed │
└─────────┘     └──────────┘     └─────────┘     └────────┘
                      │                │
                      └────────────────┘
                       Keep-alive ping
```

### Session Components
- **Session ID**: Unique identifier (UUID v4)
- **Claude Process**: Dedicated CLI process per session
- **Message Queue**: Buffered input/output streams
- **Metadata**: Creation time, last activity, message count
- **State Machine**: Tracks session status transitions

## Process Management

### Claude CLI Integration
```javascript
class ClaudeProcess {
  - spawn(): Create new Claude process
  - write(): Send input to Claude
  - read(): Stream output from Claude
  - kill(): Terminate process gracefully
  - monitor(): Track resource usage
}
```

### Process Pool
- **Reuse Strategy**: Keep processes warm for performance
- **Resource Limits**: CPU and memory monitoring
- **Graceful Shutdown**: Clean termination on timeout
- **Error Recovery**: Automatic restart on crashes

## Authentication & Security

### Token-Based Auth
```
Client Request
    │
    ├─ Header: Authorization: Bearer <token>
    │  OR
    └─ Query: ?token=<token>
         │
         ▼
    Middleware validates token
         │
         ├─ Valid ──▶ Process request
         │
         └─ Invalid ──▶ 401 Unauthorized
```

### Security Measures
- **Token Generation**: Cryptographically secure random tokens
- **TLS Support**: Automatic certificate generation
- **CORS Configuration**: Restricted origins
- **Input Validation**: Sanitize all inputs
- **Rate Limiting**: Prevent abuse

## Configuration

### Environment Variables
```env
# Server Configuration
PORT=3001                    # Server port
HOST=0.0.0.0                # Bind address
NODE_ENV=production         # Environment

# Authentication
AUTH_TOKEN=<secure-token>   # Required for connections

# Claude CLI
CLAUDE_CLI_PATH=claude      # Path to Claude executable
CLAUDE_TIMEOUT=300000       # Process timeout (5 min)

# Permissions
CLAUDE_PERMISSION_MODE=default
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit
CLAUDE_SKIP_PERMISSIONS=false

# Features
ENABLE_BONJOUR=true         # Service discovery
MAX_SESSIONS=5              # Concurrent sessions
SESSION_TIMEOUT=1800000     # 30 minutes
```

### Permission Modes
- **default**: Normal permission prompts
- **acceptEdits**: Auto-accept file edits
- **bypassPermissions**: Skip specific checks
- **plan**: Planning mode before changes

## API Endpoints

### REST Endpoints
```
GET  /health                 # Server health check
GET  /api/info              # Server information
POST /api/ask               # One-time query
POST /api/stream/start      # Start streaming session
POST /api/stream/:id        # Send to session
DELETE /api/stream/:id      # Close session
GET  /api/sessions          # List active sessions
POST /api/permission/:id    # Permission response
GET  /api/claude/status     # Claude CLI status
POST /api/claude/test       # Test Claude CLI
```

### WebSocket Events
```
Client → Server:
- ask              # One-time query
- streamStart      # Begin streaming
- streamSend       # Continue conversation
- streamClose      # End session
- permission       # Permission response
- ping             # Keep-alive

Server → Client:
- welcome          # Connection established
- askResponse      # Query result
- streamStarted    # Session created
- streamData       # Streaming content
- streamToolUse    # Tool execution
- permissionRequest # Need permission
- streamComplete   # Session finished
- error            # Error occurred
- pong             # Keep-alive response
```

## Error Handling

### Error Categories
1. **Connection Errors**: Network issues, auth failures
2. **Process Errors**: Claude CLI failures, timeouts
3. **Session Errors**: Invalid session, resource limits
4. **Permission Errors**: Denied operations
5. **System Errors**: Server issues, out of memory

### Error Response Format
```json
{
  "type": "error",
  "requestId": "req_12345",
  "data": {
    "code": "CLAUDE_UNAVAILABLE",
    "message": "Claude Code CLI not found",
    "details": {
      "originalError": "spawn claude ENOENT",
      "suggestion": "Install Claude Code CLI"
    }
  }
}
```

## Performance Optimization

### Caching Strategy
- **Session Reuse**: Keep warm processes
- **Response Buffering**: Optimize streaming
- **Connection Pooling**: Reuse WebSocket connections

### Resource Management
- **Memory Limits**: Per-session restrictions
- **CPU Monitoring**: Prevent runaway processes
- **Disk Usage**: Temporary file cleanup
- **Network Throttling**: Bandwidth limits

## Monitoring & Logging

### Health Checks
```javascript
GET /health
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime": 3600,
  "claude": {
    "available": true,
    "version": "1.0.55"
  },
  "sessions": {
    "active": 2,
    "max": 5
  }
}
```

### Logging Strategy
- **Structured Logs**: JSON format
- **Log Levels**: error, warn, info, debug
- **Request Logging**: Morgan middleware
- **Error Tracking**: Stack traces and context
- **Performance Metrics**: Response times

## Deployment Considerations

### Production Setup
1. Use process manager (PM2, systemd)
2. Enable TLS with proper certificates
3. Configure firewall rules
4. Set up monitoring alerts
5. Implement backup strategy

### Scaling Options
- **Vertical**: Increase server resources
- **Horizontal**: Load balancer + multiple instances
- **Session Affinity**: Sticky sessions for WebSocket
- **Redis**: Shared session state (future)

---

**Last Updated**: 2025-07-27