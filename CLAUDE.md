# Claude Companion Development Rules

This document contains the coding standards, guidelines, and architectural principles that must be followed when working on the Claude Companion project.

## Core Development Principles

### 1. No Random Fallbacks
- Never add arbitrary default values or fallback behaviors
- If something is unclear, ask for clarification or mark with a TODO comment
- Don't make assumptions about missing data or behavior

### 2. Ask Questions Sparingly
- Only interrupt for showstoppers (e.g., missing critical dependencies, architectural decisions)
- For non-blocking issues, add descriptive TODO comments and continue
- Batch questions when possible to minimize interruptions

### 3. No Invented Functionality
- Only implement what's explicitly requested or clearly needed
- Don't add "nice-to-have" features without discussion
- Stick to fixing the identified problems
- Avoid feature creep

### 4. Clear TODOs for Unclear Areas
```javascript
// TODO: [QUESTION] Should we limit message history size to prevent memory issues?
// Current assumption: store all messages, but may need pagination
// Questions: 
// - Max messages per session?
// - Should old messages be archived?
```

### 5. Descriptive Comments for Complex Logic
```javascript
// IMPLEMENTATION NOTE: Persisting messages to disk on each buffer update
// Alternative considered: Batch writes every N seconds for performance
// Decision: Immediate persistence ensures no data loss on crashes
```

## TODO Tracking Standards

All TODOs must be marked with specific tags:
- `TODO: [BLOCKING]` - Must be resolved before continuing
- `TODO: [QUESTION]` - Need user input, but can continue
- `TODO: [OPTIMIZE]` - Performance improvement opportunity
- `TODO: [RESEARCH]` - Need to investigate best approach

## Quality Standards

### Code Quality Requirements
- All tests must pass before marking any feature complete
- Maintain >80% code coverage
- Zero linting errors allowed (run SwiftLint for iOS/macOS, ESLint for server)
- Proper error handling and logging at all levels
- Consistent code style throughout the codebase

### Documentation Standards
- Every new API endpoint must be documented in API.md
- Complex functions need JSDoc comments explaining parameters and return values
- Configuration changes must update README.md
- Architecture decisions should be recorded in relevant documentation
- Keep documentation in sync with code changes

### Testing Requirements
- Unit tests for all new functionality
- Integration tests for API endpoints
- Error scenarios must be tested explicitly
- Performance impact should be measured for critical paths
- Test both success and failure cases

## Architecture Principles

### Server as Stateless Message Router
1. **No State Management**
   - Server doesn't create or manage sessions
   - Server doesn't track active sessions
   - Server doesn't persist session state
   - Server doesn't manage session lifecycle

2. **Pure Message Routing**
   - Receives WebSocket messages from iOS app
   - Passes messages to Claude CLI
   - Returns Claude's response unchanged
   - Uses requestId for proper message routing

3. **No Message Buffering**
   - Doesn't store messages
   - Doesn't queue messages
   - Doesn't track conversation history
   - Doesn't cache responses

4. **No Welcome Messages**
   - No initialization handshake
   - No capability announcements
   - No session setup on connection
   - No automatic messages

### Claude CLI as Source of Truth
- Claude manages all session state internally
- Claude generates and owns session IDs
- Server passes through whatever Claude returns
- No modification of Claude responses

### iOS App Manages State
- Stores session IDs locally
- Manages conversation history
- Handles project context
- Maintains UI state independently

### Project Path as Initial Context
- First message includes project path
- No session ID on first message
- Claude returns session ID in response
- Subsequent messages use that session ID

## Server Implementation Rules

### What Server MUST NOT Do
1. Create or manage sessions
2. Store or buffer messages
3. Track client state or navigation
4. Send welcome or initialization messages
5. Modify Claude responses
6. Maintain conversation history
7. Track project selections

### What Server MUST Do
1. Route messages between iOS and Claude CLI
2. Provide directory listing via `/api/projects`
3. Execute Claude CLI commands faithfully
4. Pass through session IDs unchanged
5. Use requestId for response routing
6. Maintain WebSocket connections
7. Handle errors gracefully

## iOS/macOS App Standards

### UI Design Principles
- Follow native Apple Human Interface Guidelines
- Maintain consistent spacing and alignment
- Use standard macOS/iOS controls appropriately
- Ensure proper visual hierarchy
- Keep layouts clean and uncluttered

### SwiftUI Best Practices
- Use `@EnvironmentObject` for shared state
- Implement proper `@Published` properties for reactive UI
- Follow MVVM architecture pattern
- Use appropriate view modifiers for layout
- Maintain view composition over complex views

### Settings Organization
- Basic settings belong in General tab, not Advanced
- Group related settings logically
- Use clear, descriptive labels
- Provide helpful descriptions where needed
- Advanced tab only for technical/risky settings

### Error Handling
- Show user-friendly error messages
- Log technical details for debugging
- Provide recovery suggestions when possible
- Never crash on recoverable errors
- Handle network failures gracefully

## Code Style Guidelines

### JavaScript/Node.js (Server)
- Use ES6+ features appropriately
- Async/await over callbacks
- Proper error handling with try/catch
- Meaningful variable names
- Consistent indentation (2 spaces)
- Semicolons required
- Single quotes for strings

### Swift (iOS/macOS)
- Follow SwiftLint rules
- Use guard statements for early returns
- Prefer `let` over `var` when possible
- Use meaningful property and method names
- Document public APIs
- Keep functions focused and small
- Use extensions to organize code

## Testing Standards

### Unit Tests
- Test individual functions/methods
- Mock external dependencies
- Test edge cases and error conditions
- Use descriptive test names
- Keep tests independent
- Fast execution required

### Integration Tests
- Test complete workflows
- Verify API contracts
- Test with real dependencies where appropriate
- Ensure proper cleanup after tests
- Test concurrent operations
- Verify error propagation

## Performance Guidelines

- Profile before optimizing
- Measure impact of changes
- Avoid premature optimization
- Document performance-critical code
- Consider memory usage
- Monitor for memory leaks
- Test with realistic data volumes

## Security Considerations

- Never log sensitive information
- Validate all input data
- Sanitize user-provided content
- Use secure communication protocols
- Follow principle of least privilege
- Regular security audits
- Keep dependencies updated

## Version Control Rules

- Write clear, descriptive commit messages
- Keep commits focused and atomic
- Test before committing
- Never commit broken code to main
- Use feature branches for development
- Squash commits when merging
- Update documentation with code changes

## Debugging Guidelines

- Use proper logging levels (debug, info, warn, error)
- Include context in log messages
- Log at appropriate verbosity
- Remove or disable debug logs in production
- Use breakpoints over console.log debugging
- Profile performance issues
- Document known issues

## Success Metrics

### Code Quality Metrics
- Zero linting errors
- >80% test coverage
- All tests passing
- No critical security issues
- Clean dependency audit

### Architecture Metrics
- Server remains stateless
- No session files created
- RequestId routing works reliably
- Parallel messages handled correctly
- No message loss or confusion

### User Experience Metrics
- Responsive UI
- Clear error messages
- Intuitive navigation
- Consistent behavior
- Fast response times

## Remember

- **Simplicity over complexity**: Choose the simpler solution when possible
- **Clarity over cleverness**: Write code that's easy to understand
- **Consistency over perfection**: Follow existing patterns in the codebase
- **User needs over developer preferences**: Build what users need, not what's fun to build
- **Quality over speed**: Take time to do things right the first time

When in doubt, refer back to these principles and ask for clarification rather than making assumptions.