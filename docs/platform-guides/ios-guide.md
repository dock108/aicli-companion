# AICLI Companion iOS App

A native iOS application that brings Claude's AI assistance to your mobile device through an elegant, modern interface. Built with SwiftUI for optimal performance and seamless iOS integration.

## Features

### Core Functionality
- **Real-time Chat Interface**: Stream Claude's responses character-by-character
- **Enhanced Auto-Response System**: 5 intelligent automation modes with AI integration
- **Project Management**: Organize conversations by project with full context
- **Message Persistence**: Never lose a conversation - synced with server
- **Push Notifications**: Get notified when Claude completes tasks
- **Offline Support**: Browse previous conversations without connection
- **Rich Content Rendering**: Beautiful display of code, markdown, and tool outputs
- **CloudKit Sync**: Cross-device conversation and settings synchronization

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
- AICLI Companion server running on your network

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
1. Ensure your AICLI Companion server is running
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

---


# iOS Integration Guide for AICLI Companion Server

## Overview

This guide documents all iOS-specific features and integration points for the AICLI Companion Server. It includes implementation guidelines, API usage examples, and best practices.

## 1. Session Management

### 1.1 Session Deduplication

The server now prevents multiple sessions for the same project. iOS should implement similar logic client-side.

**Implementation Requirements:**
- Store session IDs mapped to working directories
- Check for existing session before creating new one
- Use session continuation endpoint when appropriate

**Example Implementation:**
```swift
class SessionManager {
    private var activeSessions: [String: String] = [:] // workingDirectory -> sessionId
    
    func getOrCreateSession(for workingDirectory: String) async throws -> String {
        // Check for existing session
        if let existingSessionId = activeSessions[workingDirectory] {
            // Verify session is still valid
            let isValid = try await verifySession(existingSessionId)
            if isValid {
                return existingSessionId
            }
        }
        
        // Create new session
        let sessionId = try await createNewSession(workingDirectory: workingDirectory)
        activeSessions[workingDirectory] = sessionId
        return sessionId
    }
}
```

### 1.2 Session Continuation

When the app returns from background, use the continuation endpoint to reconnect to existing sessions.

**API Endpoint:**
```
POST /api/sessions/continue
{
    "sessionId": "existing-session-id",
    "workingDirectory": "/path/to/project"
}
```

**iOS Implementation:**
```swift
func applicationDidBecomeActive() {
    Task {
        for (directory, sessionId) in activeSessions {
            do {
                let response = try await api.continueSession(
                    sessionId: sessionId,
                    workingDirectory: directory
                )
                if response.success {
                    // Mark session as foregrounded
                    websocket.send(SessionForegrounded(sessionId: sessionId))
                }
            } catch {
                // Session might be expired, remove from cache
                activeSessions.removeValue(forKey: directory)
            }
        }
    }
}
```

## 2. Message Validation

### 2.1 Empty Message Filtering

The server filters empty stream chunks. iOS should implement matching validation.

**Validation Logic:**
```swift
struct MessageValidator {
    static func isValidStreamChunk(_ chunk: StreamChunk) -> Bool {
        // Filter empty content chunks
        if chunk.type == "content" && chunk.data.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return false
        }
        
        // Filter incomplete tool use chunks
        if chunk.type == "tool_use" && chunk.data.name?.isEmpty == true {
            return false
        }
        
        return true
    }
    
    static func filterMessages(_ messages: [Message]) -> [Message] {
        return messages.filter { message in
            if case .streamChunk(let chunk) = message {
                return isValidStreamChunk(chunk)
            }
            return true
        }
    }
}
```

### 2.2 Message Enrichment Metadata

Queued messages include additional metadata. Handle these fields appropriately.

**Metadata Fields:**
- `_queued`: Boolean indicating message was queued
- `_queuedAt`: ISO timestamp when message was queued
- `_originalTimestamp`: Original message timestamp

**Example Handling:**
```swift
struct QueuedMessage {
    let message: Message
    let wasQueued: Bool
    let queuedAt: Date?
    let originalTimestamp: Date?
    
    init(from json: [String: Any]) {
        // Parse regular message fields
        self.message = Message(from: json)
        
        // Parse queue metadata
        self.wasQueued = json["_queued"] as? Bool ?? false
        if let queuedAtString = json["_queuedAt"] as? String {
            self.queuedAt = ISO8601DateFormatter().date(from: queuedAtString)
        }
        if let originalString = json["_originalTimestamp"] as? String {
            self.originalTimestamp = ISO8601DateFormatter().date(from: originalString)
        }
    }
}
```

## 3. WebSocket Reconnection

### 3.1 Device ID Header

Always send a persistent device ID for automatic session restoration.

**Implementation:**
```swift
class WebSocketManager {
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    
    func connect(token: String) {
        var request = URLRequest(url: websocketURL)
        request.setValue(deviceId, forHTTPHeaderField: "x-device-id")
        request.url?.append(queryItems: [URLQueryItem(name: "token", value: token)])
        
        websocket = URLSessionWebSocketTask(session: session, request: request)
        websocket.resume()
    }
}
```

### 3.2 Handling Reconnection

The server will automatically restore your sessions on reconnection.

**Welcome Message Handling:**
```swift
func handleWelcomeMessage(_ welcome: WelcomeMessage) {
    // Server capabilities
    self.serverVersion = welcome.serverVersion
    self.capabilities = welcome.capabilities
    
    // Subscribe to events
    websocket.send(SubscribeMessage(events: [
        "assistantMessage",
        "streamData",
        "sessionStatus",
        "error"
    ]))
    
    // Re-register for push notifications if needed
    if let deviceToken = self.deviceToken {
        websocket.send(RegisterDeviceMessage(
            deviceToken: deviceToken,
            deviceInfo: "ios"
        ))
    }
}
```

## 4. Push Notifications

### 4.1 Registration

Register device tokens immediately after connection.

```swift
func registerForPushNotifications(deviceToken: Data) {
    let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
    
    websocket.send(RegisterDeviceMessage(
        deviceToken: tokenString,
        deviceInfo: "ios"
    ))
}
```

### 4.2 Handling Notifications

Process push notification payloads correctly.

```swift
func handlePushNotification(_ userInfo: [AnyHashable: Any]) {
    guard let payload = userInfo["payload"] as? [String: Any],
          let sessionId = payload["sessionId"] as? String,
          let deepLink = payload["deepLink"] as? String else {
        return
    }
    
    // Handle deep link
    if let url = URL(string: deepLink) {
        // Navigate to session
        navigateToSession(sessionId)
    }
    
    // Handle long-running completion
    if payload["isLongRunningCompletion"] as? Bool == true {
        showCompletionAlert(for: sessionId)
    }
}
```

## 5. Background Handling

### 5.1 Session Backgrounding

Notify server when app goes to background.

```swift
func applicationDidEnterBackground() {
    for sessionId in activeSessions.values {
        websocket.send(SessionBackgroundedMessage(sessionId: sessionId))
    }
}
```

### 5.2 Session Foregrounding

Notify server when app returns.

```swift
func applicationWillEnterForeground() {
    for sessionId in activeSessions.values {
        websocket.send(SessionForegroundedMessage(sessionId: sessionId))
    }
}
```

## 6. Error Handling

### 6.1 Session Errors

Handle session-specific errors appropriately.

```swift
func handleError(_ error: ErrorMessage) {
    switch error.code {
    case "INVALID_SESSION":
        // Remove from cache and create new session
        if let sessionId = error.sessionId {
            removeSession(sessionId)
            // Prompt user to restart
        }
        
    case "SESSION_LIMIT":
        // Show alert about too many sessions
        showSessionLimitAlert()
        
    case "PERMISSION_DENIED":
        // Handle permission issues
        requestPermissions()
        
    default:
        // Generic error handling
        showError(error.message)
    }
}
```

## 7. Performance Optimization

### 7.1 Message Batching

Batch UI updates for better performance.

```swift
class MessageBatcher {
    private var pendingMessages: [Message] = []
    private var batchTimer: Timer?
    
    func addMessage(_ message: Message) {
        pendingMessages.append(message)
        
        if batchTimer == nil {
            batchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                self.flushMessages()
            }
        }
    }
    
    private func flushMessages() {
        let messages = pendingMessages
        pendingMessages.removeAll()
        batchTimer = nil
        
        DispatchQueue.main.async {
            self.updateUI(with: messages)
        }
    }
}
```

### 7.2 Connection State Caching

Cache connection state for faster reconnection.

```swift
class ConnectionStateCache {
    @AppStorage("connectionState") private var cachedState: Data?
    
    func saveState(_ state: ConnectionState) {
        if let encoded = try? JSONEncoder().encode(state) {
            cachedState = encoded
        }
    }
    
    func loadState() -> ConnectionState? {
        guard let data = cachedState else { return nil }
        return try? JSONDecoder().decode(ConnectionState.self, from: data)
    }
}
```

## 8. Testing

### 8.1 Unit Tests

Test message validation and filtering.

```swift
func testMessageValidation() {
    // Test empty chunk filtering
    let emptyChunk = StreamChunk(type: "content", data: ["content": ""])
    XCTAssertFalse(MessageValidator.isValidStreamChunk(emptyChunk))
    
    // Test valid chunk
    let validChunk = StreamChunk(type: "content", data: ["content": "Hello"])
    XCTAssertTrue(MessageValidator.isValidStreamChunk(validChunk))
}
```

### 8.2 Integration Tests

Test session management flow.

```swift
func testSessionDeduplication() async {
    let manager = SessionManager()
    
    // Create first session
    let session1 = try await manager.getOrCreateSession(for: "/test/project")
    
    // Should return same session
    let session2 = try await manager.getOrCreateSession(for: "/test/project")
    
    XCTAssertEqual(session1, session2)
}
```

## 9. Migration Guide

### From Previous Version

1. **Update WebSocket connection to include device ID header**
2. **Implement session continuation on app foreground**
3. **Add message validation before displaying**
4. **Handle queued message metadata**
5. **Update push notification handling for new payload format**

## 10. Checklist

- [ ] Implement session deduplication
- [ ] Add session continuation on foreground
- [ ] Send device ID header on connection
- [ ] Implement message validation matching server
- [ ] Handle queued message metadata
- [ ] Update push notification registration
- [ ] Add session backgrounding/foregrounding messages
- [ ] Implement connection state caching
- [ ] Add proper error handling for new error codes
- [ ] Update tests for new functionality

## TODO: iOS Implementation Items

1. **Session State Persistence**
   - TODO: Implement CoreData or UserDefaults storage for session mappings
   - TODO: Add session expiry tracking
   - TODO: Implement session cleanup on app launch

2. **Message Queue UI**
   - TODO: Show indicator when receiving queued messages
   - TODO: Display queue delivery timestamp if significantly delayed
   - TODO: Handle message ordering with queued messages

3. **Connection Reliability**
   - TODO: Implement exponential backoff for reconnection
   - TODO: Add connection quality indicator
   - TODO: Cache last N messages for comparison after reconnect

4. **Performance Monitoring**
   - TODO: Track message processing time
   - TODO: Monitor WebSocket connection stability
   - TODO: Report metrics to server telemetry endpoint

5. **Push Notification Enhancements**
   - TODO: Implement notification actions (View, Dismiss)
   - TODO: Add notification grouping by project
   - TODO: Handle notification badge counts properly