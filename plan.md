# Claude Companion - Simplified Message Flow Architecture

## Development Guidelines

### Core Principles
1. **No Random Fallbacks**: Never add arbitrary default values or fallback behaviors. If something is unclear, ask for clarification or mark with a TODO comment.

2. **Ask Questions Sparingly**: 
   - Only interrupt for showstoppers (e.g., missing critical dependencies, architectural decisions)
   - For non-blocking issues, add descriptive TODO comments and continue
   - Batch questions when possible to minimize interruptions

3. **No Invented Functionality**:
   - Only implement what's explicitly requested or clearly needed
   - Don't add "nice-to-have" features without discussion
   - Stick to fixing the identified problems

4. **Clear TODOs for Unclear Areas**:
   ```javascript
   // TODO: [QUESTION] Should we limit message history size to prevent memory issues?
   // Current assumption: store all messages, but may need pagination
   // Questions: 
   // - Max messages per session?
   // - Should old messages be archived?
   ```

5. **Descriptive Comments for Complex Logic**:
   ```javascript
   // IMPLEMENTATION NOTE: Persisting messages to disk on each buffer update
   // Alternative considered: Batch writes every N seconds for performance
   // Decision: Immediate persistence ensures no data loss on crashes
   ```

## TODO Tracking Guidelines
Throughout implementation, TODOs will be marked with:
- `TODO: [BLOCKING]` - Must be resolved before continuing
- `TODO: [QUESTION]` - Need user input, but can continue
- `TODO: [OPTIMIZE]` - Performance improvement opportunity
- `TODO: [RESEARCH]` - Need to investigate best approach

## Quality Standards

### Code Quality
- All tests must pass before marking a phase complete
- Maintain >80% code coverage
- Zero linting errors allowed
- Proper error handling and logging
- Consistent code style throughout

### Documentation Standards
- Every new API endpoint must be documented
- Complex functions need JSDoc comments
- Configuration changes must update README
- Architecture decisions should be recorded

### Testing Requirements
- Unit tests for all new functionality
- Integration tests for API endpoints
- Error scenarios must be tested
- Performance impact should be measured

---

## Simplified Architecture: Server as Stateless Message Router

### Core Architecture Principles

1. **Server is a Pure Message Router**
   - No session management
   - No state persistence
   - No welcome messages or session tracking
   - Just routes messages between iOS app and Claude CLI

2. **Claude CLI is Source of Truth**
   - Claude manages all session state
   - Claude generates session IDs
   - Server passes through whatever Claude returns

3. **iOS App Manages State**
   - Stores session IDs locally
   - Manages conversation history
   - Handles project context

4. **Project Path as Initial Context**
   - First message includes project path
   - No session ID on first message
   - Claude returns session ID in response
   - Subsequent messages use that session ID

### Message Flow Walkthrough

#### Server Startup
1. Server starts on configured port (3001)
2. Broadcasts connection URL to network
3. Makes root directory available for listing
4. NO welcome messages sent
5. NO session initialization

#### iOS App Connection
1. App discovers server via broadcast
2. Connects to WebSocket endpoint
3. Requests folder list from root directory via `/api/projects`
4. NO session creation on connection
5. NO welcome message received

#### Project Selection
1. User selects project folder in iOS app
2. App stores project path locally
3. NO notification sent to server
4. NO session created on server
5. Chat view opens with empty conversation

#### First Message (No Session)
```javascript
// iOS sends:
{
  type: "claudeCommand",
  requestId: "req-123",
  data: {
    sessionId: null,  // No session yet
    command: "Help me understand this codebase",
    projectPath: "/Users/michael/project"
  }
}

// Server processes:
1. Receives message with null sessionId
2. Runs: claude --output-format json "Help me understand this codebase"
3. Claude creates session internally, returns session ID
4. Server extracts session ID from Claude response
5. Passes response back to iOS with session ID

// iOS receives:
{
  type: "claudeResponse",
  requestId: "req-123",
  data: {
    sessionId: "claude-session-abc123",  // Claude's session ID
    content: "I'll help you understand this codebase...",
    success: true
  }
}

// iOS stores session ID for future messages
```

#### Continued Conversation (With Session)
```javascript
// iOS sends:
{
  type: "claudeCommand",
  requestId: "req-456",
  data: {
    sessionId: "claude-session-abc123",  // Using Claude's session ID
    command: "What does the main function do?",
    projectPath: "/Users/michael/project"
  }
}

// Server processes:
1. Receives message with sessionId
2. Runs: claude --session-id claude-session-abc123 --output-format json "What does the main function do?"
3. Claude continues existing conversation
4. Server passes response back to iOS

// iOS receives:
{
  type: "claudeResponse",
  requestId: "req-456",
  data: {
    sessionId: "claude-session-abc123",
    content: "The main function in this codebase...",
    success: true
  }
}
```

#### Parallel Fresh Chats
```javascript
// Chat A sends (no session):
{
  type: "claudeCommand",
  requestId: "chat-a-001",
  data: {
    sessionId: null,
    command: "Explain the auth system",
    projectPath: "/Users/michael/auth-project"
  }
}

// Chat B sends (no session) - SIMULTANEOUSLY:
{
  type: "claudeCommand",
  requestId: "chat-b-001",
  data: {
    sessionId: null,
    command: "Debug this error",
    projectPath: "/Users/michael/debug-project"
  }
}

// Server handles both in parallel:
- Each gets its own Claude process
- Each gets unique session ID from Claude
- RequestId ensures responses route to correct chat

// Chat A receives:
{
  type: "claudeResponse",
  requestId: "chat-a-001",  // Routes to Chat A
  data: {
    sessionId: "claude-session-xyz789",
    content: "The authentication system..."
  }
}

// Chat B receives:
{
  type: "claudeResponse",
  requestId: "chat-b-001",  // Routes to Chat B
  data: {
    sessionId: "claude-session-def456",
    content: "Looking at the error..."
  }
}
```

#### Memory Reset
```javascript
// iOS sends clear request:
{
  type: "clearChat",
  requestId: "req-789",
  data: {
    sessionId: "claude-session-abc123"
  }
}

// Server responds (no actual cleanup):
{
  type: "clearChat",
  requestId: "req-789",
  data: {
    success: true,
    oldSessionId: "claude-session-abc123",
    newSessionId: null,  // iOS will get new one on next message
    message: "Ready for new conversation"
  }
}

// Next message starts fresh (no session ID)
```

### What Server Does NOT Do

1. **No Session Management**
   - Doesn't create sessions
   - Doesn't track active sessions
   - Doesn't persist session state
   - Doesn't manage session lifecycle

2. **No Message Buffering**
   - Doesn't store messages
   - Doesn't queue messages
   - Doesn't track conversation history

3. **No Client State Tracking**
   - Doesn't track which project is selected
   - Doesn't know client navigation state
   - Doesn't manage client sessions

4. **No Welcome Messages**
   - No initialization handshake
   - No capability announcements
   - No session setup

### What Server DOES Do

1. **Routes Messages**
   - Receives WebSocket messages
   - Passes to Claude CLI
   - Returns Claude's response
   - Uses requestId for routing

2. **Provides Directory Listing**
   - `/api/projects` endpoint for folder listing
   - Basic file system access for project selection

3. **Runs Claude CLI**
   - Executes claude commands
   - Passes through session IDs
   - Returns raw responses

4. **Maintains WebSocket Connection**
   - Keeps connection alive
   - Handles ping/pong
   - Basic connection management

### Implementation Checklist

#### Phase 1: Remove Server State Management ✅
- [x] Remove session creation from streamStart
- [x] Remove session tracking from claudeCommand  
- [x] Remove session management from connection manager
- [x] Remove welcome message with capabilities
- [x] Remove 'sessions' meta-command

#### Phase 2: Simplify Message Handlers 🚧
- [ ] Remove all session lifecycle management
- [ ] Remove message buffering and queuing
- [ ] Remove session persistence calls
- [ ] Simplify to pure message routing

#### Phase 3: Clean iOS App 🚧
- [ ] Remove project start notifications
- [ ] Remove session pre-creation
- [ ] Use requestId for message routing
- [ ] Store Claude session IDs locally

#### Phase 4: Testing & Validation 🚧
- [ ] Test parallel message handling
- [ ] Test session ID flow
- [ ] Test memory reset
- [ ] Verify no state persistence

### Success Metrics

1. **Zero State on Server**
   - Server can restart without losing context
   - No session files created
   - No memory of past conversations

2. **Reliable Message Routing**
   - RequestId ensures correct routing
   - Parallel messages work correctly
   - No message loss or confusion

3. **Simple Architecture**
   - < 50% of current code complexity
   - Easy to understand and maintain
   - No hidden state management

4. **iOS App Independence**
   - App manages all its own state
   - No dependency on server memory
   - Can work with any compliant server

### Migration Notes

Current issues to fix:
1. Server still sends welcome messages
2. Server still has session management code
3. iOS app still notifies server of project selection
4. Message handlers still track state

Next steps:
1. Remove all remaining session management
2. Simplify handlers to pure passthrough
3. Update iOS to stop project notifications
4. Test parallel message scenarios