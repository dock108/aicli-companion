# Claude Companion iOS App

A native iOS application that brings Claude's AI assistance to your mobile device through an elegant, modern interface. Built with SwiftUI for optimal performance and seamless iOS integration.

## Features

### Core Functionality
- **Real-time Chat Interface**: Stream Claude's responses character-by-character
- **Project Management**: Organize conversations by project with full context
- **Message Persistence**: Never lose a conversation - synced with server
- **Push Notifications**: Get notified when Claude completes tasks
- **Offline Support**: Browse previous conversations without connection
- **Rich Content Rendering**: Beautiful display of code, markdown, and tool outputs

### User Experience
- **Native iOS Design**: Follows Apple's Human Interface Guidelines
- **Dark Mode Support**: Automatic adaptation to system appearance
- **Haptic Feedback**: Subtle feedback for interactions
- **Gesture Support**: Swipe actions and pull-to-refresh
- **Keyboard Shortcuts**: iPad keyboard support
- **Dynamic Type**: Respects system font size preferences

### Technical Features
- **WebSocket Communication**: Real-time bidirectional messaging
- **Automatic Reconnection**: Seamlessly handles connection drops
- **Message Queue**: Reliable delivery with offline support
- **Session Persistence**: Continue conversations across app launches
- **Performance Monitoring**: Built-in telemetry for optimization
- **Secure Storage**: Keychain integration for sensitive data

## Requirements

- iOS 16.0 or later
- iPhone or iPad
- Xcode 15.0+ (for building from source)
- Claude Companion server running on your network

## Installation

### Option 1: Build from Source

1. Clone the repository:
```bash
git clone https://github.com/your-username/claude-companion.git
cd claude-companion/ios
```

2. Open in Xcode:
```bash
open AICLICompanion.xcodeproj
```

3. Configure signing:
   - Select the project in navigator
   - Go to "Signing & Capabilities"
   - Select your development team
   - Update bundle identifier if needed

4. Build and run:
   - Select your target device
   - Press ⌘R to build and run

### Option 2: TestFlight (Coming Soon)

Join our TestFlight beta for easy installation without building from source.

### Option 3: App Store (Future)

We plan to release on the App Store once the app reaches stability milestones.

## Initial Setup

### 1. Server Connection

On first launch:
1. Ensure your Claude Companion server is running
2. The app will automatically discover servers on your network
3. Select your server from the list
4. Enter authentication token if required

### 2. Push Notifications

To enable push notifications:
1. Go to Settings → Notifications
2. Enable "Push Notifications"
3. Allow notification permissions when prompted
4. Notifications will alert you when Claude completes long tasks

### 3. Project Selection

Create or select a project:
1. Tap the project selector at the top
2. Choose an existing project or create new
3. Projects help organize conversations by context

## Usage Guide

### Starting a Conversation

1. Select or create a project
2. Type your message in the input field
3. Tap send or press return
4. Watch Claude's response stream in real-time

### Message Features

- **Copy**: Long-press any message to copy
- **Code Blocks**: Tap to copy code with syntax highlighting
- **Tool Outputs**: Expandable sections for file operations
- **Retry**: Swipe left on failed messages to retry

### Session Management

- **Continue Session**: Previous conversations automatically restore
- **New Session**: Pull down to refresh for a new session
- **Switch Projects**: Tap project name to change context
- **Clear History**: Available in Settings → Data Management

### Keyboard Shortcuts (iPad)

- `⌘ + Return`: Send message
- `⌘ + N`: New session
- `⌘ + ,`: Open settings
- `⌘ + K`: Clear current message
- `⌘ + /`: Show keyboard shortcuts

## Architecture

```
ios/
├── Sources/
│   └── AICLICompanion/
│       ├── App/                    # App lifecycle
│       ├── Models/                 # Data models
│       ├── Services/               # Core services
│       │   ├── Chat/              # Chat management
│       │   ├── WebSocketService   # Real-time communication
│       │   └── MessageQueue       # Offline support
│       ├── Views/                  # UI components
│       │   ├── Chat/              # Chat interface
│       │   ├── Projects/          # Project management
│       │   └── Settings/          # Configuration
│       └── Utilities/             # Helper functions
├── Tests/                         # Unit tests
└── App/                           # App configuration
```

### Key Components

#### WebSocketService
Manages real-time communication with the server:
- Automatic reconnection with exponential backoff
- Message queuing for offline scenarios
- Device fingerprinting for session continuity
- Heartbeat for connection monitoring

#### ChatSessionManager
Handles conversation state:
- Session lifecycle management
- Message persistence
- Project context switching
- Conversation history

#### MessagePersistenceService
Local storage for offline access:
- CoreData integration
- Automatic sync with server
- Efficient message retrieval
- Storage quota management

#### PushNotificationService
Background task notifications:
- APNS integration
- Rich notifications
- Action handling
- Token management

## Configuration

### Settings Available

1. **Connection**
   - Server address (auto-discovered)
   - Authentication token
   - Connection timeout

2. **Appearance**
   - Theme selection (light/dark/auto)
   - Font size adjustment
   - Message density

3. **Notifications**
   - Push notification toggle
   - Notification sounds
   - Banner style

4. **Data & Storage**
   - Clear message history
   - Cache management
   - Export conversations

5. **Advanced**
   - Debug logging
   - Performance metrics
   - Network diagnostics

### Environment Variables

For development, create a `.xcconfig` file:
```
// Development.xcconfig
SERVER_URL = http://localhost:3001
ENABLE_LOGGING = YES
```

## Development

### Building for Development

1. Install dependencies (if any):
```bash
cd ios
# No external dependencies - pure Swift!
```

2. Open in Xcode:
```bash
open AICLICompanion.xcodeproj
```

3. Select scheme:
   - `AICLICompanion`: Main app
   - `AICLICompanionTests`: Unit tests

### Running Tests

```bash
# In Xcode
⌘ + U

# Or from command line
xcodebuild test -scheme AICLICompanion -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Code Style

We follow Swift standard conventions:
- SwiftLint for code style enforcement
- 100 character line limit
- Comprehensive documentation comments
- Meaningful variable names

### Debugging

Enable debug logging in Settings → Advanced → Debug Mode

Common debugging commands:
```swift
// Print WebSocket traffic
WebSocketService.shared.enableVerboseLogging = true

// Export message database
MessagePersistenceService.shared.exportDatabase()

// View connection metrics
ConnectionReliabilityManager.shared.printMetrics()
```

## Troubleshooting

### Connection Issues

1. **Cannot find server**
   - Ensure server is running
   - Check both devices are on same network
   - Try manual IP entry
   - Verify firewall settings

2. **Authentication failures**
   - Regenerate token on server
   - Clear app keychain data
   - Check token hasn't expired

3. **Messages not syncing**
   - Check connection status indicator
   - Pull to refresh conversation
   - Verify server message persistence

### Performance Issues

1. **Slow message rendering**
   - Clear message history
   - Reduce message density in settings
   - Check available device storage

2. **High battery usage**
   - Disable background refresh
   - Reduce reconnection frequency
   - Check for excessive logging

### Push Notifications

1. **Not receiving notifications**
   - Verify permissions in iOS Settings
   - Check server APNS configuration
   - Ensure device token is registered
   - Look for bad token errors on server

2. **Duplicate notifications**
   - Clear notification badge
   - Check for multiple device registrations
   - Verify server deduplication

## Contributing

We welcome contributions! See our [Contributing Guide](../CONTRIBUTING.md) for details.

### Development Guidelines

- Write unit tests for new features
- Update documentation for UI changes
- Follow SwiftUI best practices
- Test on multiple device sizes
- Consider accessibility

### Submitting Changes

1. Fork the repository
2. Create feature branch
3. Write tests and documentation
4. Submit pull request

## Security

The app implements several security measures:
- Keychain storage for credentials
- Certificate pinning (optional)
- No analytics or tracking
- Local data encryption
- Secure WebSocket connections

## Future Features

Planned enhancements:
- [ ] Message search functionality
- [ ] Voice input support
- [ ] Share extension
- [ ] Apple Watch companion
- [ ] Widgets for quick access
- [ ] Siri Shortcuts integration
- [ ] Multi-window support (iPad)

## License

MIT License - See [LICENSE](../LICENSE) for details.

## Acknowledgments

- Built with SwiftUI and love for iOS
- Designed for developers by developers
- Inspired by the best iOS apps