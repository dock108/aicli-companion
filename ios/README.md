# AICLI Companion iOS App

Native iOS/macOS client for AICLI Companion, providing a modern SwiftUI interface for interacting with Claude via the companion server.

## Features

### Core Functionality
- **Real-time Chat**: Stream responses from Claude with character-by-character updates
- **Project Management**: Organize conversations by project context
- **Local Storage**: All messages stored locally with CoreData
- **CloudKit Sync**: Optional iCloud synchronization across devices
- **Push Notifications**: Receive notifications when Claude completes tasks
- **Rich Content**: Beautiful rendering of code blocks, markdown, and tool outputs
- **Attachments**: Send images and documents up to 10MB

### Chat Modes
- **Normal Mode**: Full access to all file operations
- **Planning Mode**: Limited to documentation files only (*.md, *.txt, etc.)
- **Code Mode** (Hidden): Optimized for fast code generation

### Workspace Tools (Currently Hidden)
- **New Project**: AI-guided project creation with templates
- **Planning Validation**: Real-time requirement analysis and readiness scoring
- **Code Review** (Coming Soon): AI-powered code analysis
- **Refactor Assistant** (Coming Soon): Intelligent refactoring suggestions

## Architecture

### Project Structure
```
ios/
├── Sources/AICLICompanion/
│   ├── Models/              # Data models and CoreData entities
│   ├── Services/            # Business logic and API clients
│   │   ├── AICLI/          # Claude integration services
│   │   ├── CloudKit/       # iCloud sync services
│   │   └── PlanningValidation/  # Project planning validation
│   ├── Views/              # SwiftUI views
│   │   ├── Chat/           # Chat interface components
│   │   ├── ProjectCreation/ # Project creation wizard
│   │   └── PlanningDashboard/ # Planning validation UI
│   ├── ViewModels/         # View models and state management
│   └── Utils/              # Utility functions and extensions
├── Tests/                  # Unit and integration tests
└── App/                    # App configuration and assets
```

### Key Components

#### Services
- `AICLIService`: Main service for server communication
- `WebSocketManager`: Real-time WebSocket connection handling
- `PushNotificationService`: APNS integration for message delivery
- `CloudKitSyncManager`: iCloud synchronization
- `PlanningValidator`: Project requirement analysis
- `RequirementsTracker`: Track and manage project requirements

#### Views
- `ChatView`: Main chat interface with message composition
- `ProjectSelectionView`: Project list and selection
- `ConnectionView`: Server connection setup
- `PlanningDashboard`: Planning validation dashboard
- `ProjectCreationWizard`: Multi-step project creation flow

#### Models
- `Message`: Core message model with tool outputs
- `Project`: Project context and metadata
- `ToolOutput`: Structured tool execution results
- `Attachment`: File attachment handling

## Building

### Requirements
- Xcode 15.0+
- iOS 16.0+ / macOS 13.0+
- Swift 5.9+

### Build Instructions
```bash
# Build for iOS
swift build

# Run tests
swift test

# Clean build artifacts
swift package clean
```

### Dependencies
- **KeychainAccess**: Secure credential storage
- **Starscream**: WebSocket client
- **swift-markdown**: Markdown parsing and rendering

## Configuration

### Feature Flags
Located in `Sources/AICLICompanion/FeatureFlags.swift`:

```swift
// Workspace tools
static let showProjectCreation = false      // Project creation wizard
static let showPlanningValidation = false   // Planning validation
static let showCodeReview = false           // Code review (coming soon)

// Chat modes
static let showNormalMode = true            // Standard mode
static let showPlanningMode = true          // Documentation only
static let showCodeMode = false             // Fast generation

// Enhanced Auto-Response System
static let isAutoResponseEnabled = true     // 5-mode auto-response system
static let showAutoResponseUI = true        // Status bar and controls
static let enableAutoResponseSettings = true // Settings interface
static let enableAIResponses = false        // OpenAI integration
static let enableTrainingDataCollection = true // ML training

// CloudKit & Sync
static let enableCloudKitSync = true        // Cross-device sync
static let enableCloudKitSettingsSync = true // Settings sync
static let showSyncStatusUI = true          // Sync indicators

// System features
static let isQueueSystemEnabled = false     // Message queueing (future)
```

## Recent Updates (v2.1.0)

### Major Features Added
- **Enhanced Auto-Response System**: 5 intelligent automation modes (Smart Stop, Until Completion, Time-Based, Message-Based, Hybrid)
- **AI-Powered Responses**: OpenAI integration for intelligent response generation (hidden by default)
- **CloudKit Synchronization**: Cross-device sync for conversations and settings
- **Training Data Collection**: Machine learning from successful interactions
- **Real-Time Status UI**: Auto-response status bar with progress indicators
- **Comprehensive Settings**: Full settings interface for auto-response configuration

### System Improvements
- Updated feature flag system to reflect all new capabilities
- Enhanced CloudKit integration with conflict resolution
- Improved auto-response safety controls and override mechanisms
- Added comprehensive documentation and testing for all new features

### Previous Updates (v1.0.1)
- **Planning Validation Engine**: Real-time requirement extraction and readiness scoring
- **Project Creation Wizard**: Template-based project creation with AI guidance
- **Requirements Tracking**: Track project requirements across multiple domains
- **Readiness Scoring**: Dynamic scoring based on project completeness

### Performance Improvements
- Cleaned build artifacts and SPM cache
- Removed temporary coverage files
- Optimized file sizes and dependencies

## Testing

Run the test suite:
```bash
swift test
```

For specific test targets:
```bash
swift test --filter ChatViewModelTests
swift test --filter PlanningValidatorTests
```

## Deployment

The app is configured for both iOS and macOS deployment. Use Xcode for App Store distribution or TestFlight builds.

## Contributing

1. Check feature flags before adding new features
2. Follow existing SwiftUI patterns and conventions
3. Ensure all new code has appropriate test coverage
4. Update this README when adding significant features

## License

See main project LICENSE file.