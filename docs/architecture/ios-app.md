# iOS App Architecture

The AICLI Companion iOS app is built with SwiftUI and follows modern iOS development patterns for a responsive, native experience.

## App Structure

```
ClaudeCompanion/
├── App/
│   ├── ClaudeCompanionApp.swift    # App entry point
│   └── Info.plist                   # App configuration
├── Views/
│   ├── ContentView.swift            # Main container
│   ├── ChatView.swift              # Chat interface
│   ├── ConnectionView.swift         # Server connection
│   ├── SettingsView.swift          # App settings
│   └── Components/                  # Reusable UI
├── Services/
│   ├── WebSocketService.swift      # WebSocket client
│   ├── ClaudeCodeService.swift     # API wrapper
│   ├── KeychainManager.swift       # Secure storage
│   └── ServiceDiscoveryManager.swift # Bonjour
├── Models/
│   ├── Message.swift               # Chat messages
│   ├── Settings.swift              # User preferences
│   └── ServerInfo.swift            # Server details
└── Utils/
    ├── HapticManager.swift         # Haptic feedback
    └── RichContentRenderer.swift   # Markdown rendering
```

## Architecture Patterns

### MVVM Architecture
```
┌─────────────┐     ┌─────────────────┐     ┌─────────────┐
│    View     │────▶│   ViewModel     │────▶│    Model    │
│  (SwiftUI)  │◀────│  (ObservableObject) │◀────│   (Struct)  │
└─────────────┘     └─────────────────┘     └─────────────┘
       │                     │                       │
       └─────────────────────┴───────────────────────┘
                    Data Binding (@Published)
```

### Key Design Principles
1. **Reactive UI**: SwiftUI with Combine framework
2. **Protocol-Oriented**: Define capabilities via protocols
3. **Dependency Injection**: Services passed through environment
4. **Composition**: Small, focused components
5. **Type Safety**: Leverage Swift's type system

## Core Components

### WebSocket Service
```swift
class WebSocketService: ObservableObject {
    @Published var connectionState: ConnectionState
    @Published var messages: [Message]
    
    func connect(to server: ServerInfo)
    func send(_ message: ChatMessage)
    func disconnect()
}
```

**Features**:
- Automatic reconnection with exponential backoff
- Message queuing for offline support
- State management for UI updates
- Error handling and recovery

### Chat Interface
```swift
struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var inputText: String = ""
    
    var body: some View {
        VStack {
            MessageList(messages: viewModel.messages)
            ToolActivityView(activities: viewModel.toolActivities)
            MessageInput(text: $inputText, onSend: viewModel.send)
        }
    }
}
```

**Components**:
- **MessageList**: Scrollable chat history
- **MessageBubble**: Individual message display
- **ToolActivityView**: Real-time tool indicators
- **MessageInput**: Text input with send button

### Service Discovery
```swift
class ServiceDiscoveryManager: NSObject {
    func startDiscovery()
    func stopDiscovery()
    var discoveredServers: [ServerInfo]
}
```

**Implementation**:
- Uses `NWBrowser` for Bonjour/mDNS
- Filters for `_claude-companion._tcp` services
- Extracts server metadata from TXT records
- Updates UI with discovered servers

## Data Flow

### Message Flow
```
User Input → ChatView → ChatViewModel → WebSocketService
                                              │
                                              ▼
                                         Server API
                                              │
                                              ▼
ChatView ← ChatViewModel ← WebSocketService ← Response
```

### State Management
- **@StateObject**: Own the lifecycle of ViewModels
- **@ObservedObject**: Reference shared ViewModels
- **@EnvironmentObject**: App-wide services
- **@AppStorage**: Persistent user preferences
- **@State**: Local view state

## Security Implementation

### Keychain Storage
```swift
struct KeychainManager {
    static func save(token: String, for server: String)
    static func load(for server: String) -> String?
    static func delete(for server: String)
}
```

**Security Features**:
- Tokens stored in iOS Keychain
- Biometric authentication optional
- No tokens in UserDefaults
- Secure transport (TLS)

### Data Protection
- **End-to-End**: TLS for all network communication
- **At Rest**: Keychain for sensitive data
- **In Memory**: Clear sensitive data when done
- **App Transport Security**: Enforced HTTPS

## UI/UX Design

### Design System
```swift
extension Color {
    static let primaryAccent = Color("AccentColor")
    static let bubbleUser = Color("BubbleUser")
    static let bubbleAssistant = Color("BubbleAssistant")
}

extension Font {
    static let chatMessage = Font.system(.body)
    static let codeBlock = Font.system(.callout, design: .monospaced)
}
```

### Responsive Layout
- **Dynamic Type**: Support for all text sizes
- **Dark Mode**: Automatic appearance switching
- **iPad Support**: Adaptive layouts
- **Landscape**: Optimized for all orientations

### Accessibility
- **VoiceOver**: Full screen reader support
- **Dynamic Type**: Scalable text
- **Reduce Motion**: Respect system settings
- **High Contrast**: Enhanced visibility
- **Haptic Feedback**: Touch confirmation

## Performance Optimization

### Memory Management
- **Lazy Loading**: Load messages on demand
- **Image Caching**: Cache rendered markdown
- **View Recycling**: Efficient list rendering
- **Background Tasks**: Process data off main thread

### Network Optimization
- **Message Batching**: Group multiple updates
- **Compression**: Reduce data transfer
- **Caching**: Store recent conversations
- **Prefetching**: Anticipate user actions

## Offline Support

### Queue Management
```swift
class OfflineQueueManager {
    func enqueue(_ message: ChatMessage)
    func processQueue()
    var pendingMessages: [ChatMessage]
}
```

**Features**:
- Persist queued messages
- Retry with exponential backoff
- Maintain message order
- Show queue status in UI

## Testing Strategy

### Unit Tests
```swift
class WebSocketServiceTests: XCTestCase {
    func testConnection()
    func testMessageParsing()
    func testReconnection()
    func testErrorHandling()
}
```

### UI Tests
```swift
class ChatUITests: XCTestCase {
    func testSendMessage()
    func testScrollToBottom()
    func testToolActivityDisplay()
}
```

### Integration Tests
- Mock WebSocket server
- Test full message flow
- Verify state transitions
- Check error scenarios

## Build & Deployment

### Build Configuration
```
Debug:   Development servers, verbose logging
Release: Production servers, optimized
TestFlight: Beta testing, crash reporting
```

### App Store Preparation
1. **Privacy Policy**: Required for network usage
2. **Export Compliance**: Encryption declaration
3. **Screenshots**: All device sizes
4. **App Description**: Feature highlights
5. **Review Notes**: Server setup instructions

## Future Enhancements

### Planned Features
- **Multi-Window Support**: iPad productivity
- **Shortcuts Integration**: Siri and automation
- **Widget Support**: Quick actions
- **Share Extension**: Send files to Claude
- **CloudKit Sync**: Multi-device conversations

### Architecture Evolution
- **SwiftData**: Modern persistence layer
- **Async/Await**: Simplified concurrency
- **Actors**: Thread-safe state management
- **Swift Charts**: Visualization support
- **Vision Framework**: Image analysis

---

**Last Updated**: 2025-08-09