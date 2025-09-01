# Issue #33: Server-Side Session Coordination & State Management

**Priority**: High  
**Component**: Server Infrastructure  
**Beta Blocker**: No  
**Discovered**: 2025-08-31  
**Status**: In Progress  
**Resolved**: [YYYY-MM-DD if resolved]

## Problem Description

The server currently manages AICLI sessions independently without coordination between devices or sessions. This causes several issues:

1. **No Session State Sharing**: Each device has its own session with no awareness of others
2. **Duplicate Processing**: Multiple devices can process the same Claude response
3. **No Message Ordering**: Messages from different devices can arrive out of order
4. **Lost Context**: Session state isn't shared between devices
5. **Resource Waste**: Multiple Claude sessions for the same conversation

We need server-side coordination to manage session state, prevent duplicates, and ensure message ordering across all devices.

## Expected Behavior

**Session Coordination:**
- Single Claude session shared across multiple devices
- Message ordering preserved regardless of source device
- Session state synchronized in real-time
- Automatic session handoff between devices

**State Management:**
- Centralized message buffer management
- Session context preservation
- Activity tracking across devices
- Resource optimization (one Claude process per conversation)

**Message Flow:**
1. Device A sends message → Server queues and processes
2. Server sends to Claude → Gets response
3. Server broadcasts to all devices (A, B, C)
4. All devices show same conversation state

## Solution Approach

### 1. Enhanced Session Manager

**Enhance: `server/src/services/aicli-session-manager.js`**
```javascript
class AICLISessionManager {
  // Existing session management
  
  // NEW: Multi-device coordination
  linkDeviceToSession(sessionId, deviceId)
  unlinkDeviceFromSession(sessionId, deviceId)
  getDevicesForSession(sessionId)
  
  // NEW: Shared session state
  getSharedSessionState(sessionId)
  updateSharedState(sessionId, update)
  broadcastStateChange(sessionId, change)
  
  // NEW: Message coordination
  queueMessage(sessionId, message, deviceId)
  getNextMessage(sessionId)
  acknowledgeMessage(sessionId, messageId, deviceId)
}
```

### 2. Message Sequencing Service

**New: `server/src/services/message-sequencer.js`**
```javascript
class MessageSequencer {
  // Ensure proper message ordering
  assignSequenceNumber(sessionId, message)
  reorderMessages(messages)
  detectOutOfOrder(sessionId, sequenceNum)
  
  // Handle concurrent messages
  lockForProcessing(sessionId)
  releaseProcessingLock(sessionId)
  
  // Message deduplication
  generateMessageHash(message)
  checkDuplicate(sessionId, messageHash)
  recordProcessed(sessionId, messageHash)
}
```

### 3. Session State Synchronizer

**New: `server/src/services/session-state-sync.js`**
```javascript
class SessionStateSync {
  // State management
  captureState(sessionId)
  restoreState(sessionId, deviceId)
  
  // Real-time sync
  subscribeToState(sessionId, deviceId, callback)
  publishStateUpdate(sessionId, update)
  
  // Conflict resolution
  mergeStates(state1, state2)
  resolveConflict(sessionId, conflicts)
  
  // Activity tracking
  updateActivity(sessionId, deviceId, activity)
  getSessionActivity(sessionId)
}
```

### 4. WebSocket Message Coordinator

**New: `server/src/services/websocket-coordinator.js`**
```javascript
class WebSocketCoordinator {
  // Connection management
  registerConnection(ws, deviceId, userId)
  unregisterConnection(ws)
  
  // Targeted messaging
  sendToDevice(deviceId, message)
  sendToUser(userId, message)
  sendToSession(sessionId, message)
  broadcastToAll(message, excludeDevice)
  
  // Connection state
  isDeviceConnected(deviceId)
  getConnectedDevices(userId)
  
  // Heartbeat & health
  startHeartbeat(ws)
  handleDisconnect(ws, reason)
}
```

### 5. Resource Optimization

**New: `server/src/services/resource-optimizer.js`**
```javascript
class ResourceOptimizer {
  // Claude process management
  shouldReuseClaude(sessionId)
  getOrCreateClaude(sessionId)
  shareClaude(sessionIds)
  
  // Memory management
  compressMessageBuffer(sessionId)
  archiveOldMessages(sessionId)
  
  // Performance monitoring
  trackResourceUsage(sessionId)
  optimizeForDeviceCount(deviceCount)
}
```

## Implementation Details

### Message Flow Architecture

```
Device A ─┐
          ├─→ WebSocket ─→ Message Sequencer ─→ Session Manager ─→ Claude
Device B ─┘                                           │
                                                      ↓
Device A ←─┬─ WebSocket ←─ State Sync ←─ Broadcast ←─┘
Device B ←─┘
```

### State Synchronization Protocol

1. **Device Connects**: 
   - Register with WebSocket coordinator
   - Request current session state
   - Subscribe to state updates

2. **Message Sent**:
   - Assign sequence number
   - Check for duplicates
   - Queue for processing
   - Lock session if needed

3. **Response Received**:
   - Update shared state
   - Broadcast to all devices
   - Record in message buffer
   - Release session lock

4. **Device Disconnects**:
   - Preserve session state
   - Notify other devices
   - Clean up resources

### Conflict Resolution Strategy

**Last-Write-Wins with Merging:**
- Timestamp all updates
- Merge non-conflicting changes
- Last timestamp wins for conflicts
- Broadcast resolution to all devices

## Files to Create/Modify

**New Server Files:**
```
server/src/services/message-sequencer.js
server/src/services/session-state-sync.js
server/src/services/websocket-coordinator.js
server/src/services/resource-optimizer.js
server/test/services/message-sequencer.test.js
server/test/services/session-state-sync.test.js
server/test/services/websocket-coordinator.test.js
```

**Modified Server Files:**
```
server/src/services/aicli-session-manager.js - Multi-device support
server/src/services/aicli-message-handler.js - Sequencing integration
server/src/routes/chat.js - State sync endpoints
server/src/index.js - WebSocket coordination
```

## Testing Requirements

### Unit Tests
- [ ] Message sequencing logic
- [ ] Duplicate detection
- [ ] State merging algorithm
- [ ] Resource optimization decisions

### Integration Tests
- [ ] Multi-device message flow
- [ ] Session state synchronization
- [ ] WebSocket broadcast reliability
- [ ] Lock mechanism under load

### Load Testing
- [ ] 10 devices, 1 session
- [ ] 100 devices, 10 sessions
- [ ] Message ordering under load
- [ ] Memory usage optimization

### Manual Testing
1. Connect 3 devices to same session
2. Send messages from each rapidly
3. Verify ordering preserved
4. Disconnect one device
5. Verify others continue
6. Reconnect device
7. Verify state restored

## Implementation Phases

**Phase 1: Core Coordination (Week 1)**
- [ ] Enhance session manager for multi-device
- [ ] Implement message sequencer
- [ ] Add duplicate detection
- [ ] Basic WebSocket coordination

**Phase 2: State Synchronization (Week 2)**
- [ ] Build session state sync service
- [ ] Add real-time state updates
- [ ] Implement conflict resolution
- [ ] Test state consistency

**Phase 3: Optimization (Week 3)**
- [ ] Add resource optimizer
- [ ] Implement Claude process sharing
- [ ] Optimize message buffers
- [ ] Performance tuning

## Success Metrics

- **Message Ordering**: 100% correct sequence
- **Duplicate Prevention**: 0% duplicate processing
- **State Consistency**: < 100ms sync latency
- **Resource Usage**: 50% reduction with shared sessions
- **Reliability**: 99.9% message delivery

## Dependencies

- **Depends On**: #2 (CloudKit & Device Coordination) - Needs device registry
- WebSocket infrastructure (exists)
- AICLI session manager (exists)

## Related Issues

- **Enables**: #34 (Enhanced Auto-Response) - Provides coordination
- **Related**: #2 (CloudKit Sync) - Client-side complement
- **Future**: Cross-platform expansion

## Notes

This server-side coordination is the backbone for multi-device support. It ensures:
1. Perfect message ordering
2. No duplicate processing
3. Shared session state
4. Resource optimization

Combined with Issue #2 (CloudKit), this creates a complete multi-device solution where the server coordinates the session and CloudKit syncs the data.

---

**Last Updated**: 2025-08-31  
**Assigned To**: [Unassigned]  
**Labels**: enhancement, infrastructure, server, session-management