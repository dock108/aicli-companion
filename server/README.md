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

# Push Notifications (optional)
APNS_CERT_PATH=./certs/apns-cert.pem
APNS_KEY_PATH=./certs/apns-key.pem
APNS_PASSPHRASE=your-passphrase
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

#### Projects
- `GET /api/projects` - List available projects
- `POST /api/projects/:name/start` - Start Claude session in project

#### Claude Interactions
- `POST /api/claude/ask` - One-time Claude query
- `GET /api/claude/sessions` - List active sessions
- `DELETE /api/claude/sessions/:id` - Close a session
- `GET /api/claude/status` - Check Claude Code availability

### WebSocket API

Connect to `/ws` for real-time communication:

```javascript
const ws = new WebSocket('wss://localhost:8765/ws');

// Authentication
ws.send(JSON.stringify({
  type: 'auth',
  token: 'your-auth-token'
}));

// Send message to Claude
ws.send(JSON.stringify({
  type: 'message',
  sessionId: 'session-123',
  content: 'Help me write a function'
}));

// Handle streaming chunks
ws.on('message', (data) => {
  const msg = JSON.parse(data);
  if (msg.type === 'streamChunk') {
    console.log('Chunk:', msg.chunk);
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
│   │   └── push-notification.js
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

3. **Service discovery not working**
   - Verify Bonjour/mDNS is enabled
   - Check network allows multicast
   - Try manual connection

4. **High memory usage**
   - Monitor with `/api/claude/sessions`
   - Sessions timeout after 30 minutes
   - Check for zombie processes

### Debug Commands

```bash
# Check Claude Code installation
which claude

# Test Claude directly
claude --version

# Check server logs
tail -f server.log

# Monitor processes
ps aux | grep claude
```

## Contributing

See [Contributing Guide](../CONTRIBUTING.md) for development guidelines.

## License

MIT - See [LICENSE](../LICENSE) for details.