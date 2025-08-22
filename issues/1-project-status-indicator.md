# Issue #1: iOS Project Status Indicator

**Priority**: Medium (elevated due to heartbeat support)  
**Component**: iOS App - Project Status Display  
**Beta Blocker**: No  
**Discovered**: 2025-08-19  
**Status**: Reopened  

## Problem Description

Project status indicators would show when Claude is actively processing for a specific project. While initially deferred, the implementation of heartbeat functionality (Issues #28 and #29) now makes this feature straightforward to implement and valuable for user experience.

## Updated Approach

With the heartbeat infrastructure from Issues #28 and #29, we can now easily implement project status indicators:

1. **Server sends heartbeats** with session ID during processing (Issue #29)
2. **iOS maps session ID to project** and updates status
3. **Visual indicator** shows processing state per project
4. **Real-time updates** via WebSocket heartbeats

## Investigation Areas

1. Receive heartbeat messages from server (Issue #29)
2. Map session ID to project in iOS app
3. Update project list UI with status indicators
4. Show animation/pulsing for active projects
5. Clear status when processing completes

## Expected Behavior

- Project shows pulsing/animated indicator when Claude is processing
- Indicator updates based on heartbeat messages
- Shows elapsed time if desired
- Clears immediately when processing completes
- Multiple projects can show as active if multiple sessions running

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/ProjectListView.swift` (add status indicator)
- `ios/Sources/AICLICompanion/ViewModels/ProjectListViewModel.swift` (handle heartbeats)
- `ios/Sources/AICLICompanion/Models/Project.swift` (add processing state)
- `ios/Sources/AICLICompanion/Services/WebSocketService.swift` (receive heartbeats)

## Implementation Approach

### 1. Project Model Extension
```swift
extension Project {
    @Published var isProcessing: Bool = false
    @Published var processingElapsedTime: Int = 0
    @Published var lastActivity: String?
}
```

### 2. Heartbeat Handler
```swift
func handleHeartbeat(_ heartbeat: HeartbeatMessage) {
    if let project = findProjectBySessionId(heartbeat.sessionId) {
        project.isProcessing = true
        project.processingElapsedTime = heartbeat.elapsedSeconds
        project.lastActivity = heartbeat.lastActivity
    }
}
```

### 3. UI Update
```swift
// In ProjectListView
if project.isProcessing {
    ProgressView()
        .progressViewStyle(CircularProgressViewStyle())
        .scaleEffect(0.8)
    Text("\(project.processingElapsedTime)s")
        .font(.caption2)
}
```

## Dependencies

- **Requires**: Issue #28 (Activity monitoring) and Issue #29 (Heartbeat delivery)
- **Enables**: Better UX for long-running operations

## Benefits

- Users can see which projects have active Claude sessions
- Clear visibility of processing state across multiple projects
- Reduces need to switch to chat view to check status
- Improves confidence during long operations

## Status

**Current Status**: Reopened - Now feasible with heartbeat support  
**Last Updated**: 2025-08-22

## Result

Previously deferred, but now reopened as the heartbeat infrastructure (Issues #28, #29) makes this straightforward to implement and valuable for UX.