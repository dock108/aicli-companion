# Claude Companion Server

A Node.js companion server that provides HTTP and WebSocket APIs for connecting mobile devices to Claude Code CLI.

## Features

- **HTTP REST API** for one-time Claude Code interactions
- **WebSocket API** for real-time streaming conversations
- **Bonjour/mDNS discovery** for automatic server detection on local networks
- **Authentication support** with token-based security
- **Session management** for maintaining conversation context
- **Permission handling** for interactive Claude Code prompts

## Installation

### Option 1: Global Installation
```bash
npm install -g claude-companion-server
claude-companion-server
```

### Option 2: Local Development
```bash
git clone <repository>
cd server
npm install
npm start
```

## Configuration

### Environment Variables

Create a `.env` file in the server directory:

```env
# Server configuration
PORT=3001
HOST=0.0.0.0

# Authentication (optional but recommended)
AUTH_TOKEN=your-secret-token-here

# CORS settings
ALLOWED_ORIGINS=http://localhost:3000,https://your-domain.com

# Features
ENABLE_BONJOUR=true
```

### Command Line Options

```bash
# Start with custom port
PORT=8080 npm start

# Start with authentication
AUTH_TOKEN=mysecrettoken npm start

# Disable Bonjour discovery
ENABLE_BONJOUR=false npm start
```

## API Reference

### REST Endpoints

#### Health Check
```http
GET /health
```
Returns server and Claude Code status.

#### Send Prompt
```http
POST /api/ask
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "prompt": "List files in current directory",
  "workingDirectory": "/path/to/project",
  "format": "json"
}
```

#### Start Streaming Session
```http
POST /api/stream/start
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "prompt": "Help me debug this code",
  "workingDirectory": "/path/to/project"
}
```

#### Send to Streaming Session
```http
POST /api/stream/{sessionId}
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "prompt": "Continue with the next step"
}
```

#### Handle Permission Prompt
```http
POST /api/permission/{sessionId}
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "response": "y"
}
```

### WebSocket API

Connect to `ws://localhost:3001/ws?token=YOUR_TOKEN`

#### Message Types

**Send Prompt:**
```json
{
  "type": "ask",
  "prompt": "Your question",
  "workingDirectory": "/path/to/project",
  "requestId": "unique-id"
}
```

**Start Streaming:**
```json
{
  "type": "streamStart",
  "prompt": "Your question",
  "workingDirectory": "/path/to/project",
  "requestId": "unique-id"
}
```

**Stream Response:**
```json
{
  "type": "streamSend",
  "sessionId": "session-uuid",
  "prompt": "Follow-up question",
  "requestId": "unique-id"
}
```

**Permission Response:**
```json
{
  "type": "permission",
  "sessionId": "session-uuid",
  "response": "y",
  "requestId": "unique-id"
}
```

## Security

### Authentication

The server supports token-based authentication. Set the `AUTH_TOKEN` environment variable to enable it:

```bash
AUTH_TOKEN=your-secure-token npm start
```

Clients must include the token in requests:
- HTTP: `Authorization: Bearer YOUR_TOKEN` header
- WebSocket: `?token=YOUR_TOKEN` query parameter

### Network Security

- **Local Network**: The server binds to `0.0.0.0` by default, allowing connections from other devices on the local network
- **Internet Access**: To expose over the internet, use a reverse proxy with TLS termination (nginx, Cloudflare Tunnel, etc.)
- **Firewall**: Consider restricting access to specific IP ranges if needed

## Mobile App Integration

### Discovery

The server advertises itself via Bonjour/mDNS:
- Service Type: `_claudecode._tcp`
- Service Name: `Claude Companion Server`
- Port: Configured port (default 3001)

iOS apps can discover the server using `NetServiceBrowser`.

### Connection Flow

1. **Discovery**: App scans for local servers
2. **Connection**: App connects to HTTP/WebSocket endpoints
3. **Authentication**: App provides auth token if required
4. **Usage**: App sends prompts and receives responses

## Troubleshooting

### Claude Code Not Found

```
⚠️  Claude Code CLI not found. Server will start but functionality will be limited.
```

**Solution**: Ensure Claude Code is installed and available in PATH:
```bash
which claude
claude --version
```

### Permission Denied

```
Error: spawn claude EACCES
```

**Solution**: Ensure Claude Code is executable:
```bash
chmod +x $(which claude)
```

### Port Already in Use

```
Error: listen EADDRINUSE :::3001
```

**Solution**: Use a different port:
```bash
PORT=3002 npm start
```

### Bonjour Issues on Linux

```
⚠️  Bonjour setup failed
```

**Solution**: Install Avahi daemon:
```bash
# Ubuntu/Debian
sudo apt-get install avahi-daemon

# CentOS/RHEL
sudo yum install avahi-daemon
```

## Development

### Running in Development Mode

```bash
npm run dev  # Uses nodemon for auto-restart
```

### Testing

```bash
npm test
```

### Linting

```bash
npm run lint
```

## License

MIT License - see LICENSE file for details.