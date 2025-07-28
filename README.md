# AICLI Code Mobile Companion

A iOS companion app for Anthropic's AICLI Code CLI, providing mobile access to AI-assisted coding through chat and terminal interfaces.

## Project Structure

```
aicli-companion/
├── ios/                    # iOS app (SwiftUI + UIKit)
│   ├── AICLICompanion/    # Main app target
│   ├── Models/             # Data models
│   ├── Views/              # SwiftUI views
│   ├── Services/           # Network and business logic
│   └── Utils/              # Helper utilities
├── server/                 # Companion server (Node.js)
│   ├── src/                # Server source code
│   ├── package.json        # Node.js dependencies
│   └── README.md           # Server setup instructions
├── docs/                   # Documentation
└── README.md               # This file
```

## Development Status

- [x] Phase 1: Project Foundation & Research
- [ ] Phase 2: Architecture & Technical Design  
- [ ] Phase 3: Companion Server Development
- [ ] Phase 4: iOS App Core Development
- [ ] Phase 5: User Interface Development

## Requirements

- **iOS Development**: Xcode 15+, iOS 15+ deployment target
- **Server Development**: Node.js 18+, npm
- **AICLI Code**: Anthropic AICLI Code CLI v1.0.55+

## Quick Start

### 1. Clone and Setup
```bash
cd aicli-companion
npm install  # Install server dependencies
```

### 2. iOS Development
```bash
open ios/AICLICompanion.xcodeproj
```

### 3. Run Companion Server
```bash
cd server
npm start
```

## Security & Privacy

- All communication encrypted with TLS
- No data stored on third-party servers
- API keys remain on user's machine
- App Store compliant architecture

## License

MIT License - See LICENSE file for details

---

**Status**: Early Development Phase
**Last Updated**: 2025-07-18
