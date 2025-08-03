# iOS Integration Guide for Claude Companion Server

## Overview

This guide documents all iOS-specific features and integration points for the Claude Companion Server. It includes implementation guidelines, API usage examples, and best practices.

## 1. Session Management

### 1.1 Session Deduplication

The server now prevents multiple sessions for the same project. iOS should implement similar logic client-side.

**Implementation Requirements:**
- Store session IDs mapped to working directories
- Check for existing session before creating new one
- Use session continuation endpoint when appropriate

**Example Implementation:**
```swift
class SessionManager {
    private var activeSessions: [String: String] = [:] // workingDirectory -> sessionId
    
    func getOrCreateSession(for workingDirectory: String) async throws -> String {
        // Check for existing session
        if let existingSessionId = activeSessions[workingDirectory] {
            // Verify session is still valid
            let isValid = try await verifySession(existingSessionId)
            if isValid {
                return existingSessionId
            }
        }
        
        // Create new session
        let sessionId = try await createNewSession(workingDirectory: workingDirectory)
        activeSessions[workingDirectory] = sessionId
        return sessionId
    }
}
```

### 1.2 Session Continuation

When the app returns from background, use the continuation endpoint to reconnect to existing sessions.

**API Endpoint:**
```
POST /api/sessions/continue
{
    "sessionId": "existing-session-id",
    "workingDirectory": "/path/to/project"
}
```

**iOS Implementation:**
```swift
func applicationDidBecomeActive() {
    Task {
        for (directory, sessionId) in activeSessions {
            do {
                let response = try await api.continueSession(
                    sessionId: sessionId,
                    workingDirectory: directory
                )
                if response.success {
                    // Mark session as foregrounded
                    websocket.send(SessionForegrounded(sessionId: sessionId))
                }
            } catch {
                // Session might be expired, remove from cache
                activeSessions.removeValue(forKey: directory)
            }
        }
    }
}
```

## 2. Message Validation

### 2.1 Empty Message Filtering

The server filters empty stream chunks. iOS should implement matching validation.

**Validation Logic:**
```swift
struct MessageValidator {
    static func isValidStreamChunk(_ chunk: StreamChunk) -> Bool {
        // Filter empty content chunks
        if chunk.type == "content" && chunk.data.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return false
        }
        
        // Filter incomplete tool use chunks
        if chunk.type == "tool_use" && chunk.data.name?.isEmpty == true {
            return false
        }
        
        return true
    }
    
    static func filterMessages(_ messages: [Message]) -> [Message] {
        return messages.filter { message in
            if case .streamChunk(let chunk) = message {
                return isValidStreamChunk(chunk)
            }
            return true
        }
    }
}
```

### 2.2 Message Enrichment Metadata

Queued messages include additional metadata. Handle these fields appropriately.

**Metadata Fields:**
- `_queued`: Boolean indicating message was queued
- `_queuedAt`: ISO timestamp when message was queued
- `_originalTimestamp`: Original message timestamp

**Example Handling:**
```swift
struct QueuedMessage {
    let message: Message
    let wasQueued: Bool
    let queuedAt: Date?
    let originalTimestamp: Date?
    
    init(from json: [String: Any]) {
        // Parse regular message fields
        self.message = Message(from: json)
        
        // Parse queue metadata
        self.wasQueued = json["_queued"] as? Bool ?? false
        if let queuedAtString = json["_queuedAt"] as? String {
            self.queuedAt = ISO8601DateFormatter().date(from: queuedAtString)
        }
        if let originalString = json["_originalTimestamp"] as? String {
            self.originalTimestamp = ISO8601DateFormatter().date(from: originalString)
        }
    }
}
```

## 3. WebSocket Reconnection

### 3.1 Device ID Header

Always send a persistent device ID for automatic session restoration.

**Implementation:**
```swift
class WebSocketManager {
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    
    func connect(token: String) {
        var request = URLRequest(url: websocketURL)
        request.setValue(deviceId, forHTTPHeaderField: "x-device-id")
        request.url?.append(queryItems: [URLQueryItem(name: "token", value: token)])
        
        websocket = URLSessionWebSocketTask(session: session, request: request)
        websocket.resume()
    }
}
```

### 3.2 Handling Reconnection

The server will automatically restore your sessions on reconnection.

**Welcome Message Handling:**
```swift
func handleWelcomeMessage(_ welcome: WelcomeMessage) {
    // Server capabilities
    self.serverVersion = welcome.serverVersion
    self.capabilities = welcome.capabilities
    
    // Subscribe to events
    websocket.send(SubscribeMessage(events: [
        "assistantMessage",
        "streamData",
        "sessionStatus",
        "error"
    ]))
    
    // Re-register for push notifications if needed
    if let deviceToken = self.deviceToken {
        websocket.send(RegisterDeviceMessage(
            deviceToken: deviceToken,
            deviceInfo: "ios"
        ))
    }
}
```

## 4. Push Notifications

### 4.1 Registration

Register device tokens immediately after connection.

```swift
func registerForPushNotifications(deviceToken: Data) {
    let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
    
    websocket.send(RegisterDeviceMessage(
        deviceToken: tokenString,
        deviceInfo: "ios"
    ))
}
```

### 4.2 Handling Notifications

Process push notification payloads correctly.

```swift
func handlePushNotification(_ userInfo: [AnyHashable: Any]) {
    guard let payload = userInfo["payload"] as? [String: Any],
          let sessionId = payload["sessionId"] as? String,
          let deepLink = payload["deepLink"] as? String else {
        return
    }
    
    // Handle deep link
    if let url = URL(string: deepLink) {
        // Navigate to session
        navigateToSession(sessionId)
    }
    
    // Handle long-running completion
    if payload["isLongRunningCompletion"] as? Bool == true {
        showCompletionAlert(for: sessionId)
    }
}
```

## 5. Background Handling

### 5.1 Session Backgrounding

Notify server when app goes to background.

```swift
func applicationDidEnterBackground() {
    for sessionId in activeSessions.values {
        websocket.send(SessionBackgroundedMessage(sessionId: sessionId))
    }
}
```

### 5.2 Session Foregrounding

Notify server when app returns.

```swift
func applicationWillEnterForeground() {
    for sessionId in activeSessions.values {
        websocket.send(SessionForegroundedMessage(sessionId: sessionId))
    }
}
```

## 6. Error Handling

### 6.1 Session Errors

Handle session-specific errors appropriately.

```swift
func handleError(_ error: ErrorMessage) {
    switch error.code {
    case "INVALID_SESSION":
        // Remove from cache and create new session
        if let sessionId = error.sessionId {
            removeSession(sessionId)
            // Prompt user to restart
        }
        
    case "SESSION_LIMIT":
        // Show alert about too many sessions
        showSessionLimitAlert()
        
    case "PERMISSION_DENIED":
        // Handle permission issues
        requestPermissions()
        
    default:
        // Generic error handling
        showError(error.message)
    }
}
```

## 7. Performance Optimization

### 7.1 Message Batching

Batch UI updates for better performance.

```swift
class MessageBatcher {
    private var pendingMessages: [Message] = []
    private var batchTimer: Timer?
    
    func addMessage(_ message: Message) {
        pendingMessages.append(message)
        
        if batchTimer == nil {
            batchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
                self.flushMessages()
            }
        }
    }
    
    private func flushMessages() {
        let messages = pendingMessages
        pendingMessages.removeAll()
        batchTimer = nil
        
        DispatchQueue.main.async {
            self.updateUI(with: messages)
        }
    }
}
```

### 7.2 Connection State Caching

Cache connection state for faster reconnection.

```swift
class ConnectionStateCache {
    @AppStorage("connectionState") private var cachedState: Data?
    
    func saveState(_ state: ConnectionState) {
        if let encoded = try? JSONEncoder().encode(state) {
            cachedState = encoded
        }
    }
    
    func loadState() -> ConnectionState? {
        guard let data = cachedState else { return nil }
        return try? JSONDecoder().decode(ConnectionState.self, from: data)
    }
}
```

## 8. Testing

### 8.1 Unit Tests

Test message validation and filtering.

```swift
func testMessageValidation() {
    // Test empty chunk filtering
    let emptyChunk = StreamChunk(type: "content", data: ["content": ""])
    XCTAssertFalse(MessageValidator.isValidStreamChunk(emptyChunk))
    
    // Test valid chunk
    let validChunk = StreamChunk(type: "content", data: ["content": "Hello"])
    XCTAssertTrue(MessageValidator.isValidStreamChunk(validChunk))
}
```

### 8.2 Integration Tests

Test session management flow.

```swift
func testSessionDeduplication() async {
    let manager = SessionManager()
    
    // Create first session
    let session1 = try await manager.getOrCreateSession(for: "/test/project")
    
    // Should return same session
    let session2 = try await manager.getOrCreateSession(for: "/test/project")
    
    XCTAssertEqual(session1, session2)
}
```

## 9. Migration Guide

### From Previous Version

1. **Update WebSocket connection to include device ID header**
2. **Implement session continuation on app foreground**
3. **Add message validation before displaying**
4. **Handle queued message metadata**
5. **Update push notification handling for new payload format**

## 10. Checklist

- [ ] Implement session deduplication
- [ ] Add session continuation on foreground
- [ ] Send device ID header on connection
- [ ] Implement message validation matching server
- [ ] Handle queued message metadata
- [ ] Update push notification registration
- [ ] Add session backgrounding/foregrounding messages
- [ ] Implement connection state caching
- [ ] Add proper error handling for new error codes
- [ ] Update tests for new functionality

## TODO: iOS Implementation Items

1. **Session State Persistence**
   - TODO: Implement CoreData or UserDefaults storage for session mappings
   - TODO: Add session expiry tracking
   - TODO: Implement session cleanup on app launch

2. **Message Queue UI**
   - TODO: Show indicator when receiving queued messages
   - TODO: Display queue delivery timestamp if significantly delayed
   - TODO: Handle message ordering with queued messages

3. **Connection Reliability**
   - TODO: Implement exponential backoff for reconnection
   - TODO: Add connection quality indicator
   - TODO: Cache last N messages for comparison after reconnect

4. **Performance Monitoring**
   - TODO: Track message processing time
   - TODO: Monitor WebSocket connection stability
   - TODO: Report metrics to server telemetry endpoint

5. **Push Notification Enhancements**
   - TODO: Implement notification actions (View, Dismiss)
   - TODO: Add notification grouping by project
   - TODO: Handle notification badge counts properly