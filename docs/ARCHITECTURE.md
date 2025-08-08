# Claude Companion Architecture

## System Overview

Claude Companion is a distributed system consisting of three primary components that work together to provide AI assistance through a native mobile experience:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│  Node.js Server │────▶│  AICLI (Claude) │
│  (SwiftUI)      │◀────│   (Express)     │◀────│                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         ▲                       ▲
         │                       │
         └───────────────────────┘
              WebSocket/REST
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
- `WebSocketService`: Manages real-time communication
- `ChatSessionManager`: Handles conversation state
- `MessagePersistenceService`: Local storage with CoreData
- `PushNotificationService`: APNS integration
- `ConnectionReliabilityManager`: Network resilience

### 2. Node.js Server

**Technology Stack**: Node.js, Express, WebSocket (ws), EventEmitter

**Key Responsibilities**:
- Bridge between iOS app and AICLI
- WebSocket connection management
- Session and message persistence
- Service discovery (Bonjour/mDNS)
- Push notification relay
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
- `AICLIService`: AICLI process management
- `WebSocketService`: Client connection handling
- `SessionPersistenceService`: Session/message storage
- `MessageQueueService`: Reliable message delivery
- `StreamParserService`: AICLI output parsing
- `TelemetryService`: Performance monitoring

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

## Communication Protocols

### WebSocket Protocol

**Connection Flow**:
```
1. Client connects with auth token and device ID
2. Server sends welcome message with session info
3. Client subscribes to events
4. Bidirectional message flow begins
```

**Message Format**:
```typescript
interface WebSocketMessage {
  type: string;          // Message type identifier
  requestId?: string;    // Client request tracking
  data: any;            // Payload
  error?: Error;        // Error information
}
```

**Message Types**:
- `welcome`: Initial connection confirmation
- `sendCommand`: User message to Claude
- `streamData`: Streaming response chunks
- `assistantMessage`: Complete response
- `sessionStatus`: Session state updates
- `error`: Error notifications
- `heartbeat`: Connection keep-alive

### REST API

**Endpoints**:
```
GET  /health                    # Server health check
GET  /api/info                  # Server capabilities
GET  /api/projects              # List available projects
POST /api/projects/:name/start  # Start Claude session
GET  /api/sessions              # Active sessions
POST /api/sessions/continue     # Continue existing session
GET  /api/telemetry            # Performance metrics
```

**Authentication**: Bearer token in Authorization header

## Data Flow

### Message Flow (User → Claude)

```
1. User types message in iOS app
2. iOS sends via WebSocket to server
3. Server validates and queues message
4. Server sends to AICLI subprocess
5. AICLI processes with Claude
6. Response streams back through same path
```

### Stream Processing

```
AICLI Output → StreamParser → ChunkValidator → WebSocket → iOS App
     ↓              ↓              ↓                ↓
  Raw text    Structured     Validated      Real-time
             chunks         content       updates
```

### Session Persistence

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Memory    │────▶│    Disk     │────▶│   Restore   │
│   Cache     │     │   Storage   │     │  on Start   │
└─────────────┘     └─────────────┘     └─────────────┘
```

## State Management

### Server State

**Session Lifecycle**:
```
Created → Active → Idle → Expired/Closed
           ↓        ↓
      Persisted  Restored
```

**Message Buffer**:
- In-memory circular buffer per session
- Persisted to disk on each update
- Configurable size limits
- Automatic cleanup on expiry

### iOS State

**Connection States**:
```
Disconnected → Connecting → Connected → Reconnecting
                              ↓             ↑
                          Authenticated ─────┘
```

**Message States**:
```
Pending → Sending → Sent → Delivered → Read
            ↓         ↓
         Failed   Acknowledged
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

- **Transport**: Optional TLS encryption
- **Authentication**: Bearer token validation
- **Session Isolation**: Separate AICLI processes
- **Input Validation**: Message sanitization
- **Rate Limiting**: Connection and message limits
- **Permission Control**: Configurable AICLI tools

## Performance Optimizations

### Message Streaming
- Chunked transfer encoding
- Stream backpressure handling
- Empty chunk filtering
- Adaptive buffer sizing

### Connection Management
- Connection pooling
- Automatic reconnection
- Exponential backoff
- Heartbeat monitoring

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
- Session affinity for WebSockets
- Distributed session storage (future)
- Load balancer compatible

### Vertical Scaling
- Configurable worker processes
- Adjustable memory limits
- Resource pooling
- Concurrent session limits

## Monitoring and Observability

### Metrics Collection
```
- Connection metrics (count, duration, errors)
- Message metrics (sent, received, failed)
- Session metrics (active, created, expired)
- Performance metrics (latency, throughput)
- Resource metrics (CPU, memory, disk)
```

### Logging Strategy
- Structured JSON logging
- Log levels (debug, info, warn, error)
- Contextual information
- Log aggregation ready

### Health Checks
- Server process health
- AICLI availability
- Database connectivity
- Resource thresholds

## Error Handling

### Error Categories
1. **Network Errors**: Connection failures, timeouts
2. **Process Errors**: AICLI crashes, spawn failures
3. **Validation Errors**: Invalid input, auth failures
4. **System Errors**: Resource exhaustion, permissions

### Recovery Strategies
- Automatic reconnection
- Process restart
- Message retry with backoff
- Graceful degradation
- Circuit breaker pattern

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

The Claude Companion architecture prioritizes:
- **Reliability**: Through persistent sessions and message queuing
- **Performance**: Via streaming and efficient state management
- **Security**: With authentication and isolation
- **User Experience**: Through native apps and real-time updates
- **Maintainability**: With clear separation of concerns

This architecture provides a solid foundation for current needs while remaining flexible for future enhancements.