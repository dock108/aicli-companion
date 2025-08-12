# AICLI Companion

A comprehensive AI assistant integration system that brings Claude's capabilities to iOS through a modern, native experience. The system consists of three core components working seamlessly together.

## 🎯 Overview

AICLI Companion enables iOS users to interact with AI assistants (currently via Claude CLI) from their mobile devices, with full project context, push notification delivery, and persistent conversations. Perfect for developers who want to leverage AI assistance on the go.

### Core Components

1. **📱 iOS App** - Native SwiftUI application with modern chat interface
2. **🖥️ macOS Companion** - Menu bar app for server lifecycle management  
3. **🚀 Server** - Node.js backend bridging iOS app with Claude CLI

## ✨ Key Features

### iOS App
- **Modern Chat Interface**: Clean, intuitive design following iOS Human Interface Guidelines
- **Real-time Streaming**: See Claude's responses character-by-character as they're generated
- **Project Management**: Organize conversations by project with full context preservation
- **Message Persistence**: Never lose a conversation - all messages are synced with the server
- **Push Notifications**: Get notified when Claude completes long-running tasks
- **Rich Content Rendering**: Beautiful rendering of code blocks, markdown, and tool outputs
- **Offline Support**: Browse previous conversations even without connection
- **Attachment Support**: Send images, documents, and code files to Claude (up to 10MB)
- **Auto-Response Mode**: "Jesus Take the Wheel" mode for automated task continuation
- **Thinking Indicator**: Real-time progress with duration and token count display

### macOS Companion
- **Menu Bar Integration**: Always accessible from your menu bar
- **One-Click Server Control**: Start/stop server with a single click
- **Real-time Monitoring**: See active sessions, memory usage, and server health
- **Auto-Start Options**: Launch at login and auto-start server
- **Native Performance**: Built with SwiftUI for optimal macOS experience

### Server
- **Claude CLI Integration**: Seamless bridge to Claude via Claude CLI
- **HTTP + APNS**: Asynchronous message delivery via Apple Push Notifications
- **Session Management**: Active session tracking with timeout management
- **Security First**: Token authentication, TLS support, configurable permissions
- **Service Discovery**: Automatic discovery via Bonjour/mDNS
- **RESTful API**: Clean API for chat, sessions, and project management

## 🏗️ Architecture

```
aicli-companion/
├── ios/                    # iOS app (SwiftUI)
│   ├── Sources/           # Swift source code
│   ├── Tests/             # Unit tests
│   └── App/               # App configuration
├── macos-app/             # macOS companion app
│   ├── ClaudeCompanionHost/
│   └── Assets.xcassets/
├── server/                # Node.js backend
│   ├── src/               # Server source code
│   └── test/              # Server tests
└── docs/                  # Documentation
```

## 🚀 Quick Start

### Prerequisites

- **macOS 14.0+** (for development)
- **Xcode 15.0+**
- **Node.js 18+**
- **Claude CLI** installed and configured
- **iOS 16.0+** device or simulator

### 1. Clone and Setup

```bash
git clone https://github.com/your-username/claude-companion.git
cd claude-companion
```

### 2. Start the Server

```bash
cd server
npm install
npm start
```

The server will display:
- Port number (default: 3001)
- Authentication token (if auth enabled)
- Service discovery status

### 3. Launch macOS Companion

Open `macos-app/ClaudeCompanionHost.xcodeproj` in Xcode and run.

Or build from command line:
```bash
cd macos-app
swift build -c release
open .build/release/ClaudeCompanionHost.app
```

### 4. Run iOS App

Open `ios/AICLICompanion.xcodeproj` in Xcode:
1. Select your development team
2. Choose target device/simulator
3. Build and run (⌘R)

## ⚙️ Configuration

### Server Configuration

Create `.env` file in `server/` directory:

```env
# Server
PORT=3001
HOST=0.0.0.0
AUTH_REQUIRED=true
AUTH_TOKEN=your-secure-token

# Claude CLI
CLAUDE_SKIP_PERMISSIONS=false
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit,Bash

# Features
ENABLE_BONJOUR=true
ENABLE_TLS=false
MAX_ATTACHMENT_SIZE=10485760  # 10MB in bytes
TEMP_FILE_PATH=/tmp/claude-attachments

# APNS (for push notifications)
APNS_KEY_PATH=/path/to/key.p8
APNS_KEY_ID=your-key-id
APNS_TEAM_ID=your-team-id
APNS_BUNDLE_ID=com.claude.companion
APNS_PRODUCTION=false

# Paths
CONFIG_PATH=/path/to/projects
```

### macOS Companion Settings

Configure via the app's preferences:
- Server port
- Auto-start preferences
- Authentication settings
- Project directory path

### iOS App Configuration

In-app settings include:
- Server connection
- Notification preferences
- Appearance (light/dark/system)
- Message persistence options

## 🧪 Testing

```bash
# Run all tests
cd server && npm test

# Run with coverage
npm run test:coverage

# Lint code
npm run lint

# iOS tests (in Xcode)
⌘U or Product → Test
```

## 📚 Documentation

- [API Reference](./server/API.md)
- [Architecture Overview](./server/ARCHITECTURE.md)
- [iOS Integration Guide](./server/IOS_INTEGRATION_GUIDE.md)
- [Deployment Guide](./server/DEPLOYMENT.md)
- [Troubleshooting](./server/TROUBLESHOOTING.md)

## 🔒 Security

- **Authentication**: Token-based authentication for all connections
- **Encryption**: Optional TLS support for production deployments
- **Permissions**: Configurable AICLI tool permissions
- **Local First**: All data stays on your devices
- **No Telemetry**: Zero tracking or analytics

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built for use with [Anthropic's Claude](https://www.anthropic.com)
- Uses AICLI for Claude integration
- Inspired by the need for mobile AI assistance

## 📊 Status

- **Current Version**: 1.0.0
- **Status**: Production Ready
- **Last Updated**: January 2025

---

Made with ❤️ by the AICLI Companion team