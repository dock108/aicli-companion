# Development Setup Guide

This guide will help you set up your development environment for contributing to AICLI Companion.

## Prerequisites

### Required Software
- **macOS**: 12.0+ (for iOS development)
- **Xcode**: 15.0+ with iOS SDK
- **Node.js**: 18.0+ LTS
- **npm**: 8.0+
- **Git**: 2.30+
- **Claude Code CLI**: 1.0.55+

### Optional but Recommended
- **Rust**: Latest stable (for desktop app)
- **Visual Studio Code**: With extensions
- **Postman**: For API testing
- **Charles Proxy**: For network debugging

## Repository Setup

### 1. Fork and Clone

```bash
# Fork the repository on GitHub first
git clone https://github.com/YOUR_USERNAME/claude-companion.git
cd claude-companion

# Add upstream remote
git remote add upstream https://github.com/original/claude-companion.git
```

### 2. Install Dependencies

```bash
# Install root dependencies
npm install

# Install server dependencies
cd server
npm install

# Install host app dependencies
cd hostapp
npm install

# Return to root
cd ../..
```

### 3. Environment Configuration

Create `.env` files for development:

**server/.env**
```env
# Development settings
NODE_ENV=development
PORT=3001
HOST=0.0.0.0

# Generate a development token
AUTH_TOKEN=dev-token-change-in-production

# Enable all features for development
ENABLE_BONJOUR=true
DEBUG=claude:*

# Claude settings for development
CLAUDE_PERMISSION_MODE=acceptEdits
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit,Bash
```

**server/hostapp/.env**
```env
# Host app development
VITE_DEV_SERVER_URL=http://localhost:3001
```

## iOS Development Setup

### 1. Swift Package Dependencies

```bash
cd ios
swift package resolve
```

### 2. Xcode Configuration

1. Open `ios/ClaudeCompanion.xcodeproj`
2. Select your development team
3. Update bundle identifier if needed
4. Select a simulator or device
5. Build and run (⌘R)

### 3. Development Certificates

For device testing:
1. Automatic signing recommended
2. Register test devices in Apple Developer portal
3. Create development provisioning profile

## Server Development

### 1. Start Development Server

```bash
cd server
npm run dev
```

This runs with:
- Auto-restart on file changes (nodemon)
- Debug logging enabled
- Source maps for debugging

### 2. Testing the Server

```bash
# In another terminal
curl http://localhost:3001/health

# Test with auth token
curl http://localhost:3001/api/info \
  -H "Authorization: Bearer dev-token-change-in-production"
```

### 3. Debugging

**VS Code Launch Configuration** (`.vscode/launch.json`):
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Debug Server",
      "program": "${workspaceFolder}/server/src/index.js",
      "envFile": "${workspaceFolder}/server/.env",
      "console": "integratedTerminal"
    }
  ]
}
```

## Desktop App Development

### 1. Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### 2. Run in Development

```bash
cd server/hostapp
npm run tauri dev
```

This provides:
- Hot reload for frontend
- Rust compilation with debug symbols
- DevTools access

## Testing Setup

### 1. Run All Tests

```bash
# From root directory
npm test
```

### 2. Test Coverage

```bash
# Server tests with coverage
cd server
npm run test:coverage

# Host app tests
cd hostapp
npm run test:coverage
```

### 3. iOS Tests

```bash
cd ios
swift test

# Or in Xcode
# Product → Test (⌘U)
```

## Development Workflow

### 1. Branch Strategy

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Create bug fix branch
git checkout -b fix/issue-description
```

### 2. Code Style

**JavaScript/TypeScript**:
- ESLint configuration provided
- Prettier for formatting
- Run `npm run lint` before committing

**Swift**:
- SwiftLint rules in `.swiftlint.yml`
- Follow Swift API Design Guidelines
- Use meaningful variable names

**Rust**:
- Follow Rust formatting guidelines
- Run `cargo fmt` before committing
- Use `cargo clippy` for linting

### 3. Commit Messages

Follow conventional commits:
```
feat: add new feature
fix: resolve bug in component
docs: update installation guide
test: add unit tests for service
refactor: improve error handling
```

## Common Development Tasks

### Adding a New API Endpoint

1. Define route in `server/src/routes/index.js`
2. Implement handler in appropriate service
3. Add validation middleware
4. Update API documentation
5. Write tests

### Adding iOS Features

1. Create new SwiftUI view
2. Add ViewModel if needed
3. Update navigation
4. Add to preview provider
5. Write unit tests

### Modifying WebSocket Protocol

1. Update protocol in `server/src/services/websocket.js`
2. Update iOS WebSocket service
3. Update protocol documentation
4. Test bidirectional communication

## Debugging Tips

### Server Debugging

```bash
# Enable all debug logs
DEBUG=* npm run dev

# Filter specific modules
DEBUG=claude:websocket,claude:session npm run dev
```

### iOS Debugging

1. Use Xcode breakpoints
2. Print to console: `print("Debug: \(variable)")`
3. Use the Network Link Conditioner
4. Check the device console

### WebSocket Debugging

1. Chrome DevTools: `chrome://inspect`
2. Use WebSocket client: `wscat`
3. Monitor with Wireshark
4. Check server logs

## Development Tools

### Recommended VS Code Extensions
- ESLint
- Prettier
- GitLens
- REST Client
- WebSocket Client

### Useful Commands

```bash
# Watch for file changes
npm run watch

# Format all code
npm run format

# Check for security issues
npm audit

# Update dependencies
npm update
```

## Troubleshooting Development Issues

### Port Already in Use

```bash
# Find process using port 3001
lsof -i :3001

# Kill the process
kill -9 <PID>
```

### Node Module Issues

```bash
# Clean install
rm -rf node_modules package-lock.json
npm install
```

### Xcode Build Failures

1. Clean build folder: Shift+Cmd+K
2. Delete derived data
3. Reset package cache
4. Restart Xcode

## Next Steps

- Read [Contributing Guidelines](./contributing.md)
- Review [Testing Guide](./testing.md)
- Check [Architecture Overview](../architecture/overview.md)
- Join the development chat

---

**Last Updated**: 2025-08-09# Build Instructions - UI Changes and Assets

## Clean Build Steps

To ensure all UI changes and assets are properly reflected in your app:

1. **Clean Build Folder in Xcode:**
   - Open the project in Xcode
   - Go to Product → Clean Build Folder (Shift+Cmd+K)
   - Alternatively: `rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeCompanion*`

2. **Reset Package Cache:**
   ```bash
   cd /Users/michaelfuscoletti/Desktop/claude-companion/ios
   rm -rf .build
   rm -rf build
   ```

3. **Rebuild the Project:**
   - In Xcode: Product → Build (Cmd+B)
   - Or from command line:
   ```bash
   xcodebuild clean build -project ClaudeCompanion.xcodeproj -scheme ClaudeCompanionApp
   ```

4. **If Assets Still Don't Appear:**
   - Delete the app from the simulator
   - Reset the simulator: Device → Erase All Content and Settings
   - Build and run again

## Changes Made

1. **Removed Test Button** - The debug test button has been removed from ConnectionView
2. **Added Assets** - App icon and logo assets are now properly included in the project
3. **UI Overhaul** - New gradient background and custom header with logo
4. **Fixed Asset References** - Both Xcode project and Swift Package Manager now properly reference the assets

## Verification

After building, you should see:
- App icon on the home screen
- Logo in the app header (light/dark mode variants)
- Gradient background
- No test button in the connection view
- Cleaner, single-screen UI design