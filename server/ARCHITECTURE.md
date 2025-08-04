# Claude Companion Server - Architecture Documentation

## Overview

Claude Companion Server is a WebSocket and REST API server that bridges Claude CLI with mobile and web applications. It provides real-time communication, session management, message queuing, and push notifications.

## System Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│   iOS Client    │────▶│  Load Balancer  │────▶│   nginx Proxy   │
│                 │     │    (Optional)   │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                          │
                                                          │ HTTPS/WSS
                                                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Claude Companion Server                      │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│  │   REST API  │  │  WebSocket   │  │   Event System     │    │
│  │   (Express) │  │   Server     │  │  (EventEmitter)    │    │
│  └─────────────┘  └──────────────┘  └────────────────────┘    │
│         │                 │                    │                 │
│         ▼                 ▼                    ▼                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Service Layer                         │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │   │
│  │  │   Session    │  │   Message    │  │  Connection  │ │   │
│  │  │  Management  │  │    Queue     │  │   Manager    │ │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │   │
│  │  │     Push     │  │  Telemetry   │  │   Claude     │ │   │
│  │  │Notifications │  │   Service    │  │   Service    │ │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               ▼
                    ┌──────────────────┐
                    │   Claude CLI     │
                    │   (External)     │
                    └──────────────────┘
```

## Core Components

### 1. WebSocket Server

**Purpose**: Real-time bidirectional communication with clients

**Key Features**:
- Authentication via query parameter
- Automatic reconnection support
- Client fingerprinting for session restoration
- Message subscription system
- Heartbeat/ping-pong for connection health

**Implementation**:
```javascript
// services/websocket.js
class WebSocketService {
  constructor() {
    this.wss = new WebSocketServer({ noServer: true });
    this.setupEventHandlers();
    this.setupHeartbeat();
  }
}
```

### 2. REST API Layer

**Purpose**: Synchronous operations and management endpoints

**Endpoints**:
- `/health` - Server health status
- `/api/sessions/*` - Session management
- `/api/projects/*` - Project operations
- `/api/telemetry/*` - Metrics and monitoring
- `/api/push-notifications/*` - Push notification management

**Implementation**:
```javascript
// routes/index.js
app.use('/api/sessions', sessionRoutes);
app.use('/api/projects', projectRoutes);
app.use('/api/telemetry', telemetryRoutes);
```

### 3. Session Management

**Purpose**: Manage Claude CLI interactive sessions

**Key Features**:
- Session deduplication by working directory
- Session persistence across reconnections
- Automatic cleanup of expired sessions
- Activity tracking and timeout management

**State Management**:
```javascript
// Session State
{
  sessionId: string,
  workingDirectory: string,
  process: ChildProcess,
  isActive: boolean,
  createdAt: number,
  lastActivity: number,
  backgrounded: boolean,
  conversationStarted: boolean
}
```

### 4. Message Queue System

**Purpose**: Reliable message delivery during disconnections

**Key Features**:
- Per-session message queuing
- Delivery tracking by client
- Message validation and filtering
- Automatic expiration
- Metadata enrichment

**Queue Structure**:
```javascript
// Message Queue Entry
{
  sessionId: string,
  message: WebSocketMessage,
  timestamp: Date,
  delivered: Set<clientId>,
  expiresAt: Date,
  _queued: true,
  _queuedAt: string,
  _originalTimestamp: string
}
```

### 5. Connection Management

**Purpose**: Track and manage WebSocket connections

**Key Features**:
- Client identification and fingerprinting
- Connection history tracking
- Automatic session restoration
- Connection state persistence
- Multi-client session support

**Connection State**:
```javascript
// Connection Info
{
  clientId: string,
  deviceId: string,
  connectedAt: Date,
  sessions: Set<sessionId>,
  platform: string,
  subscriptions: Set<eventType>
}
```

### 6. Event Broadcasting System

**Purpose**: Distribute Claude output to connected clients

**Event Types**:
- `assistantMessage` - Complete Claude responses
- `streamData` - Streaming response chunks
- `humanMessage` - User input echo
- `error` - Error notifications
- `sessionStatus` - Session state changes

**Event Flow**:
```
Claude CLI → Session Manager → Event Broadcaster → WebSocket Clients
                                      ↓
                                Message Queue
```

### 7. Telemetry Service

**Purpose**: Performance monitoring and diagnostics

**Metrics Collected**:
- WebSocket connections and messages
- Session lifecycle events
- Message queue statistics
- Performance timings
- Error rates

**Data Structure**:
```javascript
{
  websocket: {
    activeConnections: number,
    totalMessages: { sent, received, failed },
    reconnections: number
  },
  sessions: {
    created, resumed, expired, active,
    duplicatesPrevented: number
  },
  messages: {
    queued, delivered, expired, filtered
  },
  performance: {
    avgMessageProcessingTime: ms,
    avgQueueDeliveryTime: ms
  }
}
```

### 8. Push Notification Service

**Purpose**: Send notifications for background sessions

**Key Features**:
- APNS integration for iOS
- Retry logic with exponential backoff
- Bad token management
- Batch notification sending
- Deep linking support

## Data Flow

### 1. Session Creation Flow

```
Client Request → REST API → Session Manager → Claude CLI Process
       ↓                           ↓
   Validation              Check Existing Sessions
       ↓                           ↓
   Response ←─────────── Create or Reuse Session
```

### 2. Message Processing Flow

```
User Input → WebSocket → Message Handler → Session Manager → Claude CLI
                              ↓
                        Message Queue
                              ↓
Claude Response → Parser → Event Broadcaster → Connected Clients
                                    ↓
                            Push Notifications (if needed)
```

### 3. Reconnection Flow

```
Client Reconnect → WebSocket → Connection Manager
                                      ↓
                            Check Connection History
                                      ↓
                            Restore Session Associations
                                      ↓
                            Deliver Queued Messages
```

## State Management

### In-Memory State

1. **Active Sessions**: Map of sessionId → session state
2. **WebSocket Clients**: Map of clientId → WebSocket connection
3. **Message Queue**: Map of sessionId → message array
4. **Connection History**: Map of deviceId → connection info
5. **Telemetry Data**: Aggregated metrics in memory

### Persistent State (Optional)

1. **Session Persistence**: File or Redis storage
2. **Connection State**: Redis or file-based
3. **Message Queue**: Redis for distributed setup
4. **Telemetry**: Time-series database

## Security Architecture

### Authentication

- **Token-based**: Bearer token in Authorization header
- **WebSocket**: Token passed as query parameter
- **Validation**: Constant-time comparison

### Authorization

- **Session Isolation**: Clients can only access their sessions
- **Directory Validation**: Path traversal prevention
- **Command Filtering**: No shell injection

### Data Protection

- **TLS/SSL**: Encrypted transport
- **Token Storage**: Environment variables only
- **No Sensitive Data Logging**: Filtered logs

## Scalability Considerations

### Current Limitations

1. **Single Instance**: Claude CLI requires single process
2. **In-Memory State**: Limits horizontal scaling
3. **File System Access**: Requires shared storage

### Scaling Strategies

1. **Vertical Scaling**: Increase server resources
2. **Session Sharding**: Distribute by project
3. **Read Replicas**: Separate read/write operations
4. **Queue Distribution**: External message queue

### Performance Optimizations

1. **Message Batching**: Group small messages
2. **Compression**: gzip for large responses
3. **Caching**: Session state caching
4. **Connection Pooling**: Reuse Claude processes

## Error Handling

### Error Categories

1. **Client Errors (4xx)**
   - Invalid requests
   - Authentication failures
   - Resource not found

2. **Server Errors (5xx)**
   - Claude CLI failures
   - System resource issues
   - Unexpected exceptions

### Error Recovery

1. **Automatic Retry**: Transient failures
2. **Circuit Breaker**: Prevent cascading failures
3. **Graceful Degradation**: Partial service availability
4. **Error Reporting**: Telemetry and logging

## Monitoring and Observability

### Health Checks

```javascript
GET /health
{
  "status": "healthy|degraded|unhealthy",
  "version": "1.0.0",
  "claudeCodeAvailable": boolean,
  "checks": {
    "database": "ok",
    "claude": "ok",
    "memory": "ok"
  }
}
```

### Logging

- **Structured Logging**: JSON format
- **Log Levels**: error, warn, info, debug
- **Correlation IDs**: Request tracking
- **PII Filtering**: No sensitive data

### Metrics

- **RED Method**: Rate, Errors, Duration
- **USE Method**: Utilization, Saturation, Errors
- **Business Metrics**: Sessions, messages, users

## Development Patterns

### Service Pattern

```javascript
class ServiceName {
  constructor(options = {}) {
    this.config = { ...defaultConfig, ...options };
    this.initialize();
  }
  
  async initialize() {
    // Setup code
  }
  
  async shutdown() {
    // Cleanup code
  }
}
```

### Event-Driven Pattern

```javascript
// Emit events for cross-service communication
this.emit('session.created', { sessionId, workingDirectory });

// Listen for events
this.on('session.expired', this.handleSessionExpired.bind(this));
```

### Error Handling Pattern

```javascript
try {
  const result = await operation();
  return { success: true, data: result };
} catch (error) {
  logger.error('Operation failed', { error, context });
  telemetry.recordError(error);
  return { success: false, error: error.message };
}
```

## Testing Strategy

### Unit Tests

- Service isolation with mocks
- Edge case coverage
- Error scenario testing
- Performance benchmarks

### Integration Tests

- API endpoint testing
- WebSocket flow testing
- Claude CLI interaction
- Push notification delivery

### End-to-End Tests

- Full user flows
- Reconnection scenarios
- Multi-client testing
- Load testing

## Future Considerations

### Planned Enhancements

1. **Multi-Model Support**: Beyond Claude
2. **Distributed Architecture**: Horizontal scaling
3. **Plugin System**: Extensible functionality
4. **Analytics Dashboard**: Usage insights

### Technical Debt

1. **TODO Items**: Marked in code for attention
2. **Optimization Opportunities**: Performance improvements
3. **Refactoring Needs**: Code organization
4. **Documentation Gaps**: API specifications

## Conclusion

Claude Companion Server provides a robust bridge between Claude CLI and client applications. The architecture emphasizes reliability, real-time communication, and graceful handling of mobile app lifecycle events. Future enhancements will focus on scalability and distributed deployment options.