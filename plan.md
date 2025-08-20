# AICLI Companion - Beta Release & TestFlight Distribution Plan

**Goal**: Launch both iOS and macOS apps on TestFlight for beta testing  
**Last Updated**: 2025-08-18  
**Status**: Phase 1 Ready to Begin  
**Target Beta Date**: 3-5 days from start  

---

## 📊 Executive Summary

This plan guides AICLI Companion from current state to TestFlight beta release. Tasks are organized into two parallel tracks:
- **🤖 AI Track**: Code fixes, configuration, and automation (can be done by Claude/AI)
- **👤 Developer Track**: Certificates, App Store setup, and manual tasks (requires human action)

### Quick Status Overview
- ✅ **Phase 0**: Core features implemented
- 🔄 **Phase 1-4**: Beta readiness fixes (AI Track)
- ⏳ **Phase 5-6**: TestFlight preparation (Both tracks)
- ⏳ **Phase 7**: Beta launch and monitoring

---

## 🎯 Current State Analysis

### ✅ What's Working
- iOS app with chat interface and local message storage
- macOS companion app with menu bar and server management
- Node.js server routing messages to Claude Code CLI
- APNS-based response delivery
- Project management and folder creation
- Local-first message persistence

### ⚠️ Critical Issues for Beta
1. **Chat scrolling UX** - Major usability issue
2. **Session timeout handling** - No graceful recovery
3. **APNS delivery failures** - Messages get lost
4. **Network error crashes** - App crashes on connection issues
5. **Memory management** - Potential leaks in long sessions

### 📋 TestFlight Requirements Status
- ❌ Version numbers not configured
- ❌ Info.plist permissions missing
- ❌ Export options plists needed
- ❌ Build scripts not created
- ❌ App Store Connect not configured
- ❌ Certificates and profiles needed

---

## 🤖 AI TRACK - Code & Configuration Tasks

### Phase 1: Critical Bug Fixes (Day 1)
*These are showstoppers that must be fixed before beta*

#### TODO 1.1: Fix Chat Scrolling UX ⚠️ CRITICAL
**Problem**: Chat doesn't auto-scroll properly, position jumps during streaming
**Files to modify**:
```
ios/Sources/AICLICompanion/Views/Chat/ChatView.swift
ios/Sources/AICLICompanion/Views/Chat/Components/MessageList.swift
```
**Tasks**:
- [ ] Implement proper auto-scroll on new messages
- [ ] Maintain scroll position during streaming
- [ ] Fix keyboard scroll adjustment
- [ ] Add scroll-to-bottom button
- [ ] Test with 100+ message conversations

#### TODO 1.2: Session Timeout Handling
**Files to modify**:
```
server/src/services/aicli-session-manager.js
ios/Sources/AICLICompanion/Services/AICLI/SessionManager.swift
```
**Tasks**:
- [ ] Detect session expiry from Claude responses
- [ ] Add session expired error type
- [ ] Implement automatic session recreation
- [ ] Show user-friendly timeout message
- [ ] Add "Start New Session" recovery action

#### TODO 1.3: APNS Delivery Failure Recovery
**Files to modify**:
```
server/src/services/push-notification.js
ios/Sources/AICLICompanion/Services/PushNotificationService.swift
```
**Tasks**:
- [ ] Implement delivery confirmation mechanism
- [ ] Add fallback HTTP polling for active sessions
- [ ] Retry failed APNS with exponential backoff
- [ ] Track delivery success metrics
- [ ] Show "checking for response" indicator

### Phase 2: Stability & Crash Prevention (Day 1-2)

#### TODO 2.1: Network Error Resilience
**Files to modify**:
```
ios/Sources/AICLICompanion/Services/AICLIService.swift
ios/Sources/AICLICompanion/Services/NetworkManager.swift
```
**Tasks**:
- [ ] Wrap all network calls in try-catch
- [ ] Implement NetworkError enum with all cases
- [ ] Add automatic retry with backoff
- [ ] Show offline banner when disconnected
- [ ] Queue messages for sending when reconnected

#### TODO 2.2: Memory Management Audit
**Tools needed**: Xcode Instruments
**Tasks**:
- [ ] Profile with Leaks instrument
- [ ] Fix retain cycles in ViewModels
- [ ] Implement message pagination (load 50 at a time)
- [ ] Clear old messages from memory
- [ ] Add memory warning handlers

#### TODO 2.3: Server Process Monitoring
**Files to create**:
```
server/src/services/health-monitor.js
macos-app/AICLICompanionHost/Services/ProcessMonitor.swift
```
**Tasks**:
- [ ] Implement health check endpoint
- [ ] Add auto-restart on crash
- [ ] Monitor Claude Code CLI process
- [ ] Log crashes with stack traces
- [ ] Implement graceful shutdown

### Phase 3: Essential UX Polish (Day 2)

#### TODO 3.1: Message Status Indicators
**Files to modify**:
```
ios/Sources/AICLICompanion/Views/Chat/Components/MessageBubble.swift
ios/Sources/AICLICompanion/Models/Message.swift
```
**Tasks**:
- [ ] Add sending/sent/delivered/failed states
- [ ] Show typing indicator for Claude
- [ ] Add retry button for failed messages
- [ ] Implement read receipts
- [ ] Show timestamp on tap

#### TODO 3.2: Loading States & Feedback
**Components to add**:
```
ios/Sources/AICLICompanion/Components/LoadingView.swift
ios/Sources/AICLICompanion/Components/SkeletonLoader.swift
```
**Tasks**:
- [ ] Add loading overlays for all async operations
- [ ] Implement skeleton screens
- [ ] Add progress bars for long operations
- [ ] Show operation descriptions
- [ ] Add haptic feedback for actions

### Phase 4: Quality Assurance (Day 2-3)

#### TODO 4.1: Automated Testing
**Commands to run**:
```bash
# Server tests
cd server && npm test

# iOS tests
xcodebuild test -scheme AICLICompanion -destination 'platform=iOS Simulator,name=iPhone 15'

# macOS tests
xcodebuild test -scheme AICLICompanionHost
```
**Tasks**:
- [ ] Fix all failing tests
- [ ] Add tests for critical fixes
- [ ] Achieve 80% coverage on critical paths
- [ ] Set up GitHub Actions CI

#### TODO 4.2: Linting & Code Quality
**Commands**:
```bash
# Server
cd server && npx eslint . --fix

# iOS/macOS
swiftlint autocorrect
```
**Tasks**:
- [ ] Fix all ESLint errors
- [ ] Fix all SwiftLint warnings
- [ ] Remove commented code
- [ ] Update code documentation

### Phase 5: TestFlight Preparation - Configuration (Day 3)

#### TODO 5.1: Version Configuration
**Files to modify**:
```
ios/App/Info.plist
macos-app/AICLICompanionHost/Info.plist
server/package.json
```
**Updates needed**:
```xml
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

#### TODO 5.2: Privacy & Permissions
**Add to iOS Info.plist**:
```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture images for sharing with Claude</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to select images to share with Claude</string>
<key>NSUserNotificationsUsageDescription</key>
<string>Receive notifications when Claude responds</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Connect to local AICLI Companion server</string>
```

#### TODO 5.3: Export Options Plists
**Create ios/ExportOptions-AppStore.plist**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>TEAM_ID_PLACEHOLDER</string>
    <key>uploadBitcode</key>
    <false/>
    <key>compileBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

**Create macos-app/ExportOptions-AppStore.plist**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>TEAM_ID_PLACEHOLDER</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.aicli.companion.macos</key>
        <string>PROFILE_NAME_PLACEHOLDER</string>
    </dict>
</dict>
</plist>
```

#### TODO 5.4: Build Automation Scripts
**Create scripts/build-ios-testflight.sh**:
```bash
#!/bin/bash
set -e

echo "🏗 Building iOS app for TestFlight..."

# Clean
xcodebuild clean -project ios/AICLICompanion.xcodeproj -scheme AICLICompanion

# Archive
xcodebuild archive \
    -project ios/AICLICompanion.xcodeproj \
    -scheme AICLICompanion \
    -configuration Release \
    -archivePath build/AICLICompanion.xcarchive \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    DEVELOPMENT_TEAM="TEAM_ID_PLACEHOLDER"

# Export
xcodebuild -exportArchive \
    -archivePath build/AICLICompanion.xcarchive \
    -exportPath build/ios-export \
    -exportOptionsPlist ios/ExportOptions-AppStore.plist

echo "✅ iOS build complete: build/ios-export/AICLICompanion.ipa"
```

**Create scripts/build-macos-testflight.sh**:
```bash
#!/bin/bash
set -e

echo "🏗 Building macOS app for TestFlight..."

# Ensure server is bundled
./scripts/bundle-server.sh

# Clean
xcodebuild clean -project macos-app/AICLICompanionHost.xcodeproj -scheme AICLICompanionHost

# Archive
xcodebuild archive \
    -project macos-app/AICLICompanionHost.xcodeproj \
    -scheme AICLICompanionHost \
    -configuration Release \
    -archivePath build/AICLICompanionHost.xcarchive \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    DEVELOPMENT_TEAM="TEAM_ID_PLACEHOLDER" \
    OTHER_CODE_SIGN_FLAGS="--deep"

# Export
xcodebuild -exportArchive \
    -archivePath build/AICLICompanionHost.xcarchive \
    -exportPath build/macos-export \
    -exportOptionsPlist macos-app/ExportOptions-AppStore.plist

echo "✅ macOS build complete: build/macos-export/AICLICompanionHost.app"
```

#### TODO 5.5: Pre-flight Validation
**Create scripts/validate-build.sh**:
```bash
#!/bin/bash

echo "🔍 Validating builds..."

# Check iOS
if [ -f "build/ios-export/AICLICompanion.ipa" ]; then
    echo "✅ iOS IPA found"
    unzip -l build/ios-export/AICLICompanion.ipa | grep Info.plist
else
    echo "❌ iOS IPA not found"
    exit 1
fi

# Check macOS
if [ -d "build/macos-export/AICLICompanionHost.app" ]; then
    echo "✅ macOS app found"
    codesign -dv build/macos-export/AICLICompanionHost.app
    # Check server bundle
    if [ -d "build/macos-export/AICLICompanionHost.app/Contents/Resources/server" ]; then
        echo "✅ Server bundle included"
    else
        echo "❌ Server bundle missing!"
        exit 1
    fi
else
    echo "❌ macOS app not found"
    exit 1
fi

echo "✅ Build validation complete"
```

---

## 👤 DEVELOPER TRACK - Manual Setup Tasks

### Phase 6: Apple Developer Portal Setup

#### TODO 6.1: Certificates & Keys
**Portal URL**: https://developer.apple.com/account/resources/certificates/list

- [ ] **iOS Distribution Certificate**
  - Type: Apple Distribution
  - Platform: iOS, tvOS, watchOS
  - Download and install in Keychain
  
- [ ] **macOS Distribution Certificate**  
  - Type: Apple Distribution
  - Platform: macOS
  - Download and install in Keychain

- [ ] **Push Notification Certificate**
  - Type: Apple Push Notification service SSL
  - App ID: com.aicli.companion
  - Download .p12 file for server

- [ ] **App Store Connect API Key**
  - Name: AICLI Companion CI
  - Access: App Manager
  - Download .p8 file
  - Note Key ID and Issuer ID

#### TODO 6.2: App Identifiers
**Create at**: https://developer.apple.com/account/resources/identifiers/list

**iOS App ID**:
- [ ] Bundle ID: `com.YOURCOMPANY.aicli-companion`
- [ ] Description: AICLI Companion iOS
- [ ] Capabilities:
  - ✅ Push Notifications
  - ✅ Associated Domains (optional)
  - ✅ CloudKit (if using)

**macOS App ID**:
- [ ] Bundle ID: `com.YOURCOMPANY.aicli-companion-host`
- [ ] Description: AICLI Companion Host
- [ ] Capabilities:
  - ✅ Push Notifications
  - ✅ Hardened Runtime

#### TODO 6.3: Provisioning Profiles
**Create at**: https://developer.apple.com/account/resources/profiles/list

- [ ] **iOS App Store Profile**
  - Name: AICLI Companion iOS App Store
  - Type: App Store
  - App ID: com.YOURCOMPANY.aicli-companion
  - Certificates: iOS Distribution

- [ ] **macOS App Store Profile**
  - Name: AICLI Companion Host App Store
  - Type: Mac App Store
  - App ID: com.YOURCOMPANY.aicli-companion-host
  - Certificates: macOS Distribution

### Phase 7: App Store Connect Setup

#### TODO 7.1: Create Apps
**URL**: https://appstoreconnect.apple.com

**iOS App**:
- [ ] Platform: iOS
- [ ] Name: AICLI Companion
- [ ] Primary Language: English (U.S.)
- [ ] Bundle ID: com.YOURCOMPANY.aicli-companion
- [ ] SKU: aicli-companion-ios

**macOS App**:
- [ ] Platform: macOS
- [ ] Name: AICLI Companion Host
- [ ] Primary Language: English (U.S.)
- [ ] Bundle ID: com.YOURCOMPANY.aicli-companion-host
- [ ] SKU: aicli-companion-macos

#### TODO 7.2: App Information
**For both apps, provide**:

**Description** (4000 chars max):
```
AICLI Companion brings the power of Claude directly to your iOS device, seamlessly integrated with your development workflow.

Key Features:
• Chat with Claude using the familiar Claude Code CLI
• Manage multiple project contexts
• Local message storage for offline access
• Real-time streaming responses
• Push notifications for long-running tasks
• Secure connection to your Mac server
• Beautiful native iOS/macOS interface

Perfect for developers who want to:
- Get AI assistance on the go
- Review code from anywhere
- Continue conversations across devices
- Maintain project context

The macOS companion app provides:
- Menu bar control
- Server management
- Auto-start options
- Activity monitoring

Note: Requires Claude Code CLI installed on your Mac.
```

**Keywords** (100 chars):
```
ai,assistant,claude,code,development,programming,chat,productivity,developer,tools
```

**Categories**:
- Primary: Developer Tools
- Secondary: Productivity

**Support URL**: https://github.com/YOURCOMPANY/aicli-companion/issues
**Privacy Policy URL**: https://YOURCOMPANY.github.io/aicli-companion/privacy

#### TODO 7.3: TestFlight Information

**Test Details**:
```
Welcome to the AICLI Companion beta!

What to Test:
1. Connect to your Mac server using QR code
2. Send messages to Claude
3. Switch between different projects
4. Test offline mode and message persistence
5. Try long conversations (50+ messages)
6. Test push notifications
7. Report any crashes or errors

Known Issues:
- Auto-scroll may be jumpy during streaming
- Session timeouts need manual recovery
- Some network errors may cause crashes

Please report feedback via GitHub issues.
```

**Beta App Review Information**:
- [ ] Demo account: Not required
- [ ] Notes: App requires Claude Code CLI on Mac

#### TODO 7.4: Screenshots
**Required sizes and quantities**:

**iOS** (Upload 5-10 per size):
- [ ] 6.7" Display (1290 × 2796): iPhone 15 Pro Max
- [ ] 6.5" Display (1284 × 2778): iPhone 14 Plus  
- [ ] 5.5" Display (1242 × 2208): iPhone 8 Plus
- [ ] 12.9" Display (2048 × 2732): iPad Pro

**macOS** (Upload 5-10):
- [ ] 16:10 aspect ratio (2880 × 1800)

**Screenshot Checklist**:
1. [ ] Welcome/connection screen
2. [ ] Active chat with Claude
3. [ ] Project selection
4. [ ] Settings screen
5. [ ] macOS menu bar
6. [ ] Server status
7. [ ] Multiple conversations
8. [ ] Code highlighting example

---

## 🚀 Execution Playbook

### Day 1: Critical Fixes
**Morning (AI Track)**:
1. Fix chat scrolling (TODO 1.1)
2. Start session timeout handling (TODO 1.2)

**Afternoon (Developer Track)**:
1. Create Apple Developer certificates (TODO 6.1)
2. Register App IDs (TODO 6.2)

### Day 2: Stability & Polish
**Morning (AI Track)**:
1. Complete APNS recovery (TODO 1.3)
2. Network error resilience (TODO 2.1)
3. Memory audit (TODO 2.2)

**Afternoon (Developer Track)**:
1. Create provisioning profiles (TODO 6.3)
2. Set up App Store Connect (TODO 7.1)

### Day 3: Testing & Preparation
**Morning (AI Track)**:
1. Run all tests (TODO 4.1)
2. Fix linting issues (TODO 4.2)
3. Update versions (TODO 5.1)

**Afternoon (Both Tracks)**:
1. Create build scripts (TODO 5.4)
2. Prepare screenshots (TODO 7.4)
3. Write app descriptions (TODO 7.2)

### Day 4: Build & Submit
**Morning**:
1. Run final builds with scripts
2. Validate builds
3. Upload to App Store Connect

**Afternoon**:
1. Submit for TestFlight review
2. Add internal testers
3. Send beta invitations

---

## ✅ Success Criteria & Quality Gates

### Gate 1: Before Starting TestFlight Prep
- [ ] All Phase 1 critical bugs fixed
- [ ] No crashes in 30-minute usage session
- [ ] All tests passing
- [ ] Zero high-priority linting errors

### Gate 2: Before Building
- [ ] Versions updated consistently
- [ ] All Info.plist permissions added
- [ ] Export options configured
- [ ] Certificates installed

### Gate 3: Before Uploading
- [ ] Builds complete without errors
- [ ] Server bundle included in macOS app
- [ ] Code signing valid
- [ ] Build validation script passes

### Gate 4: TestFlight Ready
- [ ] Both apps uploaded successfully
- [ ] TestFlight processing complete
- [ ] Internal testers added
- [ ] Beta test information provided
- [ ] First internal tester can install

---

## 📊 Progress Tracking

### Phase Completion
- ✅ Phase 0: Feature Development (100%)
- ⏳ Phase 1: Critical Bugs (0%)
- ⏳ Phase 2: Stability (0%)
- ⏳ Phase 3: UX Polish (0%)
- ⏳ Phase 4: Quality Assurance (0%)
- ⏳ Phase 5: TestFlight Prep (0%)
- ⏳ Phase 6: Apple Setup (0%)
- ⏳ Phase 7: App Store Connect (0%)

### Key Metrics
- **Crashes**: Currently unknown → Target: 0
- **Test Coverage**: ~60% → Target: 80%
- **Linting Errors**: Many → Target: 0
- **Build Time**: ~5 min → Target: <3 min
- **TestFlight Review**: Not submitted → Target: Approved

---

## 🔧 Troubleshooting Guide

### Common Issues

**Build Fails with Code Signing**:
```bash
# Check certificates
security find-identity -v -p codesigning

# Clear derived data
rm -rf ~/Library/Developer/Xcode/DerivedData
```

**Server Bundle Missing**:
```bash
# Manually bundle server
cd macos-app/AICLICompanionHost/Resources
cp -r ../../../server .
cd server && npm ci --production
```

**TestFlight Processing Stuck**:
- Wait up to 48 hours for first submission
- Check email for issues
- Verify all capabilities match provisioning profile

**APNS Certificate Issues**:
```bash
# Test APNS certificate
openssl s_client -connect gateway.push.apple.com:2195 \
    -cert push-cert.pem -key push-key.pem
```

---

## 🤝 For AI Assistants

### Working on This Plan
1. **Start with Phase 1** - Critical bugs are blocking
2. **Test after each fix** - Don't introduce regressions
3. **Update task checkboxes** - Mark with ✅ when complete
4. **Note blockers** - Add ⚠️ if stuck
5. **Skip developer tasks** - Focus on AI track only
6. **Validate changes** - Run tests before moving on

### Priority Order
1. 🔴 Crashes and data loss
2. 🟠 Broken core features
3. 🟡 Major UX issues
4. 🟢 Polish and optimization

### Remember
- This is for BETA - not perfection
- Fix only what blocks basic usage
- Document any issues for post-beta
- Keep changes minimal and focused

---

## 📝 Change Log

### 2025-08-18
- Complete refactor of plan structure
- Added comprehensive TestFlight requirements
- Separated AI and Developer tracks
- Added specific commands and scripts
- Included validation gates

### Previous Updates
- ✅ Phase 0: Folder creation from iOS
- Initial beta readiness plan created

---

**Current Status**: Ready to begin Phase 1 - Critical Bug Fixes  
**Next AI Action**: Fix chat scrolling UX (TODO 1.1)  
**Next Developer Action**: Create certificates (TODO 6.1)  
**Estimated Time to Beta**: 4-5 days  
**Blockers**: None currently identified