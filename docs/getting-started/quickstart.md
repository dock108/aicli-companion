# Quick Start Guide

Get AICLI Companion up and running in 5 minutes!

## Prerequisites

- Claude Code CLI installed (`claude --version`)
- Node.js 18+ installed
- iOS device with iOS 17.0+
- Mac for running the companion server

## 1. Clone and Install

```bash
git clone https://github.com/your-repo/claude-companion.git
cd claude-companion
npm install
```

## 2. Start the Companion Server

```bash
cd server
npm start
```

You'll see:
```
🚀 AICLI Companion Server v1.0.0
🔐 Auth Token: abc123xyz...
📡 Server running on https://0.0.0.0:8765
🔍 Bonjour: _aiclicode._tcp
✅ Claude Code CLI found at: /usr/local/bin/claude
```

**Important**: Copy the auth token shown - you'll need it for the iOS app!

## 3. Build and Run the iOS App

### Option A: Using Xcode
```bash
cd ios
open AICLICompanion.xcodeproj
```

In Xcode:
1. Select your development team
2. Choose your device/simulator
3. Press ⌘R to build and run

### Option B: Using Xcodegen (if configured)
```bash
cd ios
xcodegen generate
open AICLICompanion.xcodeproj
```

## 4. Connect iOS App to Server

1. **Launch the app** on your iOS device
2. The app will automatically discover the server via Bonjour
3. **Tap on the discovered server** (shows as "AICLI Companion Server")
4. **Enter the auth token** from step 2
5. **Tap "Connect"**

## 5. Start Using Claude

1. **Select a Project**: Choose or create a project directory
2. **Start Chatting**: Type your first message
3. **Watch the Magic**: See Claude's responses stream in real-time

### Example First Commands

```
"What files are in this directory?"
"Explain the purpose of this project"
"Help me create a new React component"
"Run the tests and show me the results"
```

## Features to Try

### Real-time Streaming
Watch Claude's responses appear word by word as they're generated.

### Push Notifications
Get notified when Claude completes a long-running task.

### Session Persistence
Close the app and reopen - your conversation continues where you left off.

### Project Switching
Tap the project name to switch between different coding projects.

## Quick Configuration

### Server Environment Variables
Create `server/.env`:
```env
PORT=8765
REQUIRE_AUTH=true
ENABLE_TLS=true
CLAUDE_PERMISSION_MODE=relaxed
ENABLE_BONJOUR=true
```

### iOS App Settings
In the app, tap Settings to configure:
- Push notification preferences
- Auto-save intervals
- UI theme

## Using the Desktop Host App (Optional)

For easier server management:

```bash
cd server/hostapp
npm install
npm run tauri dev
```

This provides:
- Visual server status
- QR code for mobile connection
- Log viewing
- Easy start/stop controls

## Troubleshooting Quick Fixes

### Can't find server on iOS?
- Ensure both devices are on the same network
- Check firewall isn't blocking port 8765
- Try manual connection with IP address

### Claude Code not found?
```bash
export CLAUDE_CLI_PATH=/usr/local/bin/claude
```

### Permission errors?
Set relaxed permissions in `.env`:
```env
CLAUDE_PERMISSION_MODE=relaxed
CLAUDE_ALLOWED_TOOLS=read,write,edit,list
```

## What's Next?

- 📖 Read the [full documentation](../README.md)
- 🏗️ Understand the [architecture](../architecture/overview.md)
- 🔧 Learn about [advanced features](../features/streaming-and-notifications.md)
- 🚀 Deploy to [production](../operations/deployment.md)

## Need Help?

- 🐛 [Report issues](https://github.com/your-repo/claude-companion/issues)
- 💬 [Join discussions](https://github.com/your-repo/claude-companion/discussions)
- 📚 [Full documentation](../README.md)

---

**Happy Coding with Claude! 🚀**

*Last Updated: 2025-08-09*