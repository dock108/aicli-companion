# Issue #2: CloudKit Sync & Cross-Device Coordination

**Priority**: High  
**Component**: iOS CloudKit + Server Device Management  
**Beta Blocker**: No  
**Discovered**: 2025-08-19  
**Status**: Complete  
**Resolved**: 2025-09-04

## Problem Description

Currently, each device operates in isolation, which causes several critical issues:
1. **No Cross-Device Sync**: Messages don't sync between iPhone, iPad, and Mac
2. **Duplicate Messages**: Multiple devices can send the same auto-response
3. **No Session Coordination**: Devices don't know about each other's active sessions
4. **Lost Context**: Starting on one device means starting over on another

We need both CloudKit integration for data sync AND server-side device coordination to prevent chaos when multiple devices are active.

## Why This Matters for Auto-Response

Without proper device coordination:
- Auto-response on multiple devices = duplicate messages sent to Claude
- No way to hand off automation between devices
- Conflicts when devices have different conversation states
- Server can't determine which device should handle responses

## Expected Behavior

**Cross-Device Sync:**
- Messages appear on all devices within 3 seconds
- Session context transfers seamlessly
- Conversation history stays in sync
- Project state synchronized

**Device Coordination:**
- Only ONE device sends auto-responses (primary device)
- Server rejects duplicate messages from multiple devices
- Clean handoff when switching devices
- Conflict resolution for simultaneous edits

**User Experience:**
1. Start conversation on iPhone during commute
2. Continue on iPad at coffee shop
3. Finish on Mac at desk
4. Auto-response follows to active device

## Solution Approach

### Part 1: Server-Side Device Coordination

**1.1 Device Registry Service**
```javascript
// server/src/services/device-registry.js
class DeviceRegistry {
  // Device management
  registerDevice(userId, deviceId, deviceInfo)
  updateLastSeen(deviceId)
  getActiveDevices(userId)
  
  // Primary device election
  electPrimary(userId, sessionId)
  transferPrimary(fromDevice, toDevice)
  
  // Duplicate prevention
  isDuplicate(messageHash, deviceId, timeWindow)
  recordMessage(messageHash, deviceId)
}
```

**1.2 Session Coordination**
```javascript
// server/src/services/session-sync.js
class SessionSyncService {
  // Cross-device session state
  broadcastStateUpdate(sessionId, update, excludeDevice)
  syncMessageBuffer(sessionId, deviceId)
  
  // Locking mechanism
  acquireSessionLock(sessionId, deviceId)
  releaseSessionLock(sessionId, deviceId)
  
  // Conflict resolution
  resolveMessageConflict(message1, message2)
}
```

**1.3 WebSocket Protocol Updates**
```javascript
// New message types
DEVICE_HELLO: 'device:hello'          // Device announces itself
DEVICE_PRIMARY: 'device:primary'       // Primary device election
SESSION_LOCK: 'session:lock'          // Lock for sending
SESSION_SYNC: 'session:sync'          // Sync state
MESSAGE_ACK: 'message:ack'            // Acknowledge receipt
```

### Part 2: iOS CloudKit Integration

**2.1 CloudKit Schema**
```swift
// Record Types
CKRecord.RecordType.Message
CKRecord.RecordType.Session  
CKRecord.RecordType.Project
CKRecord.RecordType.Device
CKRecord.RecordType.SyncState

// Subscriptions for real-time updates
CKQuerySubscription(recordType: .Message)
CKQuerySubscription(recordType: .Session)
```

**2.2 CloudKit Sync Service**
```swift
// ios/Sources/AICLICompanion/Services/CloudKitSyncService.swift
class CloudKitSyncService {
    // Core sync
    func syncMessages(for session: Session)
    func pushLocalChanges()
    func pullRemoteChanges()
    
    // Conflict resolution
    func resolveConflicts(_ conflicts: [CKRecord])
    func mergeRecords(_ local: CKRecord, _ remote: CKRecord)
    
    // Real-time
    func subscribeToChanges()
    func handleRemoteNotification(_ notification: CKNotification)
    
    // Offline support
    func queueForSync(_ operation: SyncOperation)
    func processSyncQueue()
}
```

**2.3 Device Coordinator**
```swift
// ios/Sources/AICLICompanion/Services/DeviceCoordinator.swift
class DeviceCoordinator {
    @Published var isPrimary: Bool = false
    @Published var activeDevices: [Device] = []
    
    func registerWithServer()
    func checkPrimaryStatus()
    func requestPrimary()
    func releasePrimary()
}
```

### Part 3: Integration Points

**3.1 Message Deduplication Flow**
1. iOS generates unique message ID (UUID + timestamp)
2. Sends to server with device ID
3. Server checks duplicate within 5-second window
4. Rejects if duplicate, accepts if unique
5. Broadcasts to other devices if accepted

**3.2 Primary Device Election**
1. First device to open session becomes primary
2. Primary device handles all auto-responses
3. If primary goes offline, next device elected
4. Manual transfer via UI action

**3.3 Sync Triggers**
- On app launch
- On app foreground
- On message send/receive
- On session change
- Every 30 seconds (if active)
- On push notification

## Files to Create/Modify

**New Server Files:**
```
server/src/services/device-registry.js
server/src/services/session-sync.js
server/src/services/duplicate-detector.js
server/src/routes/devices.js
server/test/services/device-registry.test.js
server/test/services/session-sync.test.js
```

**Modified Server Files:**
```
server/src/services/aicli-session-manager.js - Add device tracking
server/src/routes/chat.js - Add deduplication
server/src/index.js - WebSocket device messages
```

**New iOS Files:**
```
ios/Sources/AICLICompanion/Services/CloudKit/CloudKitSyncService.swift
ios/Sources/AICLICompanion/Services/CloudKit/CloudKitModels.swift
ios/Sources/AICLICompanion/Services/CloudKit/ConflictResolver.swift
ios/Sources/AICLICompanion/Services/DeviceCoordinator.swift
ios/Sources/AICLICompanion/Models/SyncModels.swift
```

**Modified iOS Files:**
```
ios/Sources/AICLICompanion/Services/MessagePersistenceService.swift
ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift
ios/Sources/AICLICompanion/Views/Chat/ChatView.swift - Primary indicator
ios/AICLICompanion.xcodeproj - CloudKit capability
Info.plist - CloudKit container ID
```

## Testing Requirements

### Server Testing
- [ ] Device registration and tracking
- [ ] Duplicate message rejection
- [ ] Primary device election
- [ ] Session lock mechanism
- [ ] WebSocket broadcast to devices

### iOS Testing
- [ ] CloudKit container setup
- [ ] Message sync between devices
- [ ] Conflict resolution
- [ ] Offline queue and sync
- [ ] Push notification sync triggers

### Integration Testing
- [ ] 2-device sync scenario
- [ ] 3+ device coordination
- [ ] Primary device handoff
- [ ] Network interruption recovery
- [ ] Duplicate prevention under load

### Manual Testing Checklist
1. **Basic Sync**
   - [ ] Send message on iPhone, verify on iPad
   - [ ] Send message on iPad, verify on iPhone
   - [ ] Sync latency < 3 seconds

2. **Auto-Response Coordination**
   - [ ] Enable auto-response on Device A
   - [ ] Verify Device B doesn't duplicate
   - [ ] Transfer primary to Device B
   - [ ] Verify Device A stops auto-responding

3. **Conflict Resolution**
   - [ ] Edit same message on 2 devices
   - [ ] Verify conflict resolution
   - [ ] Check final state consistency

4. **Edge Cases**
   - [ ] Airplane mode sync queue
   - [ ] App kill during sync
   - [ ] Server restart handling
   - [ ] 10+ devices stress test

## Current Status (2025-09-03)

### ✅ Completed
1. **Session ID Persistence** - Claude session IDs now properly persist between messages
2. **Server Session Management** - Simplified to use Claude's session IDs directly
3. **CloudKit Infrastructure** - Base CloudKit models and sync manager implemented
4. **Device Coordination Base** - DeviceCoordinator and WebSocket extensions created

### 🔧 Issues Fixed
- Server was returning placeholder "new" instead of actual Claude session IDs
- Session ID mapping between server internal IDs and Claude IDs was overly complex
- Removed unnecessary internal session ID generation

### ⚠️ Current Problem
- **Messages save locally but don't sync to CloudKit automatically**
- Each device maintains its own conversation history
- No cross-device message synchronization yet

## Implementation Phases

**Phase 1: Server Device Coordination (Week 1)**
- [x] Design device registry schema
- [x] Implement device-registry.js
- [ ] Add session-sync.js service (partial)
- [x] Update WebSocket handlers
- [x] Add duplicate detection

**Phase 2: CloudKit Setup (Week 2)**
- [x] Enable CloudKit capability
- [x] Design record schemas
- [x] Create CloudKitSyncService
- [ ] Add subscription handlers (needs activation)
- [x] Implement conflict resolution

**Phase 3: Integration (Week 3) - CURRENT**
- [x] Connect iOS to device registry
- [ ] Implement sync triggers (IN PROGRESS)
- [ ] Add primary device UI
- [ ] Test end-to-end sync
- [ ] Performance optimization

## Success Metrics

- **Sync Latency**: < 3 seconds for message appearance
- **Duplicate Prevention**: 100% duplicate rejection rate
- **Conflict Resolution**: < 1% data loss in conflicts
- **Primary Handoff**: < 5 seconds for transfer
- **Reliability**: 99.9% sync success rate

## Dependencies

- Apple Developer account for CloudKit
- CloudKit container provisioning
- Server WebSocket infrastructure (exists)
- iOS message persistence (exists)

## Related Issues

- **Blocks**: #34 (Enhanced Auto-Response) - Needs device coordination
- **Blocks**: #33 (macOS Companion) - Needs sync infrastructure
- **Related**: #3 (Message Queue) - May need queue coordination

## Next Steps (Implementation Plan)

### Immediate Actions Required:
1. **Add CloudKit sync when messages are received** (PushNotificationService.swift)
   - After saving message locally, trigger CloudKit save
   - Include projectPath in CloudKit record

2. **Sync messages on app launch/resume** (ChatViewModel.swift)
   - When loading messages for a project, also fetch from CloudKit
   - Merge CloudKit messages with local, handling duplicates by messageHash

3. **Configure CloudKit subscriptions** (CloudKitSyncManager.swift)
   - Set up CKQuerySubscription for new messages
   - Handle remote notifications to trigger UI updates

4. **Add sync status indicators** (Already has SyncStatusView)
   - Update sync status during upload/download
   - Show sync progress in UI

### Technical Details:
- Messages already have CloudKit conversion methods (Message+CloudKit.swift)
- CloudKitSyncManager has saveMessage() method ready
- DeviceCoordinator tracks device state
- Just need to connect the pieces

## Outstanding Issues (2025-09-03)

### 1. Message Sender Identification
**Problem**: Messages sent from one device (e.g., iPhone) appear as received messages on other devices (e.g., iPad) instead of showing as sent messages from the user.

**Root Cause**: The Message model doesn't properly identify which device sent a user message, so when synced to CloudKit and retrieved on another device, user messages are being displayed as if they came from someone else.

**Solution Required**:
- Add device identifier to user messages when saving to CloudKit
- When fetching from CloudKit, check if message was sent by current user (any device)
- Properly set sender as .user for all user messages regardless of originating device
- May need to track user ID separate from device ID

### 2. Chat Clear Synchronization
**Problem**: When clearing chat on one device, need to:
- Clear the server-side session for that project
- Keep local messages on other devices until they also clear
- Prevent new messages from being sent in a cleared session

**Solution Required**:
- When clearing chat on Device A:
  1. Call server kill session endpoint
  2. Clear local messages on Device A only
  3. Clear CloudKit messages for that project/session
  4. Other devices keep their local copy until manually cleared
- Server should reject messages for killed sessions
- Need to handle session state synchronization

### Implementation Tasks:
1. **Fix Message Sender Identification**:
   - Modify Message+CloudKit to include sender device ID
   - Add logic to identify user messages regardless of source device
   - Update Message.from(ckRecord:) to properly set sender

2. **Implement Proper Chat Clear**:
   - Ensure killSession actually clears server state
   - Don't auto-clear messages on other devices
   - Add session state check before sending messages
   - Handle "session killed" errors gracefully

## Notes

This issue is critical infrastructure that blocks several other features. The combination of CloudKit for data sync and server-side device coordination ensures:
1. Data consistency across devices
2. No duplicate auto-responses
3. Clean device handoff
4. Foundation for future multi-device features

The server remains stateless for individual requests but maintains device registry for coordination.

**Session ID Fix**: The server now properly uses Claude's session IDs directly without internal mapping, ensuring conversation continuity works correctly on individual devices.

---

**Last Updated**: 2025-09-03  
**Assigned To**: [Active Development]  
**Labels**: enhancement, infrastructure, cloudkit, device-coordination