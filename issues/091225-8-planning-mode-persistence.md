# Issue 121225-5: Planning Mode State Desync Between UI and Backend

**Priority**: High  
**Component**: Server & iOS App - Mode State Management  
**Beta Blocker**: Yes - Prevents core code modification functionality  
**Discovered**: 2025-09-10  
**Status**: Open  
**Related Test Note**: USER_TEST_NOTES.md - Test Note 10

## Problem Description

Claude remains stuck in planning mode even after the UI shows it has returned to normal mode. Users cannot execute code modifications despite the interface indicating normal mode is active, requiring session restarts or workarounds.

## Business Impact

- **Functionality Loss**: Users cannot execute code changes
- **Workflow Disruption**: Forced to restart sessions
- **Trust Issues**: UI shows incorrect state
- **Productivity**: Time wasted figuring out why code won't execute

## Debug & Triage Steps

### 1. Mode State Tracking
```javascript
// Server-side mode tracking
class SessionManager {
    constructor() {
        this.sessions = new Map();
    }
    
    logModeChange(sessionId, newMode, source) {
        const timestamp = new Date().toISOString();
        console.log(`🔄 [MODE] Session ${sessionId}: ${newMode} from ${source} at ${timestamp}`);
        
        const session = this.sessions.get(sessionId);
        if (session) {
            session.modeHistory = session.modeHistory || [];
            session.modeHistory.push({ mode: newMode, timestamp, source });
        }
    }
    
    getModeHistory(sessionId) {
        const session = this.sessions.get(sessionId);
        return session?.modeHistory || [];
    }
}
```

### 2. iOS Mode State Verification
```swift
// iOS-side mode state tracking
class ChatViewModel: ObservableObject {
    @Published var displayMode: ChatMode = .normal
    private var actualMode: ChatMode = .normal
    
    func verifyModeSync() {
        if displayMode != actualMode {
            print("⚠️ [MODE] Desync detected! Display: \(displayMode), Actual: \(actualMode)")
            // Log to analytics
            Analytics.log("mode_desync", parameters: [
                "display": displayMode.rawValue,
                "actual": actualMode.rawValue
            ])
        }
    }
    
    func updateMode(_ newMode: ChatMode, source: String) {
        print("🔄 [MODE] Updating from \(actualMode) to \(newMode) via \(source)")
        actualMode = newMode
        displayMode = newMode
        verifyModeSync()
    }
}
```

### 3. Message Flow Analysis
```bash
# Check mode-related message handling
grep -r "planning.*mode" src/
grep -r "exitPlanMode" src/
grep -r "chatMode" ios/Sources/

# Check for mode state persistence
grep -r "UserDefaults.*mode" ios/Sources/
grep -r "sessionStorage.*mode" src/
```

### 4. WebSocket Message Inspection
```javascript
// Add WebSocket message logging for mode changes
wss.on('message', (ws, message) => {
    const data = JSON.parse(message);
    
    if (data.type === 'mode_change' || data.mode) {
        console.log('🔍 [WS] Mode-related message:', {
            type: data.type,
            mode: data.mode,
            sessionId: data.sessionId,
            timestamp: new Date().toISOString()
        });
    }
});
```

## Root Cause Analysis

### Suspected Causes

1. **Race Condition in Mode Updates**
   ```javascript
   // Problem: Async mode update with sync UI update
   async function exitPlanningMode(sessionId) {
       // UI updates immediately
       sendToClient({ type: 'mode_change', mode: 'normal' });
       
       // But backend update is async and might fail
       await updateBackendMode(sessionId, 'normal');
       // If this fails, UI and backend are desynced
   }
   ```

2. **Missing Mode Propagation**
   - Mode change not propagated to all components
   - Claude CLI session maintains planning mode
   - Server doesn't update its session state

3. **State Persistence Issue**
   - Mode saved in multiple places
   - Conflicting state sources on reload

## Recommended Solution

### Immediate Fix: Mode Synchronization Protocol

```javascript
// Server-side mode manager with verification
class ModeManager {
    async changeMode(sessionId, newMode, requestId) {
        const steps = [];
        
        try {
            // Step 1: Update server state
            steps.push('server');
            this.updateServerMode(sessionId, newMode);
            
            // Step 2: Update Claude CLI state
            steps.push('cli');
            await this.updateCLIMode(sessionId, newMode);
            
            // Step 3: Confirm with client
            steps.push('client');
            await this.confirmClientMode(sessionId, newMode, requestId);
            
            // Step 4: Verify all states match
            steps.push('verify');
            const verified = await this.verifyModeSync(sessionId, newMode);
            
            if (!verified) {
                throw new Error('Mode sync verification failed');
            }
            
            return { success: true, mode: newMode };
            
        } catch (error) {
            console.error('Mode change failed at step:', steps[steps.length - 1]);
            // Rollback to known good state
            await this.rollbackMode(sessionId);
            throw error;
        }
    }
    
    async verifyModeSync(sessionId, expectedMode) {
        const serverMode = this.getServerMode(sessionId);
        const cliMode = await this.getCLIMode(sessionId);
        const clientMode = await this.requestClientMode(sessionId);
        
        const synced = serverMode === expectedMode && 
                      cliMode === expectedMode && 
                      clientMode === expectedMode;
        
        if (!synced) {
            console.error('Mode sync failed:', {
                expected: expectedMode,
                server: serverMode,
                cli: cliMode,
                client: clientMode
            });
        }
        
        return synced;
    }
}
```

### iOS Mode Verification

```swift
class ModeCoordinator: ObservableObject {
    @Published var currentMode: ChatMode = .normal
    private var modeVerificationTimer: Timer?
    
    func requestModeChange(to newMode: ChatMode) {
        // Generate unique request ID
        let requestId = UUID().uuidString
        
        // Send mode change request
        networkManager.sendModeChange(newMode, requestId: requestId) { result in
            switch result {
            case .success(let confirmedMode):
                if confirmedMode == newMode {
                    self.currentMode = newMode
                    self.startModeVerification()
                } else {
                    print("⚠️ Mode change failed, server returned: \(confirmedMode)")
                    self.handleModeConflict(expected: newMode, actual: confirmedMode)
                }
                
            case .failure(let error):
                print("❌ Mode change failed: \(error)")
                self.revertMode()
            }
        }
    }
    
    private func startModeVerification() {
        // Verify mode is still correct after 2 seconds
        modeVerificationTimer?.invalidate()
        modeVerificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.verifyCurrentMode()
        }
    }
    
    private func verifyCurrentMode() {
        networkManager.getCurrentMode { serverMode in
            if serverMode != self.currentMode {
                print("⚠️ Mode desync detected after verification")
                self.handleModeConflict(expected: self.currentMode, actual: serverMode)
            }
        }
    }
}
```

### Mode State Recovery

```javascript
// Add mode recovery endpoint
app.post('/api/session/:sessionId/recover-mode', async (req, res) => {
    const { sessionId } = req.params;
    
    try {
        // Get mode from multiple sources
        const cliMode = await getCLIModeDirectly(sessionId);
        const serverMode = sessionManager.getMode(sessionId);
        const lastKnownGood = await getLastKnownGoodMode(sessionId);
        
        // Determine correct mode
        const correctMode = determinCorrectMode(cliMode, serverMode, lastKnownGood);
        
        // Force sync all components
        await forceModeSync(sessionId, correctMode);
        
        res.json({ 
            recovered: true, 
            mode: correctMode,
            sources: { cliMode, serverMode, lastKnownGood }
        });
        
    } catch (error) {
        res.status(500).json({ error: 'Mode recovery failed' });
    }
});
```

## Testing Plan

1. **Mode Transition Tests**
   - Normal → Planning → Normal
   - Rapid mode switches
   - Mode change during message send
   - Mode change during long operation

2. **Failure Scenarios**
   - Network interruption during mode change
   - Server restart during planning mode
   - Client disconnect/reconnect

3. **Verification Tests**
   - Verify UI matches actual mode
   - Verify commands respect current mode
   - Verify mode persists across app restart

## Acceptance Criteria

- [ ] Mode changes are atomic (all or nothing)
- [ ] UI always reflects actual mode
- [ ] Mode state recoverable after failures
- [ ] Clear error messages when mode change fails
- [ ] Mode verification happens automatically
- [ ] Manual mode recovery option available

## Notes

Consider implementing a "mode status" indicator that shows the sync state between UI and backend, similar to a connection status indicator.

---
**Last Updated**: 2025-09-12