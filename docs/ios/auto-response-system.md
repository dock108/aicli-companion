# iOS Auto-Response System

## Overview

The iOS Auto-Response System provides intelligent automation capabilities that allow AICLI Companion to continue conversations with Claude automatically based on configurable criteria. The system includes 5 distinct modes, AI-powered response generation, and cross-device synchronization via CloudKit.

## Architecture

### Key Components

1. **AutoReplySettings** (`ios/Sources/AICLICompanion/Models/AutoReplySettings.swift`)
   - Core settings model with all configuration options
   - Supports 5 auto-response modes with mode-specific settings
   - Includes AI configuration and safety controls

2. **AutoReplySettingsStore** (`ios/Sources/AICLICompanion/Models/AutoReplySettingsStore.swift`)
   - Singleton service managing settings persistence
   - CloudKit integration for cross-device sync
   - Handles settings import/export

3. **AutoReplySettingsView** (`ios/Sources/AICLICompanion/Views/AutoReplySettingsView.swift`)
   - Comprehensive SwiftUI interface for all settings
   - Mode-specific configuration sections
   - Quick setup presets and import/export functionality

4. **AutoReplyStatusBar** (`ios/Sources/AICLICompanion/Views/Chat/Components/AutoReplyStatusBar.swift`)
   - Real-time status display in chat interface
   - Progress indicators and quick controls
   - Visual feedback for current mode and activity

## Auto-Response Modes

### 1. Smart Stop
**Description**: AI-powered completion detection that automatically stops when Claude indicates the task is complete.

**Key Features**:
- Uses server-side AI analysis to detect completion
- Configurable confidence thresholds
- Fallback to time/message limits for safety

**Best For**: General development tasks where completion is clear

### 2. Until Completion
**Description**: Continues until Claude explicitly signals task completion, with safety limits.

**Key Features**:
- Highest persistence mode
- Multiple completion detection strategies
- Safety timeouts to prevent infinite loops

**Best For**: Complex multi-step tasks requiring full completion

### 3. Time-Based
**Description**: Runs for a specified duration (minutes or hours).

**Key Features**:
- Precise time control (1 minute to 8 hours)
- Countdown display in UI
- Graceful stopping at time limit

**Best For**: Focused work sessions or time-boxed tasks

### 4. Message-Based
**Description**: Processes a specific number of message exchanges.

**Key Features**:
- Exact message count control (1-100 messages)
- Progress tracking in UI
- Stops precisely at message limit

**Best For**: Specific interactions or bounded conversations

### 5. Hybrid Mode
**Description**: Combines multiple stopping criteria with flexible priority.

**Key Features**:
- Configurable time AND message limits
- AI completion detection overlay
- First-met criteria stops the session

**Best For**: Complex scenarios requiring multiple constraints

## Configuration Options

### Core Settings

```swift
struct AutoReplySettings {
    var isEnabled: Bool = false
    var mode: AutoReplyMode = .smartStop
    var projectId: String = ""
    
    // Mode-specific settings
    var maxIterations: Int = 10
    var maxMinutes: Int = 30
    var maxMessages: Int = 20
    
    // AI Integration
    var aiSettings: AISettings
    var enableAI: Bool = false
    
    // Safety Controls
    var allowOverride: Bool = true
    var requireConfirmation: Bool = false
    var enableShowstopperDetection: Bool = true
}
```

### AI Settings

```swift
struct AISettings {
    var model: String = "gpt-3.5-turbo"
    var temperature: Double = 0.7
    var maxTokens: Int = 150
    var systemPrompt: String = ""
}
```

### Time Limits

```swift
struct TimeLimits {
    var enabled: Bool = true
    var maxMinutes: Int = 30
    var warningMinutes: Int = 5
    var allowExtension: Bool = false
}
```

## CloudKit Integration

### Cross-Device Sync

Auto-response settings are automatically synchronized across all user devices via CloudKit:

```swift
// Settings sync automatically via CloudKitSyncManager
let settings = AutoReplySettingsStore.shared
settings.updateSettings(newSettings) // Syncs to all devices
```

### Sync Features

- **Real-time Sync**: Settings changes propagate to all devices
- **Conflict Resolution**: Last-write-wins for settings conflicts  
- **Offline Support**: Settings cached locally, sync when online
- **Privacy**: All data in user's private CloudKit container

## Server Integration

### API Communication

The iOS app communicates with the server using dedicated auto-response endpoints:

```swift
// Start auto-response session
POST /api/chat/auto-response/start
{
  "sessionId": "session-123",
  "deviceToken": "apns-token",
  "settings": { /* AutoReplySettings */ }
}

// Monitor progress
GET /api/chat/:sessionId/progress
{
  "iterations": 5,
  "maxIterations": 10,
  "confidence": 0.75,
  "mode": "smartStop"
}
```

### Real-time Updates

- **WebSocket Connection**: Live progress updates
- **Push Notifications**: Status changes and completions
- **Progress Tracking**: Detailed session metrics

## User Interface

### Settings Interface

The `AutoReplySettingsView` provides a comprehensive configuration interface:

1. **Mode Selection**: Visual mode picker with descriptions
2. **Basic Settings**: Common parameters (iterations, time limits)
3. **AI Configuration**: OpenAI integration settings
4. **Advanced Options**: Safety controls and expert settings
5. **Quick Setup**: Preset configurations for common scenarios

### Status Bar

The `AutoReplyStatusBar` shows real-time session status:

- **Current Mode**: Visual indicator with color coding
- **Progress**: Iteration count, time remaining, confidence levels
- **Controls**: Pause/resume, stop, settings access
- **Status Messages**: Current activity and completion status

## Implementation Guide

### Basic Setup

```swift
// 1. Configure settings
var settings = AutoReplySettings()
settings.isEnabled = true
settings.mode = .smartStop
settings.maxIterations = 15
settings.maxMinutes = 30

// 2. Save settings
AutoReplySettingsStore.shared.updateSettings(settings)

// 3. Start auto-response (handled by ChatViewModel)
chatViewModel.startAutoResponse()
```

### Advanced Configuration

```swift
// AI-powered responses
settings.enableAI = true
settings.aiSettings.model = "gpt-4"
settings.aiSettings.temperature = 0.5
settings.aiSettings.systemPrompt = "Focus on code quality and best practices"

// Safety controls
settings.allowOverride = true
settings.requireConfirmation = true
settings.enableShowstopperDetection = true

// Hybrid mode setup
settings.mode = .hybrid
settings.maxMessages = 25
settings.maxMinutes = 45
settings.enableAI = true
```

## Testing

### Unit Testing

```swift
// Test settings persistence
func testSettingsPersistence() {
    let store = AutoReplySettingsStore()
    let settings = AutoReplySettings(mode: .timeBased, maxMinutes: 15)
    
    store.updateSettings(settings)
    let retrieved = store.getSettings(for: "test-project")
    
    XCTAssertEqual(retrieved.mode, .timeBased)
    XCTAssertEqual(retrieved.maxMinutes, 15)
}
```

### Integration Testing

```swift
// Test server communication
func testAutoResponseStart() async {
    let settings = AutoReplySettings(mode: .smartStop)
    let response = try await httpService.startAutoResponse(
        sessionId: "test-session",
        settings: settings
    )
    
    XCTAssertTrue(response.success)
    XCTAssertEqual(response.mode, "smartStop")
}
```

### UI Testing

```swift
// Test settings interface
func testSettingsView() {
    let app = XCUIApplication()
    app.launch()
    
    app.buttons["Auto-Reply Settings"].tap()
    app.buttons["Smart Stop"].tap()
    app.buttons["Save"].tap()
    
    XCTAssertTrue(app.alerts["Settings Saved"].exists)
}
```

## Performance Considerations

### Resource Management

- **Minimal Battery Impact**: Settings sync only on changes
- **Efficient Storage**: Lightweight Core Data model
- **Smart Caching**: Local settings cache reduces CloudKit calls
- **Background Processing**: CloudKit operations on background queue

### Network Usage

- **Minimal Data**: Settings are small JSON objects
- **Delta Sync**: Only changed settings synchronized
- **Offline Resilience**: Full functionality without network
- **Compression**: CloudKit handles data compression automatically

## Error Handling

### Common Error Scenarios

1. **CloudKit Unavailable**: Graceful degradation to local-only mode
2. **Network Failures**: Queue sync operations for retry
3. **Invalid Settings**: Validation with user-friendly error messages
4. **Server Timeout**: Automatic retry with exponential backoff

### Recovery Strategies

```swift
// Handle CloudKit errors
func handleCloudKitError(_ error: CKError) {
    switch error.code {
    case .networkUnavailable:
        // Queue for retry when network available
        queueForRetry(operation)
    case .quotaExceeded:
        // Show user-friendly message
        showQuotaExceededAlert()
    case .notAuthenticated:
        // Prompt user to sign into iCloud
        showICloudSignInPrompt()
    default:
        // Log error, continue with local operation
        logger.error("CloudKit error: \(error)")
    }
}
```

## Security & Privacy

### Data Protection

- **Local Encryption**: Settings encrypted at rest via iOS Keychain
- **Transport Security**: HTTPS/TLS for all server communication
- **CloudKit Security**: End-to-end encryption managed by Apple
- **No Third-Party Sharing**: Settings never leave user's control

### User Control

- **Opt-in AI**: AI features require explicit user consent
- **API Key Security**: OpenAI keys encrypted and user-provided
- **Data Retention**: User controls settings retention period
- **Export/Delete**: Full data portability and deletion options

## Troubleshooting

### Common Issues

1. **Settings Not Syncing**:
   - Check iCloud sign-in status
   - Verify internet connection
   - Check CloudKit container permissions

2. **Auto-Response Not Starting**:
   - Verify server connection
   - Check authentication token
   - Review session status

3. **AI Responses Failing**:
   - Validate OpenAI API key
   - Check API quota limits
   - Review network connectivity

### Debug Information

```swift
// Enable debug logging
AutoReplySettingsStore.shared.enableDebugLogging = true

// Check sync status
let status = AutoReplySettingsStore.shared.syncStatus
print("Sync status: \(status)")

// Validate settings
let validation = settings.validate()
print("Validation errors: \(validation.errors)")
```

## Future Enhancements

### Planned Features

- **Custom Rules Engine**: User-defined stopping conditions
- **Context Awareness**: Project-specific behavior adaptation
- **Learning System**: Improve suggestions based on usage patterns
- **Team Settings**: Shared configurations for development teams
- **Analytics Dashboard**: Detailed usage and performance metrics

### Extensibility Points

- **Plugin System**: Third-party mode integrations
- **Webhook Support**: External system notifications
- **Custom AI Models**: Support for alternative AI providers
- **Advanced Scheduling**: Time-based activation rules

## Migration Guide

### Upgrading from Previous Versions

```swift
// Handle settings migration
func migrateSettings() {
    let currentVersion = UserDefaults.standard.integer(forKey: "settingsVersion")
    
    switch currentVersion {
    case 0...1:
        migrateV1ToV2()
    case 2:
        migrateV2ToV3()
    default:
        // Already current version
        break
    }
}
```

## References

- [Apple CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [SwiftUI State Management](https://developer.apple.com/documentation/swiftui/state-and-data-flow)
- [Core Data Best Practices](https://developer.apple.com/documentation/coredata)
- [OpenAI API Documentation](https://platform.openai.com/docs)

---

**Last Updated**: 2025-09-11  
**Version**: 1.0.0