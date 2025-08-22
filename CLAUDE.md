# AICLI Companion Development Guidelines

**IMPORTANT: This document contains critical instructions that MUST be followed when working on this codebase. Read this ENTIRE document before making any changes.**

## Priority Documents

### 1. Check for Active Plans and Issues
**ALWAYS check BOTH `plan.md` in root AND `issues/` directory before starting work.**

#### Plans vs Issues
- **Plans (`plan.md`)**: For major features or refactoring (>1 day of work)
- **Issues (`issues/`)**: For bug fixes, minor updates, and targeted improvements (<1 day)

### 2. Working with Active Plans
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

### 3. Working with Issues
Check `issues/` directory for active issues:
1. **Ignore completed issues** (files with `complete-` prefix)
2. **Read active issues** (files without `complete-` prefix)
3. **Prioritize by**:
   - Beta Blocker: Yes issues first
   - Priority: High > Medium > Low
   - User impact severity
4. **Update issues as you work**:
   - Change Status field as you progress
   - Add investigation findings
   - Document solution implemented
   - Update "Last Updated" date
5. **When issue is resolved**:
   - Mark Status as RESOLVED ✅
   - Add resolution date
   - Rename file with `complete-` prefix

### 4. Follow These Guidelines
This document (CLAUDE.md) contains the coding standards and principles for the project. These guidelines OVERRIDE any default behavior.

## Core Development Principles

### 1. User Directives Take Precedence
- The user's explicit request in chat ALWAYS overrides default priorities
- If the user asks to work on specific issues or tasks, do those first
- Respect when the user wants "quick wins" over high-priority items
- Don't argue about priority - the user knows their time constraints

### 2. No Random Fallbacks
- Never add arbitrary default values or fallback behaviors
- If something is unclear, ask for clarification or mark with a TODO comment
- Don't make assumptions about missing data or behavior

### 3. Ask Questions Sparingly
- Only interrupt for showstoppers (e.g., missing critical dependencies, architectural decisions)
- For non-blocking issues, add descriptive TODO comments and continue
- Batch questions when possible to minimize interruptions

### 4. No Invented Functionality
- Only implement what's explicitly requested or clearly needed
- Don't add "nice-to-have" features without discussion
- Stick to fixing the identified problems
- Avoid feature creep

### 5. Clear TODOs for Unclear Areas
```javascript
// TODO: [QUESTION] Should we limit message history size to prevent memory issues?
// Current assumption: store all messages, but may need pagination
// Questions: 
// - Max messages per session?
// - Should old messages be archived?
```

### 6. Descriptive Comments for Complex Logic
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

### Creating New Issues

When documenting a bug or minor enhancement:

1. **File Naming**: `issues/[number]-[brief-description].md`
   - Use next sequential number
   - Keep description short (2-4 words)
   - Use hyphens, not spaces

2. **Use the Template**: Copy from `issues/template.md` and fill in:
   ```markdown
   # Issue #[NUMBER]: [Brief Title]
   
   **Priority**: [High/Medium/Low]  
   **Component**: [Component - Specific Area]  
   **Beta Blocker**: [Yes/No] ([reason if yes])  
   **Discovered**: [YYYY-MM-DD]  
   **Status**: [New/In Progress/Awaiting Info/RESOLVED]  
   
   ## Problem Description
   [Clear description of the issue]
   
   ## Investigation Areas
   1. [Areas to check...]
   
   ## Expected Behavior
   [What should happen instead]
   
   ## Files to Investigate
   - `path/to/file.ext` (reason)
   
   ## Root Cause Analysis
   [Once identified, document here]
   
   ## Solution Implemented
   ### 1. [Fix Category] (✅/⏳/❌)
   - [Changes made]
   
   ## Testing Requirements
   ### Manual Testing Steps
   1. [Test steps...]
   
   ## Status
   **Current Status**: [Status]  
   **Last Updated**: [YYYY-MM-DD]
   ```

3. **When Complete**:
   - Set Status to RESOLVED ✅
   - Add Resolved date
   - Document the solution
   - Rename file with `complete-` prefix

## TODO Tracking Standards

All TODOs must be marked with specific tags:
- `TODO: [BLOCKING]` - Must be resolved before continuing
- `TODO: [QUESTION]` - Need user input, but can continue
- `TODO: [OPTIMIZE]` - Performance improvement opportunity
- `TODO: [RESEARCH]` - Need to investigate best approach
- `TODO: [PLAN]` - Refers to item in plan.md

When you see a TODO tag, check if there's a plan.md that addresses it.

### Using TodoWrite Tool
- **ALWAYS use TodoWrite** for complex multi-step tasks
- **Update status immediately** when starting/completing tasks
- **Don't batch status updates** - mark complete as you go
- **Use for planning** documentation work, refactoring, or any task with 3+ steps

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

### Claude Code CLI as Session Authority  
- Claude Code CLI generates and owns session IDs
- Claude Code CLI maintains internal context and memory
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
1. Route messages between iOS and Claude Code CLI
2. Provide directory listing via `/api/projects`
3. Execute Claude Code CLI commands faithfully
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
   3. Check issues/ directory for active issues (ignore complete-* files)
   4. If plan.md exists, read it completely
   5. If active issues exist, review them for context
   6. Identify current work status
   7. Continue from appropriate point
   ```

2. **Priority Order**:
   ```
   IMPORTANT: User's explicit request in chat ALWAYS takes precedence!
   If the user asks to work on something specific, do that first.
   
   Default priority when no specific request:
   1. Active plan.md TODOs (if working on major feature)
   2. Beta Blocker issues (Priority: High)
   3. High priority issues
   4. Medium/Low priority issues
   5. User's new request
   
   Note: Sometimes the user wants to "knock out a few quick fixes" 
   rather than tackle the highest priority item. Always respect
   the user's choice of what to work on.
   ```

3. **If No Active Plan or Issues**:
   ```
   1. Ask user what they want to work on
   2. Check if it relates to existing documentation
   3. Follow these guidelines for implementation
   4. Create plan.md if task is complex (>1 day)
   5. Create issue file if task is a bug or minor update (<1 day)
   ```

4. **If Plan Exists**:
   ```
   1. Continue from next uncompleted TODO
   2. Follow plan's testing requirements
   3. Update plan as you progress
   4. Alert user if blocked
   ```

5. **If Active Issues Exist**:
   ```
   1. Work on highest priority issue
   2. Update issue status as you progress
   3. Document findings and solutions
   4. Mark as RESOLVED when complete
   5. Rename with complete- prefix
   ```

## Remember

- **Plans & Issues First**: Always check for plan.md and active issues
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
- **ALWAYS check for plan.md AND issues/ before starting any work**
- **ALWAYS update plan.md or issue files as you progress**
- **ALWAYS rename completed issues with `complete-` prefix**

## Critical Naming Conventions

- **App Name**: AICLI Companion (the product name)
- **CLI Tool**: Claude Code CLI (only when referring to the Anthropic CLI tool)
- **NEVER** use "Claude Code Companion" or "AICLI" alone
- **NEVER** use "Claude CLI" - it's always "Claude Code CLI"

## Documentation Organization

### Documentation Structure
- **ALL documentation** must be in `/docs/` directory
- **Root directory** should only contain: README.md, CHANGELOG.md, CLAUDE.md, LICENSE
- **No archive folders** during beta - we're iterating rapidly
- **Consolidate related docs** - avoid scattered documentation across subdirectories

### When Moving/Organizing Documentation
1. Check for duplicates and remove them
2. Update all cross-references and links
3. Maintain clear subdirectory structure in `/docs/`
4. Verify all links work after reorganization

## Testing and Linting Discipline

### Before Marking Work Complete
1. **Run linting** (ESLint for server, SwiftLint for iOS/macOS)
2. **Fix all linting errors** - use `--fix` when available
3. **Run tests** to ensure nothing broke
4. **Verify documentation** links if docs were changed

### ESLint/Prettier Integration
- Server uses both ESLint and Prettier
- Always run `npx eslint . --fix` in server directory
- Formatting issues are errors, not warnings

---

**Document Version**: 2.2.0  
**Last Updated**: 2025-08-22  
**Status**: Active Development Guidelines