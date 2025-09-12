# AICLI Companion Architecture

## System Overview

AICLI Companion is a distributed system consisting of three primary components that work together to provide AI assistance through a native mobile experience:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│  Node.js Server │────▶│  Claude CLI     │
│  (SwiftUI)      │◀────│   (Express)     │◀────│                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         ▲                       ▲
         │                       │
         └───────────────────────┘
           HTTP + APNS
         ┌─────────────────┐
         │  macOS Menu Bar │
         │    (SwiftUI)    │
         └─────────────────┘
```

## Component Architecture

### 1. iOS Application

**Technology Stack**: Swift, SwiftUI, Combine, CoreData

**Key Responsibilities**:
- User interface and interaction
- Real-time message streaming
- Local message persistence
- Push notification handling
- Offline support

**Architecture Pattern**: MVVM with Combine

```
iOS App/
├── Models/              # Data structures
├── Views/               # SwiftUI views
├── ViewModels/          # Business logic
├── Services/            # Network, storage, etc.
└── Utilities/           # Helpers and extensions
```

**Key Services**:
- `HTTPService`: Manages HTTP API communication
- `ChatSessionManager`: Handles conversation state
- `MessagePersistenceService`: Local storage with CoreData
- `PushNotificationService`: APNS integration for receiving responses
- `ConnectionReliabilityManager`: Network resilience
- `AutoReplySettingsStore`: Manages auto-response configurations with CloudKit sync
- `AutoReplySettingsView`: SwiftUI interface for 5 auto-response modes

### 2. Node.js Server

**Technology Stack**: Node.js, Express, Apple Push Notification Service (APNS)

**Key Responsibilities**:
- Bridge between iOS app and Claude CLI
- HTTP API endpoint management
- Session lifecycle management
- Service discovery (Bonjour/mDNS)
- Push notification delivery via APNS
- Authentication and security

**Architecture Pattern**: Service-oriented with event-driven communication

```
Server/
├── routes/              # REST API endpoints
├── services/            # Core business logic
├── middleware/          # Express middleware
├── config/              # Configuration modules
└── utils/               # Utility functions
```

**Core Services**:
- `AICLIService`: Claude CLI process management
- `PushNotificationService`: APNS message delivery
- `SessionManager`: Active session tracking
- `MessageQueueService`: Message queuing for APNS
- `StreamParserService`: Claude output parsing
- `TelemetryService`: Performance monitoring
- `AutonomousAgent`: Enhanced auto-response system with AI integration
- `MessageAnalyzer`: Analyzes Claude output for response recommendations
- `AIResponseGenerator`: OpenAI-powered intelligent response generation
- `TrainingDataManager`: Machine learning training data collection

### 3. macOS Companion App

**Technology Stack**: Swift, SwiftUI, AppKit

**Key Responsibilities**:
- Server lifecycle management
- System tray integration
- Server status monitoring
- Configuration management
- Log viewing

**Architecture Pattern**: SwiftUI with ObservableObject

```
macOS App/
├── Models/              # Server management
├── Views/               # Menu bar UI
├── Utilities/           # System integration
└── Resources/           # Assets and config
```

## Enhanced Auto-Response System

### Auto-Response Architecture

The enhanced auto-response system provides intelligent automation with 5 distinct modes, AI-powered responses, and machine learning capabilities:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ iOS Auto-Reply  │────▶│ AutonomousAgent │────▶│ AI Integration  │
│   Settings      │     │   Orchestrator  │     │  (OpenAI API)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ CloudKit Sync   │     │ MessageAnalyzer │     │ TrainingData    │
│ Cross-Device    │     │   & Templates   │     │   Manager       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Auto-Response Modes

1. **Smart Stop**: AI determines when to halt based on completion analysis
2. **Until Completion**: Continues until task is fully complete
3. **Time-Based**: Runs for specified duration (minutes/hours)
4. **Message-Based**: Processes specific number of exchanges
5. **Hybrid**: Combines time, message, and completion criteria

### Response Selection Hierarchy

```
1. CLAUDE.md Rules    → Custom project-specific rules
2. AI Generation      → OpenAI-powered intelligent responses  
3. Template Fallback  → Predefined response templates
```

### Training Data Collection

The system automatically collects successful interactions to improve AI responses:

```
Interaction → Analysis → Storage → Training → Improved Responses
     ↓           ↓         ↓         ↓            ↓
User/Claude   Intent    Project   ML Model    Better AI
Exchange    Recognition  Data     Training   Suggestions
```

## Communication Protocols

### HTTP + APNS Architecture

**Message Flow**:
```
1. Client sends message via HTTP POST /api/chat
2. Server queues message with device token
3. Server executes Claude CLI command
4. Server sends response via APNS to device
5. iOS app receives push notification with response
```

**HTTP Request Format**:
```typescript
interface ChatRequest {
  message: string;         // User message
  projectPath?: string;    // Working directory
  sessionId?: string;      // Existing session
  deviceToken: string;     // APNS device token
}
```

**APNS Payload**:
```typescript
interface APNSPayload {
  aps: {
    alert: string;         // Notification text
    badge?: number;        // App badge count
    sound?: string;        // Notification sound
  };
  sessionId: string;       // Session identifier
  messageId: string;       // Message identifier
  content: string;         // Claude response
  type: 'response' | 'error' | 'stream';
}
```

### REST API

**Core Endpoints**:
```
GET  /health                         # Server health check
POST /api/chat                       # Send message to Claude
GET  /api/projects                   # List available projects
GET  /api/sessions                   # Active sessions
GET  /api/sessions/:id/status        # Session status
POST /api/sessions/:id/keepalive     # Keep session alive
POST /api/devices/register           # Register for APNS
GET  /api/telemetry                  # Performance metrics
```

**Authentication**: Bearer token in Authorization header

## Data Flow

### Message Flow (User → Claude)

```
1. User types message in iOS app
2. iOS sends HTTP POST to /api/chat
3. Server validates and queues message
4. Server executes Claude CLI command
5. Claude processes the request
6. Response sent via APNS to device
7. iOS app receives push notification
```

### Response Delivery

```
Claude Output → StreamParser → APNS Service → iOS Device
     ↓              ↓              ↓             ↓
  Raw text    Structured     Push payload   Notification
             response                       received
```

### Session Management

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Active    │────▶│   Timeout   │────▶│   Cleanup   │
│  Sessions   │     │  Tracking   │     │   Process   │
└─────────────┘     └─────────────┘     └─────────────┘
```

## State Management

### Server State

**Session Lifecycle**:
```
Created → Active → Idle → Expired/Closed
           ↓        ↓         ↓
      Keep-alive  Timeout  Cleanup
```

**Session Tracking**:
- Active session map in memory
- Timeout monitoring per session
- Keep-alive endpoint for extension
- Automatic cleanup on expiry

### iOS State

**Request States**:
```
Ready → Sending → Awaiting Push → Received → Displayed
           ↓            ↓             ↓
        Failed      Timeout       Error
```

**Push Notification States**:
```
Registered → Token Active → Receiving → Processing
                ↓               ↓           ↓
            Expired         Failed     Displayed
```

## Security Architecture

### Authentication Flow

```
1. Server generates auth token
2. Token stored in macOS Keychain
3. iOS app receives token via:
   - QR code scan
   - Manual entry
   - Bonjour TXT record
4. Token included in all requests
```

### Security Measures

- **Transport**: HTTPS with optional TLS certificates
- **Authentication**: Bearer token validation
- **Session Isolation**: Separate Claude CLI processes
- **Input Validation**: Message sanitization
- **Rate Limiting**: API endpoint rate limits
- **Permission Control**: Configurable Claude CLI tools
- **APNS Security**: Certificate-based authentication

## Performance Optimizations

### Response Optimization
- Efficient APNS payload formatting
- Message batching for multiple responses
- Priority-based delivery
- Payload size optimization

### API Performance
- Request queuing and throttling
- Async processing with callbacks
- Connection pooling for Claude CLI
- Resource usage monitoring

### Caching Strategy
- In-memory session cache
- Message buffer persistence
- Client-side message cache
- Configuration caching

### Resource Management
- Process lifecycle management
- Memory usage monitoring
- Automatic session cleanup
- Log rotation

## Scalability Considerations

### Horizontal Scaling
- Stateless REST endpoints
- Session management via shared state
- APNS delivery from any instance
- Load balancer compatible

### Vertical Scaling
- Configurable worker processes
- Adjustable memory limits
- Resource pooling
- Concurrent session limits

## Monitoring and Observability

### Metrics Collection
```
- API metrics (requests, latency, errors)
- Push notification metrics (sent, delivered, failed)
- Session metrics (active, created, expired)
- Claude CLI metrics (executions, duration, errors)
- Resource metrics (CPU, memory, processes)
```

### Logging Strategy
- Structured JSON logging
- Log levels (debug, info, warn, error)
- Contextual information
- Log aggregation ready

### Health Checks
- Server process health
- Claude CLI availability
- APNS service connectivity
- Resource thresholds

## Error Handling

### Error Categories
1. **Network Errors**: API failures, timeouts
2. **Process Errors**: Claude CLI crashes, spawn failures
3. **Push Errors**: APNS delivery failures, invalid tokens
4. **Validation Errors**: Invalid input, auth failures
5. **System Errors**: Resource exhaustion, permissions

### Recovery Strategies
- API request retry with backoff
- Claude CLI process restart
- APNS token refresh
- Session recovery
- Graceful error responses

## Future Architecture Considerations

### Planned Enhancements
1. **Redis Integration**: Distributed session storage
2. **Message Queue**: RabbitMQ/Kafka for reliability
3. **Microservices**: Service decomposition
4. **API Gateway**: Centralized routing
5. **Kubernetes**: Container orchestration

### Extensibility Points
- Plugin system for custom tools
- Webhook support for integrations
- Custom authentication providers
- Alternative AI model support
- Multi-language support

## Development Workflow

### Local Development
```
1. Start server: npm run dev
2. Launch macOS app from Xcode
3. Run iOS app in simulator
4. Use debug logging for troubleshooting
```

### Testing Strategy
- Unit tests for business logic
- Integration tests for API
- E2E tests for critical flows
- Performance benchmarks
- Load testing

### Deployment Pipeline
```
Code → Test → Build → Package → Deploy → Monitor
  ↓      ↓      ↓        ↓        ↓        ↓
Git   Jest   npm    Electron  PM2    Datadog
      XCTest build    App            (future)
```

## Conclusion

The AICLI Companion architecture prioritizes:
- **Reliability**: Through managed sessions and APNS delivery
- **Performance**: Via async processing and push notifications
- **Security**: With authentication and process isolation
- **User Experience**: Through native apps and push updates
- **Maintainability**: With clear separation of concerns

This architecture provides a solid foundation for current needs while remaining flexible for future enhancements.

---

**Last Updated**: 2025-09-11  
**Architecture Version**: 2.1.0