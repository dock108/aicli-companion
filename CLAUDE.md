# Development Guidelines

## Core Principles

### 1. User First
- Always prioritize what the user is asking for
- Don't assume or execute plans/issues unless explicitly requested
- Respond conversationally to greetings and questions

### 2. Keep It Simple
- Choose simple solutions over complex ones
- Don't add features that weren't requested
- Write clear, readable code

### 3. Ask When Unclear
- Only interrupt for critical blockers
- Add TODO comments for non-blocking questions
- Batch questions to minimize interruptions

### 4. Follow Existing Patterns
- Match the codebase's existing style
- Use the frameworks already in the project
- Don't introduce new dependencies without discussion

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

### Technical Stack
- **iOS/macOS**: SwiftUI, CloudKit (optional)
- **Server**: Node.js, Express, WebSocket
- **Testing**: >80% coverage requirement

## Remember
- Do what's asked, nothing more
- The user knows their priorities
- Simple working code beats perfect architecture

---
**Version**: 3.0.0  
**Last Updated**: 2025-08-22