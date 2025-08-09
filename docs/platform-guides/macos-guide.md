# AICLI Companion macOS App

A native macOS menu bar application for managing the AICLI Companion server. Built with SwiftUI for optimal performance and seamless macOS integration.

## Features

- **Menu Bar Integration**: Always accessible from your menu bar
- **One-Click Server Control**: Start/stop the server instantly
- **Real-time Status Monitoring**: See server health, active sessions, and resource usage
- **Auto-Start Options**: Launch at login and automatically start the server
- **Native macOS Experience**: Built with SwiftUI following Apple's design guidelines
- **Settings Management**: Configure server options from a beautiful native interface
- **Activity Monitoring**: View real-time logs and session activity
- **Network Information**: Display connection details and QR codes for easy iOS pairing

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later (for building from source)
- Node.js 18+ (for running the server)

## Installation

### Option 1: Build from Source

1. Clone the repository:
```bash
git clone https://github.com/your-username/claude-companion.git
cd claude-companion/macos-app
```

2. Open in Xcode:
```bash
open ClaudeCompanionHost.xcodeproj
```

3. Build and run:
   - Select your development team in project settings
   - Choose "My Mac" as the target
   - Press ⌘R to build and run

### Option 2: Command Line Build

```bash
cd macos-app
swift build -c release
open .build/release/ClaudeCompanionHost.app
```

### Option 3: Pre-built Release

Download the latest `.dmg` from the [Releases](https://github.com/your-username/claude-companion/releases) page.

## Usage

### First Launch

1. The app will appear in your menu bar with the AICLI Companion icon
2. Click the icon to open the dropdown menu
3. Configure your settings in the Settings tab

### Server Management

- **Start Server**: Click the prominent "Start Server" button
- **Stop Server**: Click "Stop Server" when the server is running
- **View Status**: Server health and connection info displayed in real-time

### Configuration

Access settings through the gear icon in the menu:

#### General Settings
- Server port (default: 3001)
- Auto-start server on app launch
- Launch app at login

#### Server Settings
- Server directory path (where projects are located)
- Custom npm/node paths if needed
- Environment configuration

#### Security Settings
- Enable/disable authentication
- Generate new auth tokens
- Configure TLS settings

#### Advanced Settings
- Detailed logging options
- Performance tuning
- Network interface selection

## Architecture

The app is built with:
- **SwiftUI**: Modern declarative UI framework
- **Combine**: Reactive programming for state management
- **Network.framework**: For network monitoring and discovery
- **UserNotifications**: System notifications
- **LocalAuthentication**: Touch ID/password for secure operations

### Key Components

```
ClaudeCompanionHost/
├── App/
│   ├── AppDelegate.swift       # App lifecycle management
│   └── ClaudeCompanionApp.swift # Main app entry point
├── Models/
│   ├── ServerManager.swift     # Server process management
│   └── SettingsManager.swift   # Settings persistence
├── Views/
│   ├── MenuBarView.swift       # Main menu bar interface
│   ├── SettingsView.swift      # Settings interface
│   └── ActivityMonitorView.swift # Real-time monitoring
└── Utilities/
    ├── NetworkMonitor.swift    # Network status monitoring
    └── KeychainManager.swift   # Secure credential storage
```

## Development

### Building for Development

1. Install dependencies:
```bash
cd macos-app
# No external dependencies - pure Swift!
```

2. Open in Xcode:
```bash
open ClaudeCompanionHost.xcodeproj
```

3. Select scheme and build configuration:
   - Scheme: ClaudeCompanionHost
   - Configuration: Debug/Release

### Code Signing

For distribution, you'll need:
- Apple Developer account
- Valid signing certificate
- Provisioning profile

Configure in Xcode:
1. Select project in navigator
2. Go to "Signing & Capabilities"
3. Enable "Automatically manage signing"
4. Select your team

### Creating a Release Build

```bash
# Command line
swift build -c release

# Or in Xcode
Product → Archive → Distribute App
```

## Troubleshooting

### Common Issues

1. **App doesn't appear in menu bar**
   - Check if LSUIElement is set to true in Info.plist
   - Restart the app
   - Check Activity Monitor for running process

2. **Server won't start**
   - Verify Node.js is installed: `which node`
   - Check server path in settings
   - View logs in Activity Monitor tab

3. **Can't save settings**
   - Check file permissions
   - Reset settings to defaults
   - Check Console.app for errors

4. **Network interface not showing**
   - Grant network access permission
   - Check System Preferences → Security & Privacy

### Debug Mode

Enable debug logging:
1. Open Settings → Advanced
2. Set Log Level to "Debug"
3. View logs in Activity Monitor tab

### Reset to Defaults

If settings become corrupted:
```bash
defaults delete com.claude.companion.host
```

## Contributing

We welcome contributions! See our [Contributing Guide](../CONTRIBUTING.md) for details.

### Development Guidelines

- Follow Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- Use SwiftUI's latest features where appropriate
- Maintain backward compatibility to macOS 14.0
- Write unit tests for new features
- Update documentation for UI changes

## Security

The app implements several security measures:
- Keychain storage for sensitive data
- App sandboxing (when distributed via App Store)
- Secure inter-process communication
- No network requests except to localhost

## License

MIT License - See [LICENSE](../LICENSE) for details.

## Acknowledgments

- Built with SwiftUI and love for the Mac platform
- Icons from SF Symbols
- Inspired by the best macOS menu bar apps