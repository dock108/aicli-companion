# System Architecture Overview

Claude Companion is a distributed system that enables mobile access to Claude Code CLI through a secure, real-time architecture.

## System Components

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│ Companion Server │────▶│ Claude Code CLI │
│   (Swift)       │◀────│    (Node.js)     │◀────│   (Process)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │                         │
        │                        │                         │
    WebSocket               HTTP/WS API              Spawn Process
    Connection              + Bonjour                + Stdio Pipes
```

## Core Architecture Principles

### 1. **Separation of Concerns**
- **iOS App**: User interface and experience
- **Companion Server**: API gateway and session management
- **Claude CLI**: AI processing and tool execution

### 2. **Real-time Communication**
- WebSocket for bidirectional streaming
- Server-Sent Events for one-way updates
- HTTP REST for stateless operations

### 3. **Security First**
- Token-based authentication
- TLS encryption for all communications
- Session isolation and sandboxing
- Permission management system

### 4. **Scalability**
- Stateless server design
- Session-based resource management
- Horizontal scaling support (future)

## Data Flow

### Request Flow
1. User sends message in iOS app
2. App sends WebSocket message to server
3. Server spawns/reuses Claude CLI process
4. Server pipes message to Claude stdin
5. Claude processes and responds
6. Server streams response back to app
7. App renders response in real-time

### Session Management
```
┌─────────────┐
│   Client    │
└─────┬───────┘
      │ Connect + Auth
      ▼
┌─────────────┐     ┌──────────────┐
│   Server    │────▶│ Session Pool │
└─────────────┘     └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ Claude Process│
                    └──────────────┘
```

## Technology Stack

### iOS App
- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Networking**: URLSession, Starscream (WebSocket)
- **Storage**: UserDefaults, Keychain
- **Min iOS**: 15.0

### Companion Server
- **Runtime**: Node.js 18+
- **Framework**: Express.js
- **WebSocket**: ws library
- **Process Management**: child_process
- **Service Discovery**: bonjour-service

### Desktop Host App
- **Framework**: Tauri 2.0
- **Frontend**: Vanilla JavaScript
- **Backend**: Rust
- **UI**: Web technologies (HTML/CSS/JS)

## Key Design Patterns

### 1. **Gateway Pattern**
The companion server acts as an API gateway, abstracting the complexity of Claude CLI interaction from the mobile client.

### 2. **Observer Pattern**
Real-time updates use WebSocket subscriptions, allowing multiple clients to observe session state changes.

### 3. **Command Pattern**
All Claude interactions are encapsulated as commands with consistent request/response formats.

### 4. **Circuit Breaker**
Automatic failover and recovery for Claude CLI process failures.

## Deployment Architecture

### Development
```
┌──────────┐     ┌──────────┐
│ iOS Sim  │────▶│  Local   │
│          │◀────│  Server  │
└──────────┘     └──────────┘
                      │
                  Claude CLI
```

### Production
```
┌──────────┐     ┌──────────┐     ┌──────────┐
│ iOS App  │────▶│  Server  │────▶│  Claude  │
│ (Device) │◀────│  (Cloud) │◀────│   CLI    │
└──────────┘     └──────────┘     └──────────┘
     │                │
     └── TLS ────────┘
```

## Performance Considerations

### Latency Optimization
- WebSocket connection pooling
- Response streaming vs buffering
- Intelligent session reuse
- Client-side response caching

### Resource Management
- Process lifecycle management
- Memory limits per session
- Automatic session timeout
- Connection throttling

## Security Architecture

### Authentication Flow
1. Server generates secure token
2. Client stores token in Keychain
3. Token sent with each request
4. Server validates before processing

### Data Protection
- No persistent storage of conversations
- Memory-only session data
- Encrypted transport (TLS)
- Input sanitization

## Extensibility

### Plugin Architecture (Future)
- Tool extensions for Claude
- Custom UI components
- Third-party integrations
- Webhook support

### API Versioning
- Semantic versioning
- Backward compatibility
- Feature flags
- Graceful degradation

## Monitoring & Observability

### Health Checks
- Server health endpoint
- Claude CLI availability
- Session metrics
- Resource usage

### Logging
- Structured logging (JSON)
- Log levels and filtering
- Error tracking
- Performance metrics

---

**Last Updated**: 2025-07-27