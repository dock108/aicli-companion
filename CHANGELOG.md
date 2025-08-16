# Changelog

All notable changes to AICLI Companion will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-08-09

### Added
- Initial release of AICLI Companion
- iOS app with native SwiftUI interface
- Companion server for bridging iOS app with Claude CLI
- HTTP + APNS architecture for message delivery
- Push notifications for Claude responses
- Session management with timeout tracking
- Project directory browsing and selection
- REST API for chat and session management
- Service discovery via Bonjour/mDNS
- TLS encryption and token-based authentication
- Tauri-based desktop host app for easy server management
- Comprehensive test coverage
- Full documentation

### Features
- **iOS App**
  - Chat interface with message bubbles
  - Real-time response streaming
  - Project selection and management
  - Session continuation on app relaunch
  - Push notification support
  - Settings management
  - Dark mode support
  - Accessibility features

- **Server**
  - Claude Code CLI integration
  - WebSocket and REST APIs
  - Stream parsing for structured responses
  - Permission handling
  - Process management
  - Service discovery broadcasting

- **Security**
  - Token-based authentication
  - TLS/SSL support
  - Configurable permission modes
  - No third-party data storage

### Known Issues
- Session context in Claude Code CLI itself may not persist between app restarts

### Features
- **Local-First Storage**: Messages stored per device with optional CloudKit cross-device sync

## [1.1.0] - 2025-08-13

### Added - Local-First Architecture
- **Local-First Message Storage**: All conversations stored locally immediately for zero message loss
- **WhatsApp/iMessage Pattern**: Messages appear instantly in UI and persist across app restarts
- **Project Switching Fix**: Complete conversation history loads correctly when switching between projects
- **Simplified Architecture**: Removed complex retry/recovery mechanisms in favor of reliable local storage
- **Offline Conversation Browsing**: Browse and read previous conversations without server connection

### Changed
- **Message Persistence**: Transitioned from server-dependent to local-first storage approach
- **Server Role**: Server now acts as pure message router without storing conversation history
- **APNS Integration**: Push notifications deliver messages to local storage rather than UI directly
- **Performance**: Removed ~300 lines of complex retry logic for simpler, more reliable operation

### Fixed
- **Message Loss on Project Switch**: Fixed ChatView loading logic to properly restore conversations
- **Session ID Management**: Improved session restoration from local metadata
- **Conversation History**: All messages now persist correctly across app lifecycle events

### Technical Improvements
- Implemented `MessagePersistenceService.appendMessage()` for reliable message storage
- Enhanced project switching logic in ChatView to load from local storage
- Simplified message flow: Local storage → HTTP request → APNS delivery → Local storage
- Added comprehensive message persistence testing framework

## [Unreleased]

### Planned
- Remove BackgroundSessionCoordinator (no longer needed with local-first architecture)
- Android app support
- Enhanced CloudKit cross-device sync
- Multiple Claude model support
- Enhanced code highlighting
- Voice input support

---

For detailed release notes, see [GitHub Releases](https://github.com/your-repo/claude-companion/releases).