# AICLI Companion Development Guidelines

**IMPORTANT: This document contains critical instructions that MUST be followed when working on this codebase. Read this ENTIRE document before making any changes.**

## Priority Documents

### 1. Check for Active Plans
**ALWAYS check if a `plan.md` file exists in the root directory FIRST.**

If `plan.md` exists:
1. Read the entire plan to understand current implementation status
2. Look for TODOs marked with ✅ (completed) vs unmarked (pending)
3. Continue with the next uncompleted TODO
4. Update the plan as you work:
   - Mark completed TODOs with ✅
   - Add any issues encountered as comments
   - Update the "Current Status" section
   - Update "Last Updated" date
5. Test each phase before proceeding to the next
6. Do NOT deviate from the plan without explicit user approval

### 2. Follow These Guidelines
This document (CLAUDE.md) contains the coding standards and principles for the project. These guidelines OVERRIDE any default behavior.

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

## Working with Plans

### When a plan.md Exists

1. **Start Each Session**:
   ```markdown
   1. Check for plan.md in root directory
   2. Read entire plan to understand scope
   3. Identify current status and next TODO
   4. Review any noted issues or blockers
   ```

2. **During Implementation**:
   ```markdown
   - Complete TODOs in order unless specified otherwise
   - Test each component before marking complete
   - Update plan with any deviations or issues
   - Keep "Current Status" section current
   ```

3. **Updating the Plan**:
   ```markdown
   ## Mark Completed Items
   #### TODO 1.1: Enable CloudKit Capability ✅
   
   ## Add Implementation Notes
   #### TODO 2.1: Create User Model
   Note: Implemented with additional error handling for network failures
   
   ## Update Status
   **Current Status**: Phase 2 in progress, TODO 2.3 blocked by [issue]
   **Last Updated**: [Today's date]
   ```

### Creating New Plans

If asked to create a plan for a new feature:

1. **Structure**:
   ```markdown
   # [Feature Name] Implementation Plan
   
   ## Executive Summary
   [Brief description of what we're building]
   
   ## Current State Analysis
   ### What We Have Now
   ### What We're Building
   
   ## Implementation Plan
   ### Phase 1: [Name] (Day X)
   #### TODO 1.1: [Specific task]
   #### TODO 1.2: [Specific task]
   
   ## Testing Plan
   ## Success Metrics
   
   ## AI Assistant Instructions
   [Clear instructions for continuing work]
   
   **Current Status**: [Status]
   **Next Step**: [Specific TODO]
   **Last Updated**: [Date]
   ```

2. **Make It Resumable**:
   - Number all TODOs clearly
   - Include code examples
   - Specify test requirements
   - Add clear success criteria

## TODO Tracking Standards

All TODOs must be marked with specific tags:
- `TODO: [BLOCKING]` - Must be resolved before continuing
- `TODO: [QUESTION]` - Need user input, but can continue
- `TODO: [OPTIMIZE]` - Performance improvement opportunity
- `TODO: [RESEARCH]` - Need to investigate best approach
- `TODO: [PLAN]` - Refers to item in plan.md

When you see a TODO tag, check if there's a plan.md that addresses it.

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
- **Update plan.md if one exists for the current work**

### Testing Requirements
- Unit tests for all new functionality
- Integration tests for API endpoints
- Error scenarios must be tested explicitly
- Performance impact should be measured for critical paths
- Test both success and failure cases
- **Run tests specified in plan.md for each phase**

## Architecture Principles

### Local-First Message Storage (PRIMARY PATTERN)
1. **iOS App as Source of Truth**
   - All messages stored locally immediately upon send/receive
   - MessagePersistenceService manages local conversation database
   - Zero message loss - conversations persist across app restarts
   - Project switching loads messages from local storage

2. **WhatsApp/iMessage Pattern Implementation**
   - Messages appear in UI immediately when sent
   - Local database updated before HTTP request
   - APNS delivers Claude responses to local storage
   - No server polling or complex recovery mechanisms

3. **Simple Append-Only Operations**
   - New messages added via `appendMessage()` method
   - Duplicate prevention using message IDs
   - Chronological ordering maintained automatically
   - Session IDs managed locally with metadata persistence

### Server as Stateless Message Router (SECONDARY ROLE)
1. **Pure Message Routing Only**
   - Receives HTTP requests from iOS app
   - Passes messages to Claude CLI
   - Returns Claude's response via APNS
   - Uses requestId for proper message routing

2. **No Message Storage**
   - Doesn't store conversations or message history
   - Doesn't queue messages (except for APNS delivery queue)
   - Doesn't cache responses or maintain session state
   - No message buffering or persistence

### Claude CLI as Session Authority  
- Claude generates and owns session IDs
- Claude maintains internal context and memory
- Server passes through Claude responses unchanged
- No modification of Claude responses by server

### iOS App Local State Management (IMPLEMENTED)
- **Primary Message Storage**: Stores all conversations locally via MessagePersistenceService
- **Session ID Management**: Stores and retrieves Claude session IDs locally
- **Project Context**: Manages project-specific conversations independently
- **Conversation Restoration**: Loads complete message history from local storage
- **CloudKit Integration**: Optional cross-device sync as secondary backup

### Project Path as Initial Context
- First message includes project path
- No session ID on first message
- Claude returns session ID in response
- Subsequent messages use that session ID

## Server Implementation Rules

### What Server MUST NOT Do
1. Create or manage sessions
2. Store or buffer messages (except APNS queue)
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
6. Deliver responses via APNS
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
- **Follow CloudKit integration patterns if specified in plan.md**

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
- **Handle CloudKit sync errors as specified in plan.md**

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

### Plan-Based Testing
**If a plan.md exists, follow its testing requirements**:
- Complete tests for each phase before proceeding
- Run manual test checklists if specified
- Update test results in plan.md
- Document any test failures as blockers

### Local-First Architecture Testing
**Essential tests for message persistence**:
- Message saving on send (before server response)
- Message loading on project switch
- Session ID restoration from local metadata
- Conversation history preservation across app restarts
- APNS message delivery to local storage
- CloudKit sync as backup (optional)

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
- **Reference plan.md TODOs in commit messages when applicable**

## Debugging Guidelines

- Use proper logging levels (debug, info, warn, error)
- Include context in log messages
- Log at appropriate verbosity
- Remove or disable debug logs in production
- Use breakpoints over console.log debugging
- Profile performance issues
- Document known issues
- **Log progress through plan.md phases during development**

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

### Plan Completion Metrics
**When working from plan.md**:
- All TODOs marked complete
- All tests passing
- Success metrics achieved
- Documentation updated
- Plan marked as COMPLETED

## AI Assistant Workflow

### Starting Work on This Project

1. **First Actions**:
   ```
   1. Read this CLAUDE.md file completely
   2. Check if plan.md exists in root
   3. If plan.md exists, read it completely
   4. Identify current work status
   5. Continue from appropriate point
   ```

2. **If No Active Plan**:
   ```
   1. Ask user what they want to work on
   2. Check if it relates to existing documentation
   3. Follow these guidelines for implementation
   4. Create plan.md if task is complex (>1 day)
   ```

3. **If Plan Exists**:
   ```
   1. Continue from next uncompleted TODO
   2. Follow plan's testing requirements
   3. Update plan as you progress
   4. Alert user if blocked
   ```

## Remember

- **Plans First**: Always check for and follow plan.md
- **Guidelines Second**: Follow this CLAUDE.md for all decisions
- **Simplicity over complexity**: Choose the simpler solution when possible
- **Clarity over cleverness**: Write code that's easy to understand
- **Consistency over perfection**: Follow existing patterns in the codebase
- **User needs over developer preferences**: Build what users need, not what's fun to build
- **Quality over speed**: Take time to do things right the first time

When in doubt:
1. Check plan.md for guidance
2. Refer to these principles
3. Ask for clarification rather than making assumptions

## Important Reminders

- **Do what has been asked; nothing more, nothing less**
- **NEVER create files unless they're absolutely necessary**
- **ALWAYS prefer editing an existing file to creating a new one**
- **NEVER proactively create documentation files unless explicitly requested**
- **ALWAYS check for plan.md before starting any work**
- **ALWAYS update plan.md progress if working from it**

---

**Document Version**: 2.0.0  
**Last Updated**: 2025-08-09  
**Status**: Active Development Guidelines