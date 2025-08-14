# Unified Architecture Plan: Single HTTP + APNS Flow

## Executive Summary

The iOS app currently has a critical architecture issue where multiple connection types (WebSocket, HTTP, APNS) and multiple service instances create a "two different worlds" problem. Users experience different behavior when connecting via QR code vs manual entry. This plan eliminates all confusion by establishing ONE service instance, ONE connection type, and ONE consistent flow.

## Critical Problem

### The "Two Different Worlds" Issue
When users connect via QR code vs manual server entry, they get completely different experiences because:
1. **Multiple AICLIService instances** exist instead of using the singleton pattern
2. **WebSocket code attempts connections** to non-existent `/ws` endpoint (404 errors)
3. **Different code paths** handle QR vs manual connection
4. **Project messages bleed between chats** due to singleton ChatViewModel issues

### Root Causes
- `AppMain.swift` creates new `AICLIService()` instead of using `AICLIService.shared`
- Environment objects throughout the app use new instances
- WebSocket code tries to connect but server has no WebSocket support
- Connection URLs are parsed as `ws://` instead of `http://`

## Proposed Solution: One Service, One Flow

### Architecture Principles
1. **Single Service Instance**: Use `AICLIService.shared` everywhere
2. **Single Connection Type**: HTTP requests + APNS responses only
3. **Single URL Format**: HTTP/HTTPS URLs for all connections
4. **No WebSocket**: Remove all WebSocket code completely

### Message Flow
```
User sends message → HTTP POST to server → Server processes with Claude CLI
                                        ↓
iOS app saves locally ← APNS push ← Server sends response via APNS
```

## Implementation Plan

### Phase 1: Fix Service Singleton Pattern (Critical)

#### 1.1 Update AppMain.swift
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/App/AppMain.swift`
```swift
// Change from:
@StateObject private var aicliService = AICLICompanion.AICLIService()
// To:
@StateObject private var aicliService = AICLICompanion.AICLIService.shared
```

#### 1.2 Update ClaudeCompanionApp.swift
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/ClaudeCompanionApp.swift`
```swift
// Change from:
.environmentObject(AICLIService())
// To:
.environmentObject(AICLIService.shared)
```

#### 1.3 Update ContentView.swift
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/ContentView.swift`
```swift
// Update both preview providers:
.environmentObject(AICLIService.shared)
```

#### 1.4 Update AdaptiveContentView.swift
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/AdaptiveContentView.swift`
```swift
// Update all 4 preview providers:
.environmentObject(AICLIService.shared)
```

#### 1.5 Update PerformanceMonitor.swift
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/Services/PerformanceMonitor.swift`
```swift
// Change from:
private let httpAICLIService = AICLIService()
// To:
private let httpAICLIService = AICLIService.shared
```

#### 1.6 Update ChatView Preview
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/Views/Chat/ChatView.swift`
```swift
// Line 540, change from:
.environmentObject(AICLIService())
// To:
.environmentObject(AICLIService.shared)
```

### Phase 2: Remove WebSocket Code

#### 2.1 Delete WebSocket Files
- Delete: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/WebSocketService.swift`
- Delete: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/ClaudeResponseStreamer.swift`

#### 2.2 Clean ChatViewModel
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/Views/Chat/ViewModels/ChatViewModel.swift`
- Remove all WebSocket connection attempts
- Remove stream chunk handlers
- Remove ClaudeResponseStreamer references
- Ensure loading state clears on APNS delivery

### Phase 3: Fix Connection URL Handling

#### 3.1 Update ConnectionView.swift
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/ios/Sources/AICLICompanion/ConnectionView.swift`
```swift
// Update parseConnectionString to handle HTTP URLs:
private func parseConnectionString(_ string: String) -> ServerConnection? {
    // Change from ws:// to http://
    guard let url = URL(string: string),
          url.scheme == "http" || url.scheme == "https",
          let host = url.host else {
        return nil
    }
    
    let port = url.port ?? (url.scheme == "https" ? 443 : 80)
    let token = url.queryParameters?["token"]
    let isSecure = (url.scheme == "https")
    
    return ServerConnection(
        address: host,
        port: port,
        authToken: token,
        isSecure: isSecure
    )
}

// Update ManualSetupSheet parseManualURL similarly
```

### Phase 4: Server-Side Cleanup

#### 4.1 Remove Misleading WebSocket Log
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/server/src/config/server-startup.js`
```javascript
// Remove line 60:
console.log(`   WebSocket: ${wsProtocol}://${hostname}:${config.port}/ws`);
```

#### 4.2 Fix QR Code Generation
**File**: `/Users/michaelfuscoletti/Desktop/claude-companion/server/src/routes/auth.js`
```javascript
// Update QR code generation to use HTTP URLs:
// Change from: ws:// or wss://
// To: http:// or https://
const protocol = config.enableTLS ? 'https' : 'http';
const qrUrl = `${protocol}://${hostname}:${port}?token=${authToken}`;
```

### Phase 5: Fix Project Message Isolation

The singleton ChatViewModel needs to properly isolate messages per project (already implemented in previous session):
- Messages stored in `projectMessages` dictionary by project path
- Session IDs stored in `projectSessionIds` dictionary
- `currentProject` setter handles switching between projects

## Testing Plan

### 1. Connection Testing
- [ ] QR code scanning connects properly with HTTP URL
- [ ] Manual server entry works with HTTP URL
- [ ] Both methods use same AICLIService.shared instance
- [ ] No WebSocket 404 errors in logs

### 2. Message Flow Testing
- [ ] Send message via HTTP POST
- [ ] Receive response via APNS
- [ ] Loading state clears properly
- [ ] Messages appear in correct project chat

### 3. Project Isolation Testing
- [ ] Messages don't bleed between projects
- [ ] Each project maintains its own message history
- [ ] Session IDs are project-specific
- [ ] Switching projects shows correct messages

### 4. Edge Cases
- [ ] App backgrounding/foregrounding
- [ ] Network interruptions
- [ ] Server restarts
- [ ] Token expiration

## Migration Checklist

### iOS App
- [ ] Fix AICLIService singleton usage (6 files)
- [ ] Delete WebSocket files (2 files)
- [ ] Update connection URL parsing
- [ ] Clean up ChatViewModel
- [ ] Test all connection methods

### Server
- [ ] Remove WebSocket log line
- [ ] Update QR code generation
- [ ] Verify HTTP endpoints work
- [ ] Test APNS delivery

### Documentation
- [ ] Update README with new architecture
- [ ] Document HTTP + APNS flow
- [ ] Remove WebSocket references

## Success Metrics

### Immediate (Day 1)
- Zero WebSocket connection attempts
- Single AICLIService instance throughout app
- Consistent behavior regardless of connection method
- No 404 errors in console

### Short-term (Week 1)
- No duplicate messages in chats
- Messages properly isolated by project
- Loading states always clear correctly
- User confusion eliminated

### Long-term (Month 1)
- Stable, predictable architecture
- Easy to debug and maintain
- Ready for additional features
- Clear upgrade path

## Risk Mitigation

### Identified Risks
1. **Breaking existing connections**
   - Mitigation: Support both URL formats temporarily
   - Fallback: Clear migration instructions

2. **APNS delivery failures**
   - Mitigation: Already have retry logic
   - Fallback: Add manual refresh option

3. **Session state issues**
   - Mitigation: Clear session on errors
   - Fallback: Fresh session creation

## Architecture Benefits

### Why HTTP + APNS is Optimal

1. **Works with ngrok**: Perfect for personal servers and tunneling
2. **Reliable delivery**: APNS ensures messages arrive even when backgrounded
3. **Simple server**: Stateless, easy to maintain and scale
4. **Battery efficient**: No persistent connections
5. **Firewall friendly**: Works through corporate networks
6. **Already implemented**: Server already uses this architecture

### What We're Removing

1. **WebSocket complexity**: No reconnection logic needed
2. **Multiple instances**: No state synchronization issues
3. **URL confusion**: One URL format for everything
4. **404 errors**: No attempts to non-existent endpoints

## Implementation Timeline

### Day 1 (Today)
- **Morning**: Fix AICLIService singleton pattern (30 min)
- **Afternoon**: Remove WebSocket code (30 min)
- **Testing**: Verify connections work (30 min)

### Day 2
- **Morning**: Server-side cleanup (15 min)
- **Afternoon**: Full integration testing (45 min)
- **Documentation**: Update README (30 min)

### Total Effort: ~3 hours

## Conclusion

This plan solves the critical "two different worlds" problem by establishing a single, consistent architecture throughout the application. By using only HTTP + APNS with a proper singleton pattern, we eliminate confusion, reduce complexity, and create a maintainable foundation for future development.

The key insight is that the server already implements the correct architecture - we just need to align the iOS app to match it. This is primarily a cleanup operation that removes broken code rather than adding new functionality.

---

**Document Version**: 3.0.0  
**Created**: 2025-01-14  
**Last Updated**: 2025-01-14  
**Status**: Ready for Implementation  
**Priority**: CRITICAL - Fixes fundamental architecture issues  
**Estimated Time**: 3 hours total