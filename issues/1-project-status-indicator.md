# Issue #1: iOS Project Status Indicator

**Priority**: High  
**Component**: iOS App - Project Status Display + WebSocket Integration  
**Beta Blocker**: Yes (users need to know Claude is working)  
**Discovered**: 2025-08-19  
**Status**: In Progress  

## Problem Description

Project status indicators need to show when Claude is actively processing for a specific project. Users currently have no indication that Claude is working during long operations, leading to confusion about whether the system is stuck or still processing.

## Current Implementation Status

### Server Side (Partially Ready)
- ✅ Activity monitoring exists (`activity-monitor.js` tracks all operations)
- ✅ Health monitor records activity every 30 seconds during processing
- ✅ Session manager tracks `isProcessing` state for each session
- ✅ `ws` package installed (version 8.18.3)
- ❌ WebSocket server currently disabled (removed in index.js line 197)
- ❌ Currently tries to send progress via APNS (not suitable for frequent updates)

### iOS Side (Not Implemented)
- ✅ Project model exists (`ProjectSelectionView.swift`)
- ✅ WebSocket models defined with progress message types
- ❌ No processing state in Project model
- ❌ No WebSocket client implementation
- ❌ No visual indicators in project list

## Implementation Plan

### 1. Re-enable WebSocket Server (Same HTTPS Connection)

**File: `server/src/index.js`**
```javascript
import { WebSocketServer } from 'ws';

// After creating HTTP/HTTPS server (around line 195)
this.server = createServer(this.app);  // or createHttpsServer

// Add WebSocket server on same server instance
this.wss = new WebSocketServer({ 
  server: this.server,
  path: '/ws'
});

// Handle WebSocket connections
this.wss.on('connection', (ws, req) => {
  // Verify auth token from query params or headers
  const token = new URL(req.url, `http://${req.headers.host}`).searchParams.get('token');
  if (this.config.authRequired && token !== this.config.authToken) {
    ws.close(1008, 'Unauthorized');
    return;
  }
  
  ws.on('message', (data) => {
    // Handle incoming messages if needed
  });
  
  // Store connection for broadcasting
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
});

// Heartbeat to detect disconnected clients
setInterval(() => {
  this.wss.clients.forEach((ws) => {
    if (!ws.isAlive) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);
```

### 2. Add Heartbeat Broadcasting

**File: `server/src/services/aicli-process-runner.js`**
```javascript
// In createHealthMonitor method, add WebSocket broadcast
createHealthMonitor(aicliProcess, sessionId) {
  const startTime = Date.now();
  let lastActivityTime = Date.now();
  let lastActivityType = 'Starting';
  
  const statusInterval = setInterval(() => {
    if (aicliProcess && aicliProcess.pid) {
      const elapsedSeconds = Math.round((Date.now() - startTime) / 1000);
      
      // Broadcast heartbeat via WebSocket
      this.broadcastHeartbeat({
        type: 'heartbeat',
        sessionId,
        projectPath: this.sessionManager?.getSession(sessionId)?.workingDirectory,
        activity: lastActivityType,
        elapsedSeconds,
        isProcessing: true,
        timestamp: new Date().toISOString()
      });
    }
  }, 10000); // Every 10 seconds
  
  return {
    recordActivity: (activityType = null) => {
      lastActivityTime = Date.now();
      if (activityType) lastActivityType = activityType;
    },
    cleanup: () => {
      clearInterval(statusInterval);
      // Send final heartbeat
      this.broadcastHeartbeat({
        type: 'heartbeat',
        sessionId,
        isProcessing: false,
        timestamp: new Date().toISOString()
      });
    }
  };
}

// Add broadcast method
broadcastHeartbeat(data) {
  if (global.wss) {
    const message = JSON.stringify(data);
    global.wss.clients.forEach((ws) => {
      if (ws.readyState === 1) { // OPEN
        ws.send(message);
      }
    });
  }
}
```

### 3. Track Tool Usage Activity

**File: `server/src/services/aicli-process-runner.js`**
```javascript
// In handleStreamChunk method, detect tool usage
if (chunk.type === 'tool_use') {
  const toolName = chunk.tool_name || chunk.name || 'tool';
  healthMonitor?.recordActivity(`Using ${toolName}`);
} else if (chunk.type === 'text' && chunk.content) {
  healthMonitor?.recordActivity('Generating response');
} else if (chunk.type === 'thinking') {
  healthMonitor?.recordActivity('Thinking');
}
```

### 4. iOS WebSocket Client

**New File: `ios/Sources/AICLICompanion/Services/WebSocketManager.swift`**
```swift
import Foundation
import Combine

@MainActor
class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared
    @Published var isConnected = false
    
    func connect(to serverURL: String, token: String?) {
        guard let url = URL(string: "\(serverURL.replacingOccurrences(of: "https", with: "wss"))/ws") else { return }
        
        var request = URLRequest(url: url)
        if let token = token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage() // Continue listening
                
            case .failure(let error):
                print("WebSocket error: \(error)")
                self?.isConnected = false
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "heartbeat" else { return }
        
        // Post notification with heartbeat data
        NotificationCenter.default.post(
            name: .claudeHeartbeatReceived,
            object: nil,
            userInfo: json
        )
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }
}

extension Notification.Name {
    static let claudeHeartbeatReceived = Notification.Name("claudeHeartbeatReceived")
}
```

### 5. Extend Project Model for Status

**File: `ios/Sources/AICLICompanion/Models/Project+Status.swift`** (new)
```swift
import Foundation
import SwiftUI

extension Project {
    class StatusInfo: ObservableObject {
        @Published var isProcessing: Bool = false
        @Published var lastActivity: String?
        @Published var processingStartTime: Date?
        @Published var elapsedSeconds: Int = 0
        
        func updateFromHeartbeat(_ data: [String: Any]) {
            isProcessing = data["isProcessing"] as? Bool ?? false
            lastActivity = data["activity"] as? String
            elapsedSeconds = data["elapsedSeconds"] as? Int ?? 0
            
            if isProcessing && processingStartTime == nil {
                processingStartTime = Date()
            } else if !isProcessing {
                processingStartTime = nil
                elapsedSeconds = 0
            }
        }
    }
}

// Project status manager to track all projects
class ProjectStatusManager: ObservableObject {
    @Published var projectStatuses: [String: Project.StatusInfo] = [:]
    
    func statusFor(_ project: Project) -> Project.StatusInfo {
        if let status = projectStatuses[project.path] {
            return status
        }
        let newStatus = Project.StatusInfo()
        projectStatuses[project.path] = newStatus
        return newStatus
    }
    
    func handleHeartbeat(_ notification: Notification) {
        guard let data = notification.userInfo,
              let projectPath = data["projectPath"] as? String,
              let status = projectStatuses[projectPath] else { return }
        
        status.updateFromHeartbeat(data)
    }
}
```

### 6. Update Project List UI

**File: `ios/Sources/AICLICompanion/ProjectSelectionView.swift`**
```swift
// Add to ProjectSelectionView
@StateObject private var statusManager = ProjectStatusManager()
@StateObject private var webSocketManager = WebSocketManager()

// In body, for each project row:
HStack {
    VStack(alignment: .leading) {
        Text(project.name)
            .font(.headline)
        Text(project.path)
            .font(.caption)
            .foregroundColor(.secondary)
        
        // Status indicator
        if statusManager.statusFor(project).isProcessing {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                
                if let activity = statusManager.statusFor(project).lastActivity {
                    Text(activity)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                Text("(\(statusManager.statusFor(project).elapsedSeconds)s)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    Spacer()
    
    if statusManager.statusFor(project).isProcessing {
        Image(systemName: "circle.fill")
            .foregroundColor(.green)
            .scaleEffect(0.8)
            .opacity(0.8)
            .animation(.easeInOut(duration: 1).repeatForever(), value: statusManager.statusFor(project).isProcessing)
    }
}
```

## Message Flow

1. User sends message → Server starts Claude processing
2. Server sets `session.isProcessing = true`
3. Server broadcasts WebSocket heartbeat every 10 seconds:
   ```json
   {
     "type": "heartbeat",
     "sessionId": "abc123",
     "projectPath": "/Users/user/project",
     "activity": "Using Edit tool",
     "elapsedSeconds": 45,
     "isProcessing": true
   }
   ```
4. iOS WebSocket client receives heartbeat
5. iOS updates Project status → UI shows indicator
6. When complete, server sends final heartbeat with `isProcessing: false`
7. iOS clears processing indicator

## Benefits

- ✅ **Single connection point** - WebSocket uses same HTTPS port
- ✅ **Silent updates** - No push notification alerts
- ✅ **Real-time feedback** - Updates every 10 seconds
- ✅ **Minimal server changes** - Leverages existing monitoring
- ✅ **Clear visual feedback** - Users see Claude is working
- ✅ **Project-specific** - Shows which project is being processed

## Testing Requirements

### Manual Testing Steps
1. Connect iOS app to server
2. Verify WebSocket connects on app launch
3. Send a message that triggers long Claude operation
4. Verify project shows processing indicator within 10 seconds
5. Verify activity text updates (e.g., "Using Edit tool")
6. Verify elapsed time increments
7. Verify indicator clears when processing completes
8. Test with multiple projects simultaneously

### Test Scenarios
- [ ] Single project processing indicator
- [ ] Multiple projects with different sessions
- [ ] WebSocket reconnection after disconnect
- [ ] Activity text updates during processing
- [ ] Elapsed time accuracy
- [ ] Indicator clears on completion
- [ ] Indicator clears on error

## Implementation Priority

1. **First**: Server WebSocket setup (required for everything else)
2. **Second**: Heartbeat broadcasting from existing monitors
3. **Third**: iOS WebSocket client
4. **Fourth**: Project status tracking
5. **Fifth**: UI indicators

## Status

**Current Status**: Ready for Implementation  
**Last Updated**: 2025-08-22

## Notes

- WebSocket is preferred over SSE because we already have `ws` package installed
- Using same HTTPS connection eliminates need for separate connection
- 10-second heartbeat interval balances real-time updates with efficiency
- Can extend later to show more detailed progress (e.g., tool names, file paths)