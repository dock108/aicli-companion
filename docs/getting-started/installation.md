# Installation Guide

This guide will walk you through installing all components of AICLI Companion.

## Prerequisites

Before installing AICLI Companion, ensure you have:

- **macOS**: 12.0 or later (for development)
- **Node.js**: Version 18 or later
- **npm**: Version 8 or later
- **Xcode**: Version 15 or later (for iOS development)
- **Claude Code CLI**: Version 1.0.55 or later

## Installing Claude Code CLI

First, install the Claude Code CLI globally:

```bash
npm install -g @anthropic/claude-code
```

Verify the installation:
```bash
claude --version
```

## Installing the Companion Server

### Option 1: Global Installation (Recommended)

```bash
npm install -g claude-companion-server
```

### Option 2: From Source

1. Clone the repository:
```bash
git clone https://github.com/your-repo/claude-companion.git
cd claude-companion
```

2. Install dependencies:
```bash
npm install
```

3. Build the server:
```bash
cd server
npm install
npm run build
```

## Installing the iOS App

### From TestFlight (Coming Soon)
1. Download TestFlight from the App Store
2. Join the beta using the invitation link
3. Install AICLI Companion from TestFlight

### From Source (Development)

1. Navigate to the iOS directory:
```bash
cd ios
```

2. Install Swift dependencies:
```bash
swift package resolve
```

3. Open in Xcode:
```bash
open ClaudeCompanion.xcodeproj
```

4. Select your development team in project settings
5. Build and run on your device or simulator

## Installing the Desktop Host App

The desktop host app provides a GUI for managing the companion server:

1. Navigate to the host app directory:
```bash
cd server/hostapp
```

2. Install dependencies:
```bash
npm install
```

3. Install Rust (required for Tauri):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

4. Build the desktop app:
```bash
npm run tauri build
```

The installer will be created in `src-tauri/target/release/bundle/`.

## Post-Installation Setup

### 1. Generate Authentication Token

```bash
claude-companion-server --generate-token
```

Save this token - you'll need it to connect from the iOS app.

### 2. Configure Environment

Create a `.env` file in your server directory:

```env
PORT=3001
AUTH_TOKEN=your-generated-token
ENABLE_BONJOUR=true
```

### 3. Verify Installation

Start the server:
```bash
claude-companion-server
```

Check the health endpoint:
```bash
curl http://localhost:3001/health
```

## Platform-Specific Notes

### macOS
- Ensure firewall allows incoming connections to Node.js
- Grant necessary permissions for file access

### Windows (Experimental)
- Use PowerShell or Git Bash for commands
- Install Windows Build Tools for native dependencies
- Some features like Bonjour discovery may be limited

### Linux
- Install Avahi for mDNS support: `sudo apt-get install avahi-daemon`
- Ensure Node.js has necessary permissions

## Troubleshooting Installation

### Claude Code CLI not found
- Ensure npm global bin directory is in your PATH
- Try: `export PATH=$PATH:$(npm config get prefix)/bin`

### Permission Errors
- On macOS/Linux, you may need to use `sudo` for global installs
- Consider using a Node version manager like `nvm`

### Build Failures
- Ensure all prerequisites are installed
- Check for specific error messages in build output
- See the [troubleshooting guide](./troubleshooting.md) for common issues

## Next Steps

- Follow the [Quick Start Guide](./quickstart.md) to get up and running
- Read the [Architecture Overview](../architecture/overview.md) to understand the system
- Check the [API Documentation](../api/rest-api.md) for integration details

---

**Last Updated**: 2025-08-09