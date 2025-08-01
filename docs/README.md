# Claude Companion Documentation

Welcome to the Claude Companion documentation! This comprehensive guide covers everything you need to know about using, developing, and deploying Claude Companion.

## 📚 Documentation Structure

### 🚀 Getting Started
- [Installation Guide](./getting-started/installation.md) - Complete setup instructions
- [Quick Start](./getting-started/quickstart.md) - Get running in minutes
- [Troubleshooting](./getting-started/troubleshooting.md) - Common issues and solutions

### 🏗️ Architecture
- [System Overview](./architecture/overview.md) - High-level architecture
- [Server Architecture](./architecture/server.md) - Companion server internals
- [iOS App Architecture](./architecture/ios-app.md) - Mobile app structure

### 📡 API Reference
- [REST API](./api/rest-api.md) - HTTP endpoints
- [WebSocket API](./api/websocket-api.md) - Real-time communication

### 🔧 Features
- [Streaming & Notifications](./features/streaming-and-notifications.md) - Real-time response streaming
- [Session Persistence](./features/session-persistence.md) - Conversation continuity
- [Push Notifications Backend](./features/push-notifications-backend.md) - Server-side push setup

### 💻 Development
- [Development Setup](./development/setup.md) - Environment configuration
- [Testing Guide](./development/testing.md) - Unit and integration testing
- [Building for iOS](./development/build-ios.md) - iOS build process
- [Host App Development](./development/hostapp-testing.md) - Tauri app testing
- [Contributing](./development/contributing.md) - Contribution guidelines

### 🚀 Operations
- [Deployment Guide](./operations/deployment.md) - Production deployment

### 🔒 Security
- [Tauri Security Update](./security/tauri-security-update.md) - Security considerations

### 🧪 Testing
- [UAT Scenarios](./testing/uat-scenarios.md) - User acceptance testing

## 🎯 Quick Links

### For Users
- [Download Latest Release](https://github.com/your-repo/claude-companion/releases)
- [Report an Issue](https://github.com/your-repo/claude-companion/issues)
- [Feature Requests](https://github.com/your-repo/claude-companion/discussions)

### For Developers
- [API Documentation](./api/rest-api.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [Architecture Overview](./architecture/overview.md)

## 🌟 Key Features

### Mobile Experience
- **Native iOS App**: Built with SwiftUI for optimal performance
- **Real-time Streaming**: See Claude's responses as they arrive
- **Push Notifications**: Stay updated when Claude completes tasks
- **Project Management**: Switch between coding projects seamlessly

### Server Capabilities
- **Claude Code Integration**: Direct integration with Anthropic's CLI
- **WebSocket Support**: Real-time bidirectional communication
- **Service Discovery**: Automatic server detection via Bonjour
- **Security**: TLS encryption and token authentication

### Developer Experience
- **Comprehensive Testing**: Unit, integration, and UAT coverage
- **CI/CD Ready**: Automated testing and deployment scripts
- **Well-Documented APIs**: Clear REST and WebSocket specifications
- **Modular Architecture**: Easy to extend and maintain

## 📋 Prerequisites

Before you begin, ensure you have:
- **iOS Device**: iPhone or iPad running iOS 17.0+
- **Mac**: For development and running the companion server
- **Node.js**: Version 18 or later
- **Claude Code CLI**: Version 1.0.55+
- **Xcode**: Version 15+ (for iOS development)

## 🤝 Getting Help

- **Documentation**: You're here! 📖
- **Issues**: [GitHub Issues](https://github.com/your-repo/claude-companion/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-repo/claude-companion/discussions)
- **Contributing**: See our [Contributing Guide](../CONTRIBUTING.md)

## 📈 Version History

- **v1.0.0** - Initial release with core features
  - iOS app with chat interface
  - Companion server with Claude Code integration
  - Real-time streaming and notifications
  - Session persistence

---

**Last Updated**: 2025-07-30  
**Documentation Version**: 1.0.0