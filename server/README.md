# Claude Companion Server

A Node.js companion server that provides HTTP and WebSocket APIs for connecting mobile devices to Claude Code CLI.

## Features

- **HTTP REST API** for one-time Claude Code interactions
- **WebSocket API** for real-time streaming conversations
- **Bonjour/mDNS discovery** for automatic server detection on local networks
- **Authentication support** with token-based security
- **Session management** for maintaining conversation context
- **Permission handling** for interactive Claude Code prompts
- **Process monitoring** for resource management

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

# Claude CLI Permission Configuration
# Note: Claude CLI uses camelCase for permission flags (--allowedTools, not --allowed-tools)
CLAUDE_PERMISSION_MODE=default  # Options: default, acceptEdits, bypassPermissions, plan
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit  # Comma-separated list of allowed tools (default: Read,Write,Edit)
CLAUDE_DISALLOWED_TOOLS=Bash(rm:*),Bash(sudo:*)  # Comma-separated list of disallowed tools
CLAUDE_SKIP_PERMISSIONS=false  # Set to 'true' to use --dangerously-skip-permissions (use with caution)
```

### Permission Configuration

The server supports configuring Claude CLI permission settings to reduce permission prompts:

- **CLAUDE_PERMISSION_MODE**: Controls how Claude handles permissions
  - `default`: Normal permission prompts
  - `acceptEdits`: Automatically accept file edits
  - `bypassPermissions`: Skip all permission checks (use with caution)
  - `plan`: Enter planning mode before making changes

- **CLAUDE_ALLOWED_TOOLS**: Pre-approve specific tools
  - Default: `Read,Write,Edit` (basic file operations)
  - Example: `Bash,Edit,Read,Write` (includes bash commands)
  - Reduces permission prompts for common operations

- **CLAUDE_DISALLOWED_TOOLS**: Block specific tool patterns
  - Example: `Bash(rm:*),Bash(sudo:*)` blocks dangerous commands
  - Adds safety restrictions

- **CLAUDE_SKIP_PERMISSIONS**: Bypass all permission checks
  - Set to `true` to use `--dangerously-skip-permissions`
  - Only use in trusted, sandboxed environments
  - Useful for automated workflows

### Command Line Options

```bash
# Start with custom port
PORT=8080 npm start

# Start with authentication
AUTH_TOKEN=my-secret-token npm start

# Start with custom Claude path
CLAUDE_CLI_PATH=/usr/local/bin/claude npm start
```

## API Endpoints

### HTTP REST API

- `GET /health` - Health check
- `GET /api/info` - Server information
- `POST /api/ask` - Send prompt to Claude Code
- `POST /api/stream/start` - Start streaming session
- `POST /api/stream/:sessionId` - Send to existing session
- `DELETE /api/stream/:sessionId` - Close session
- `GET /api/sessions` - List active sessions
- `POST /api/permission/:sessionId` - Respond to permission prompts

### WebSocket API

Connect to `/ws` with authentication token in query string:
```
ws://localhost:3001/ws?token=your-auth-token
```

Message types:
- `askClaude` - Send prompt
- `continueSession` - Continue existing session
- `closeSession` - Close session
- `permission` - Respond to permission prompt

## Security

### Authentication
- Token-based authentication for all endpoints
- Token can be provided via:
  - Query parameter: `?token=your-token`
  - Authorization header: `Authorization: Bearer your-token`

### TLS/SSL
- Automatic self-signed certificate generation
- Custom certificates supported via `certs/` directory

### CORS
- Configurable allowed origins
- Credentials support for authenticated requests

## Development

### Testing
```bash
npm test                 # Run tests
npm run test:coverage    # Run with coverage
npm run test:watch       # Watch mode
```

### Linting
```bash
npm run lint             # Check code style
npm run lint:fix         # Fix code style issues
```

### Desktop App
```bash
npm run hostapp          # Run Tauri desktop app
npm run hostapp:build    # Build desktop app
```

## Troubleshooting

### Claude CLI not found
- Ensure Claude CLI is installed: `npm install -g @anthropic/claude-code`
- Set custom path: `CLAUDE_CLI_PATH=/path/to/claude npm start`

### Permission denied errors
- Check file permissions in working directory
- Use `CLAUDE_ALLOWED_TOOLS` to pre-approve tools
- Consider `CLAUDE_SKIP_PERMISSIONS=true` for trusted environments

### High memory usage
- Monitor active sessions with `/api/sessions`
- Sessions timeout after 30 minutes of inactivity
- Process health monitoring alerts on high resource usage

## License

MIT License - See LICENSE file for details