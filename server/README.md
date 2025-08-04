# Claude Companion Server

The Node.js companion server that bridges the Claude Companion iOS app with Claude Code CLI.

## Overview

This server provides:
- WebSocket connection for real-time communication with iOS clients
- REST API for one-time queries and project management
- Claude Code CLI integration with streaming support
- Service discovery via Bonjour/mDNS
- TLS encryption and token-based authentication
- Push notification support for iOS devices
- Session deduplication and persistence
- Message queue with reliable delivery
- WebSocket reconnection support
- Comprehensive telemetry and monitoring
- Connection state persistence

## Installation

```bash
cd server
npm install
```

## Configuration

### Environment Variables

Create a `.env` file in the server directory:

```env
# Server Configuration
PORT=8765                    # Server port (default: 8765)
HOST=0.0.0.0                # Host to bind to
NODE_ENV=development        # Environment (development/production)

# Security
REQUIRE_AUTH=true           # Require authentication token
ENABLE_TLS=true            # Enable TLS/SSL
TLS_CERT_PATH=./certs/server.crt
TLS_KEY_PATH=./certs/server.key

# Claude Code Configuration
CLAUDE_CLI_PATH=/usr/local/bin/claude    # Path to Claude CLI
CLAUDE_PERMISSION_MODE=relaxed           # Permission mode: strict/relaxed/custom
CLAUDE_ALLOWED_TOOLS=read,write,list     # Allowed tools (comma-separated)
CLAUDE_SKIP_PERMISSIONS=false            # Skip permission prompts

# Service Discovery
ENABLE_BONJOUR=true         # Enable Bonjour/mDNS broadcasting

# Session Management
SESSION_TIMEOUT=86400000              # Session timeout in ms (24 hours)
MAX_SESSIONS_PER_CLIENT=5             # Max concurrent sessions per client
SESSION_CLEANUP_INTERVAL=3600000      # Cleanup interval in ms (1 hour)

# WebSocket Configuration
WS_HEARTBEAT_INTERVAL=30000           # Heartbeat interval in ms
WS_CONNECTION_TIMEOUT=60000           # Connection timeout in ms
MAX_WEBSOCKET_CONNECTIONS=1000        # Max concurrent connections

# Message Queue
MESSAGE_QUEUE_MAX_SIZE=1000           # Max messages per session
MESSAGE_RETENTION_PERIOD=3600000      # Message retention in ms (1 hour)

# Telemetry
TELEMETRY_ENABLED=true                # Enable telemetry collection
TELEMETRY_RETENTION_PERIOD=604800000  # Telemetry retention (7 days)

# Connection State
CONNECTION_STATE_STORAGE=memory       # Storage type: memory/redis/file
CONNECTION_STATE_TTL=86400000         # Connection state TTL (24 hours)

# Push Notifications (optional)
APNS_CERT_PATH=./certs/apns-cert.pem
APNS_KEY_PATH=./certs/apns-key.pem
APNS_PASSPHRASE=your-passphrase
APNS_BUNDLE_ID=com.yourcompany.claudecompanion
```

### Permission Modes

Configure how Claude Code handles permissions:

- **`strict`**: All operations require explicit approval
- **`relaxed`**: Basic file operations auto-approved
- **`custom`**: Use CLAUDE_ALLOWED_TOOLS to specify

### TLS Setup

For secure connections, place your certificates in the `certs` directory:

```bash
mkdir certs
# Place server.crt and server.key in this directory
```

For development, you can generate self-signed certificates:

```bash
cd certs
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes
```

## Running the Server

### Development
```bash
npm run dev    # Runs with nodemon for auto-restart
```

### Production
```bash
npm start
```

### With Custom Configuration
```bash
PORT=3000 REQUIRE_AUTH=false npm start
```

### Using the Desktop App
```bash
cd hostapp
npm run tauri dev    # Development
npm run tauri build  # Build desktop app
```

## API Endpoints

### REST API

#### Health & Info
- `GET /health` - Server health check
- `GET /api/info` - Server information and capabilities

#### Session Management
- `GET /api/sessions` - List all active sessions
- `GET /api/sessions/:sessionId` - Get session details
- `POST /api/sessions/continue` - Continue existing session (iOS)

#### Projects
- `GET /api/projects` - List available projects
- `POST /api/projects/:name/start` - Start Claude session in project

#### Claude Interactions
- `POST /api/claude/ask` - One-time Claude query
- `GET /api/claude/sessions` - List active sessions
- `DELETE /api/claude/sessions/:id` - Close a session
- `GET /api/claude/status` - Check Claude Code availability
- `POST /api/claude/test` - Test Claude with simple prompt

#### Telemetry
- `GET /api/telemetry` - Get comprehensive metrics
- `GET /api/telemetry/connection/:clientId` - Get connection metrics
- `POST /api/telemetry/reset` - Reset all metrics (admin)

#### Push Notifications
- `GET /api/push-notifications/stats` - Get notification statistics
- `POST /api/push-notifications/test` - Send test notification
- `DELETE /api/push-notifications/bad-tokens` - Clear bad tokens

### WebSocket API

Connect to `/ws` for real-time communication:

```javascript
const ws = new WebSocket('wss://localhost:8765/ws?token=your-auth-token');

// Set device ID header for reconnection support
ws.headers = { 'x-device-id': 'unique-device-id' };

// Subscribe to events
ws.send(JSON.stringify({
  type: 'subscribe',
  requestId: 'req-123',
  data: {
    events: ['assistantMessage', 'streamData', 'sessionStatus']
  }
}));

// Send message to Claude
ws.send(JSON.stringify({
  type: 'sendCommand',
  requestId: 'req-456',
  data: {
    sessionId: 'session-123',
    prompt: 'Help me write a function'
  }
}));

// Register for push notifications (iOS)
ws.send(JSON.stringify({
  type: 'registerDevice',
  requestId: 'req-789',
  data: {
    deviceToken: 'apns-device-token',
    deviceInfo: 'ios'
  }
}));

// Handle messages
ws.on('message', (data) => {
  const msg = JSON.parse(data);
  switch (msg.type) {
    case 'welcome':
      console.log('Connected:', msg.data);
      break;
    case 'streamData':
      console.log('Stream chunk:', msg.data.chunk);
      break;
    case 'assistantMessage':
      console.log('Complete response:', msg.data.content);
      break;
    case 'error':
      console.error('Error:', msg.data.error);
      break;
  }
});
```

## Architecture

```
server/
├── src/
│   ├── index.js              # Main server entry point
│   ├── config/               # Configuration modules
│   │   ├── middleware-config.js
│   │   ├── server-config.js
│   │   └── tls-config.js
│   ├── middleware/           # Express middleware
│   │   ├── auth.js          # Authentication
│   │   └── error.js         # Error handling
│   ├── routes/              # REST API routes
│   │   ├── index.js         # Main routes
│   │   ├── projects.js      # Project management
│   │   └── aicli-status.js  # Claude status
│   ├── services/            # Core services
│   │   ├── aicli.js         # Claude Code integration
│   │   ├── websocket.js     # WebSocket handling
│   │   ├── discovery.js     # Bonjour/mDNS
│   │   ├── stream-parser.js # Response streaming
│   │   ├── push-notification.js
│   │   ├── message-queue.js # Message queue management
│   │   ├── session-persistence.js # Session persistence
│   │   ├── connection-state-manager.js # Connection state
│   │   └── telemetry.js     # Performance monitoring
│   └── utils/               # Utility functions
├── test/                    # Test files
├── certs/                   # TLS certificates
└── hostapp/                # Tauri desktop app
```

## Core Services

### AICLI Service
Manages Claude Code CLI processes and sessions:
- Process lifecycle management
- Session state tracking
- Permission handling
- Output streaming

### WebSocket Service
Real-time communication with iOS clients:
- Authentication handling
- Message routing
- Event broadcasting
- Connection management

### Stream Parser Service
Parses Claude's output into structured chunks:
- Markdown parsing
- Code block detection
- Section identification
- Chunk metadata
- Empty chunk filtering

### Discovery Service
Broadcasts server availability:
- Bonjour/mDNS registration
- Service type: `_aiclicode._tcp`
- Automatic network discovery

### Push Notification Service
iOS push notification support:
- APNS integration
- Notification on completion
- Rich notification content
- Retry logic with exponential backoff
- Bad token management
- Batch notification sending

### Message Queue Service
Reliable message delivery:
- Per-session message queuing
- Delivery tracking by client
- Automatic expiration
- Message validation and filtering
- Metadata enrichment

### Session Persistence Service
Session state management:
- In-memory session cache
- Session deduplication by working directory
- Activity tracking
- Automatic cleanup of expired sessions

### Connection State Manager
WebSocket connection persistence:
- Client fingerprinting
- Connection history tracking
- Automatic session restoration
- Support for Redis/file storage (future)

### Telemetry Service
Performance monitoring:
- WebSocket connection metrics
- Session lifecycle tracking
- Message queue statistics
- Performance timings
- Error rate monitoring

## Testing

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage
```

### Note

Tests run with `--experimental-test-isolation=none` to support EventEmitter-based tests. This requires Node.js v22.8.0 or higher for the isolation flag.

## Development

### Code Quality

```bash
# Linting
npm run lint
npm run lint:fix

# Formatting
npm run format
```

### Debugging

Enable debug logging:
```bash
DEBUG=* npm run dev
```

### Manual Testing

Test scripts are available:
```bash
node manual-tests/test-websocket.js
node manual-tests/test-streaming.js
```

## Security Considerations

1. **Authentication**: Token-based auth enabled by default
2. **TLS**: Use proper certificates in production
3. **Permissions**: Configure Claude Code access carefully
4. **Network**: Bind to specific interfaces in production
5. **CORS**: Configure allowed origins appropriately

## Troubleshooting

### Common Issues

1. **Claude Code not found**
   ```bash
   # Set path explicitly
   export CLAUDE_CLI_PATH=/usr/local/bin/claude
   ```

2. **WebSocket connection fails**
   - Check firewall settings
   - Verify TLS certificates
   - Ensure authentication token matches
   - Include x-device-id header for reconnection

3. **Service discovery not working**
   - Verify Bonjour/mDNS is enabled
   - Check network allows multicast
   - Try manual connection

4. **High memory usage**
   - Monitor with `/api/telemetry`
   - Check session count: `/api/sessions`
   - Sessions timeout after SESSION_TIMEOUT
   - Enable session cleanup logs

5. **Duplicate sessions created**
   - Check session deduplication logs
   - Verify working directory paths match
   - Monitor with `/api/sessions`

6. **Empty/blank messages**
   - Check telemetry for filtered messages
   - Verify stream chunk validation is working
   - Look for "Filtering empty stream chunk" in logs

7. **Push notifications not working**
   - Check APNS certificate validity
   - Monitor `/api/push-notifications/stats`
   - Clear bad tokens if needed
   - Verify device registration in logs

### Debug Commands

```bash
# Check Claude Code installation
which claude

# Test Claude directly
claude --version

# Check server logs
pm2 logs claude-companion-server

# Monitor processes
ps aux | grep claude

# View telemetry
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/api/telemetry | jq

# Check active sessions
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/api/sessions | jq

# Test WebSocket connection
wscat -H "x-device-id: test-device" -c "ws://localhost:3001/ws?token=YOUR_TOKEN"
```

### Additional Resources

- [API Documentation](./API.md) - Complete API reference
- [Deployment Guide](./DEPLOYMENT.md) - Production deployment
- [Troubleshooting Guide](./TROUBLESHOOTING.md) - Detailed troubleshooting
- [Architecture](./ARCHITECTURE.md) - System design and internals

## Contributing

See [Contributing Guide](../CONTRIBUTING.md) for development guidelines.

## License

MIT - See [LICENSE](../LICENSE) for details.