# Claude Companion

A mobile companion app for Anthropic's Claude Code CLI, enabling iOS users to interact with Claude Code remotely through an intuitive chat interface.

## Overview

Claude Companion consists of three main components:
- **iOS App**: Native SwiftUI application for iPhone and iPad
- **Companion Server**: Node.js server that bridges the iOS app with Claude Code CLI
- **Host App**: Tauri-based desktop application for easy server management

## Features

- 📱 **Native iOS Experience**: Built with SwiftUI for smooth, responsive interactions
- 🔄 **Real-time Streaming**: See Claude's responses as they're generated
- 📂 **Project Management**: Switch between different coding projects seamlessly
- 🔔 **Push Notifications**: Get notified when Claude completes a response
- 💾 **Session Persistence**: Continue conversations across app launches
- 🔒 **Secure Communication**: TLS encryption and token-based authentication
- 🔍 **Service Discovery**: Automatic server detection via Bonjour/mDNS
- 🌐 **WebSocket Support**: Real-time bidirectional communication

## Project Structure

```
claude-companion/
├── ios/                    # iOS app (SwiftUI)
│   ├── Sources/           # Swift source code
│   ├── Tests/             # Unit tests
│   └── App/               # App configuration
├── server/                # Companion server (Node.js)
│   ├── src/               # Server source code
│   ├── test/              # Server tests
│   └── hostapp/           # Tauri desktop app
├── docs/                  # Documentation
│   ├── api/               # API documentation
│   ├── architecture/      # Architecture guides
│   ├── development/       # Development guides
│   └── getting-started/   # Quick start guides
└── tests/                 # Integration tests
```

## Requirements

- **iOS Development**: 
  - Xcode 15+
  - iOS 17.0+ deployment target
  - macOS 13+ for development
- **Server Development**: 
  - Node.js 18+
  - npm or yarn
- **Claude Code CLI**: 
  - Version 1.0.55 or later
  - Valid API key

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/your-repo/claude-companion.git
cd claude-companion
npm install
```

### 2. Start the Companion Server
```bash
cd server
npm install
npm start
```

The server will:
- Generate an authentication token
- Start on port 8765 (configurable)
- Enable TLS if certificates are available
- Broadcast via Bonjour for iOS discovery

### 3. Build and Run the iOS App
```bash
cd ios
open AICLICompanion.xcodeproj
```

In Xcode:
1. Select your development team
2. Choose your target device/simulator
3. Build and run (⌘R)

### 4. Connect and Start Coding
1. The iOS app will automatically discover the server
2. Enter the authentication token displayed by the server
3. Select a project directory
4. Start chatting with Claude!

## Configuration

### Server Configuration
Create a `.env` file in the `server` directory:

```env
# Server settings
PORT=8765
HOST=0.0.0.0
NODE_ENV=development

# Security
REQUIRE_AUTH=true
ENABLE_TLS=true

# Claude Code settings
CLAUDE_CLI_PATH=/usr/local/bin/claude
CLAUDE_PERMISSION_MODE=relaxed
CLAUDE_ALLOWED_TOOLS=read,write,list

# Service discovery
ENABLE_BONJOUR=true
```

### iOS App Settings
Configure in the Settings tab:
- Server connection preferences
- Notification settings
- Session persistence options
- UI customization

## Development

### Running Tests

```bash
# All tests
npm test

# Server tests only
npm run test:server

# iOS tests
npm run test:ios

# Integration tests
cd tests/integration
npm test
```

### Code Quality

```bash
# Linting
npm run lint

# Format code
npm run format

# Type checking (TypeScript)
npm run typecheck
```

## Documentation

- [Installation Guide](./docs/getting-started/installation.md)
- [API Reference](./docs/api/rest-api.md)
- [Architecture Overview](./docs/architecture/overview.md)
- [Contributing Guide](./docs/development/contributing.md)
- [Troubleshooting](./docs/getting-started/troubleshooting.md)

## Security

- All communication is encrypted with TLS
- Token-based authentication required by default
- No data stored on third-party servers
- API keys remain on the host machine
- Configurable permission modes for Claude Code access

## License

MIT License - See [LICENSE](LICENSE) file for details

## Contributing

We welcome contributions! Please see our [Contributing Guide](./docs/development/contributing.md) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/your-repo/claude-companion/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-repo/claude-companion/discussions)
- **Documentation**: [Full Documentation](./docs/README.md)

---

**Current Version**: 1.0.0  
**Last Updated**: 2025-07-30