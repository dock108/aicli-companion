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
- Messages are stored per device, not synced across devices

## [Unreleased]

### Planned
- Android app support
- Cloud sync for messages and settings
- Multiple Claude model support
- Enhanced code highlighting
- File upload/download capabilities
- Voice input support
- Collaborative features

---

For detailed release notes, see [GitHub Releases](https://github.com/your-repo/claude-companion/releases).