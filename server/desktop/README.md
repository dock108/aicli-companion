# Claude Companion Desktop

A desktop application for managing the Claude Companion server, built with Tauri for a lightweight cross-platform experience.

## Features

- **Server Management**: Start/stop the Claude Companion server with a single click
- **Configuration**: Set custom data directory and server port
- **QR Code Connection**: Generate QR codes for easy mobile app connection
- **Health Monitoring**: Real-time server status and health checks
- **Dark-Slate Terminal Design**: Consistent UI with the mobile app

## Development

### Prerequisites

- Node.js 18+
- Rust (latest stable)
- Platform-specific requirements:
  - **macOS**: Xcode Command Line Tools
  - **Windows**: Microsoft C++ Build Tools
  - **Linux**: `webkit2gtk-4.0` and development packages

### Setup

```bash
# From the server directory
cd desktop
npm install
```

### Running in Development

```bash
# From the server directory
npm run desktop

# Or from the desktop directory
npm run tauri dev
```

### Building

```bash
# From the server directory
npm run desktop:build

# Or from the desktop directory
npm run tauri build
```

## Architecture

The desktop app consists of:

- **Frontend**: HTML/CSS/JavaScript with Vite for development
- **Backend**: Rust with Tauri for native functionality
- **IPC**: Commands for server management, file dialogs, and network detection

### Key Components

- `src/app.js` - Main application logic
- `src/styles.css` - Dark-Slate Terminal design system
- `src-tauri/src/main.rs` - Rust backend with server management
- `index.html` - UI structure

## Usage

1. **Configure Path**: Click "Browse" to select where server data should be stored
2. **Set Port**: Choose the port for the server (default: 3001)
3. **Start Server**: Click "Start Server" to launch the Claude Companion server
4. **Connect Mobile**: Scan the QR code with the Claude Companion mobile app
5. **Stop Server**: Click "Stop Server" when done

## Troubleshooting

### Server won't start
- Ensure Node.js is installed and in PATH
- Check if the port is already in use
- Verify the server files exist in the parent directory

### QR code not displaying
- Check that the server is running
- Ensure your device is on the same network
- Verify firewall settings allow local connections

### Build issues
- Update Rust: `rustup update`
- Clean and rebuild: `cargo clean && npm run tauri build`
- Check platform-specific dependencies are installed