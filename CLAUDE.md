# Development Guidelines

## Core Principles

### 1. PERSISTENCE AND COMPLETION
- **NEVER GIVE UP** - Continue working until tasks are 100% complete or hit a genuine showstopper
- **REMEMBER THE GOAL** - User asked for "UNTIL COMPLETION or a showstopper"
- When stuck on one approach, try another approach
- Fix ALL test failures, don't settle for "good enough"
- 80% coverage means 80%, not 78%
- **COMPLETION MEANS**: Task is ready for user testing, evaluation, or further direction
  - Code compiles and runs without errors
  - All tests pass
  - Feature is implemented and functional
  - Ready to hand over to user for testing
  - If blocked, clearly explain the blocker for user evaluation
- **IMPORTANT**: Never move issues or documentation to 'done' or 'complete' folders until user explicitly confirms testing is complete
  - Keep issues open with status "Awaiting User Testing"
  - Only close/move when user says "testing complete" or similar confirmation

### 2. User First
- Always prioritize what the user is asking for
- Don't assume or execute plans/issues unless explicitly requested
- Execute tasks to full completion as requested
- Respond conversationally to greetings and questions

### 3. Keep It Simple
- Choose simple solutions over complex ones
- Don't add features that weren't requested
- Write clear, readable code
- But simple doesn't mean incomplete - finish the job

### 4. Ask When Unclear
- Only interrupt for critical blockers
- Add TODO comments for non-blocking questions
- Batch questions to minimize interruptions

### 5. Follow Existing Patterns
- Match the codebase's existing style
- Use the frameworks already in the project
- Don't introduce new dependencies without discussion

### 6. No Defensive Coding
- Don't add try/except blocks "just in case" 
- Don't check for conditions that shouldn't happen in normal operation
- Don't add fallback mechanisms for missing dependencies that are required
- Let failures fail fast and clearly - better than silent degradation
- Only handle errors that you can meaningfully recover from

## Project Context
This is AICLI Companion - an iOS/macOS app that provides a native interface for Claude Code CLI.

### Architecture Overview
- **iOS/macOS App**: SwiftUI native app
- **Node.js Server**: Routes messages between app and Claude Code CLI
- **Claude Code CLI**: Anthropic's official CLI tool
- **Message Flow**: App → HTTP → Server → Claude CLI → APNS → App

### Key Principles
- Server is stateless - just routes messages
- iOS app stores all conversation history locally
- Claude CLI owns session management
- Use requestId for message correlation
- Robust error handling with clear failure modes
- Comprehensive logging throughout the system

### Technical Stack
- **iOS/macOS**: SwiftUI, CloudKit (optional)
- **Server**: Node.js, Express, WebSocket
- **Testing**: >80% coverage requirement
- **Config**: Environment variables for server configuration

### Key Features
- Real-time message routing between iOS app and Claude CLI
- Session management with automatic expiry handling
- Push notification support via APNS
- WebSocket support for real-time communication
- Authentication and security middleware
- Telemetry and monitoring integration

## Post-Sprint Cleanup
After completing any sprint or major task:
- **Check for duplication** - Remove duplicate methods/functions
- **Performance review** - Profile slow operations, optimize bottlenecks
- **File cleanup** - Delete temporary files, organize outputs
- **Size check** - Monitor data files, logs, and cache growth
- **Line count review** - If files exceed ~1000 lines, consider breaking them down
- **Documentation sync** - Update README, but DO NOT move issues to done/ until user confirms
- **Test coverage** - Verify all new code has tests
- **Code quality** - Run linters, fix warnings
- **CRITICAL**: Keep issues in active folder with "Awaiting User Testing" status until user explicitly confirms testing is complete

## Remember
- Do what's asked, nothing more
- The user knows their priorities
- Simple working code beats perfect architecture

---
**Version**: 1.3.0  
**Last Updated**: 2025-09-09