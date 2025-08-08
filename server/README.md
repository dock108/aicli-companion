# Claude Companion Server

The Node.js backend server that bridges the Claude Companion iOS app with AICLI, providing real-time communication, session management, and intelligent message handling.

## Overview

This server provides:
- WebSocket connection for real-time communication with iOS clients
- REST API for project management and configuration
- AICLI integration with streaming support
- Service discovery via Bonjour/mDNS
- TLS encryption and token-based authentication
- Push notification support for iOS devices
- Session persistence with message history
- Message queue with reliable delivery
- WebSocket reconnection support
- Comprehensive telemetry and monitoring
- Connection state management

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
PORT=3001                    # Server port (default: 3001)
HOST=0.0.0.0                # Host to bind to
NODE_ENV=development        # Environment (development/production)
CONFIG_PATH=/path/to/projects  # Base path for project directories

# Security
AUTH_REQUIRED=true          # Require authentication token
AUTH_TOKEN=your-token-here  # Authentication token
ENABLE_TLS=false           # Enable TLS/SSL (set true for production)
TLS_CERT_PATH=./certs/server.crt
TLS_KEY_PATH=./certs/server.key

# AICLI Configuration
CLAUDE_SKIP_PERMISSIONS=false            # Skip permission prompts
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit,Bash # Allowed tools (comma-separated)

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

### AICLI Tool Permissions

Configure which tools AICLI can use:

- **`Read`**: Read file contents
- **`Write`**: Create new files
- **`Edit`**: Modify existing files
- **`Bash`**: Execute shell commands

Set `CLAUDE_SKIP_PERMISSIONS=true` to auto-approve all tool use (use with caution).

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

### Using the macOS Companion App
The macOS companion app provides a convenient menu bar interface for managing the server. See the [macOS app documentation](../macos-app/README.md) for details.

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

#### AICLI Interactions
- `POST /api/aicli/ask` - One-time AICLI query
- `GET /api/aicli/sessions` - List active sessions
- `DELETE /api/aicli/sessions/:id` - Close a session
- `GET /api/aicli/status` - Check AICLI availability
- `POST /api/aicli/test` - Test AICLI with simple prompt

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
│   │   ├── aicli.js         # AICLI integration
│   │   ├── websocket.js     # WebSocket handling
│   │   ├── discovery.js     # Bonjour/mDNS
│   │   ├── stream-parser.js # Response streaming
│   │   ├── push-notification.js # iOS notifications
│   │   ├── message-queue.js # Message queue management
│   │   ├── session-persistence.js # Session & message persistence
│   │   ├── connection-state-manager.js # Connection state
│   │   └── telemetry.js     # Performance monitoring
│   └── utils/               # Utility functions
├── test/                    # Test files
└── certs/                   # TLS certificates
```

## Core Services

### AICLI Service
Manages AICLI processes and sessions:
- Process lifecycle management
- Session state tracking with persistence
- Tool permission handling
- Output streaming with parsing
- Message buffer management

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
Session and message persistence:
- In-memory session cache with disk backup
- Message buffer persistence for conversation history
- Session metadata tracking
- Automatic cleanup of expired sessions
- Message history API for client sync

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

1. **AICLI not found**
   ```bash
   # Ensure AICLI is installed and in PATH
   which aicli
   # or
   which claude
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
# Check AICLI installation
which aicli || which claude

# Test AICLI directly
aicli --version || claude --version

# Check server logs
npm run dev  # For development logs

# Monitor processes
ps aux | grep -E "aicli|claude|node"

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