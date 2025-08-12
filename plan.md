# Command Controls & Security Implementation Plan

## Executive Summary
Implementing comprehensive command controls and security features to allow users to restrict which commands Claude can execute and prevent destructive operations outside designated project folders. This addresses critical security concerns while maintaining functionality.

## Current State Analysis

### What We Have Now
- Basic permission controls via Claude CLI flags (--allowedTools, --disallowedTools)
- Path security validation for project directories
- Environment variable configuration for some settings
- No UI controls for security configuration
- No audit logging or monitoring
- No path restrictions beyond project validation

### What We're Building
- Comprehensive command filtering and validation system
- Directory-based access controls with safe zones
- UI controls in both iOS and macOS apps for security configuration
- Audit logging and activity monitoring
- Permission request system for dangerous operations
- Emergency stop capabilities
- Security preset templates for easy configuration

## Implementation Plan

### Phase 1: Server-Side Command Control Infrastructure (Day 1) ✅ COMPLETED

#### TODO 1.1: Create Command Security Service ✅
**File**: `server/src/services/command-security.js`
- ✅ Command pattern matching and validation
- ✅ Blocklist/allowlist implementation
- ✅ Path validation against allowed directories
- ✅ Destructive command detection
- ✅ Security violation logging

#### TODO 1.2: Extend Environment Configuration ✅
**File**: `server/.env.example`
- ✅ Added all security environment variables
- ✅ Support for safe directories
- ✅ Command blocking patterns
- ✅ Read-only mode option
- ✅ Security presets

#### TODO 1.3: Update AICLI Process Runner ✅
**File**: `server/src/services/aicli-process-runner.js`
- ✅ Integrated command security checks
- ✅ Working directory validation
- ✅ Tool use validation method
- ✅ Security violation events

#### TODO 1.4: Create Security API Endpoints ✅
**File**: `server/src/routes/security.js`
- ✅ GET `/api/security/settings` - Working
- ✅ PUT `/api/security/settings` - Working
- ✅ GET `/api/security/audit` - Working
- ✅ POST `/api/security/test` - Working
- ✅ GET `/api/security/presets` - Working
- ✅ Permission management endpoints

### Phase 2: iOS App Security Settings (Day 2)

#### TODO 2.1: Create Security Settings View
**File**: `ios/Sources/AICLICompanion/Views/Settings/SecuritySettingsView.swift`
```swift
struct SecuritySettingsView: View {
    @StateObject private var securityManager = SecurityManager.shared
    
    var body: some View {
        Form {
            Section("Command Restrictions") {
                Toggle("Enable Command Filtering", isOn: $securityManager.filterCommands)
                Toggle("Block Destructive Commands", isOn: $securityManager.blockDestructive)
                Toggle("Read-Only Mode", isOn: $securityManager.readOnlyMode)
            }
            
            Section("Allowed Directories") {
                ForEach(securityManager.allowedDirectories) { dir in
                    Text(dir.path)
                }
                Button("Add Directory") { /* ... */ }
            }
            
            Section("Security Presets") {
                Picker("Preset", selection: $securityManager.preset) {
                    Text("Unrestricted").tag(SecurityPreset.unrestricted)
                    Text("Standard").tag(SecurityPreset.standard)
                    Text("Restricted").tag(SecurityPreset.restricted)
                    Text("Custom").tag(SecurityPreset.custom)
                }
            }
        }
    }
}
```

#### TODO 2.2: Extend Settings Manager
**File**: `ios/Sources/AICLICompanion/SettingsManager.swift`
- Security configuration properties
- Secure storage implementation
- Server synchronization methods

#### TODO 2.3: Create Security Models
**File**: `ios/Sources/AICLICompanion/Models/SecuritySettings.swift`
- Security configuration models
- Command restriction rules
- Directory access rules
- Audit log entry model

#### TODO 2.4: Update Settings Navigation
**File**: `ios/Sources/AICLICompanion/SettingsView.swift`
- Add Security section
- Security status indicator
- Quick toggle for read-only mode

### Phase 3: macOS Host App Integration (Day 3)

#### TODO 3.1: Enhance Security Settings View
**File**: `macos-app/AICLICompanionHost/Views/SecuritySettingsView.swift`
- Command Controls section
- Directory restrictions UI
- Command pattern editor
- Real-time validation

#### TODO 3.2: Update Server Manager
**File**: `macos-app/AICLICompanionHost/Models/ServerManager.swift`
- Security configuration in server launch
- Security preset templates
- Security status monitoring

#### TODO 3.3: Create Security Presets
**File**: `macos-app/AICLICompanionHost/Models/SecurityPresets.swift`
```swift
enum SecurityPreset {
    case unrestricted  // Current behavior
    case standard      // Block destructive, limit to project
    case restricted    // Read-only, specific tools
    case custom        // User-defined rules
}
```

### Phase 4: Advanced Security Features (Day 4)

#### TODO 4.1: Implement Command Sandboxing
**File**: `server/src/services/command-sandbox.js`
- Sandbox environment for execution
- File system virtualization
- Rollback capability

#### TODO 4.2: Add Permission Request System
**File**: `server/src/services/permission-manager.js`
- Queue dangerous commands
- Send permission requests to apps
- Timeout and default-deny

#### TODO 4.3: Create Activity Monitor
**File**: `server/src/services/activity-monitor.js`
- Real-time operation tracking
- Security report generation
- Suspicious pattern alerts
- Audit log export

#### TODO 4.4: Implement Emergency Stop
- Global kill switch
- Session termination
- Process cleanup

### Phase 5: Testing & Documentation (Day 5)

#### TODO 5.1: Security Test Suite
**File**: `server/src/test/services/command-security.test.js`
- Command filtering tests
- Path validation tests
- Permission system tests
- Emergency stop tests

#### TODO 5.2: Update Documentation
- Security settings documentation
- Configuration examples
- Best practices guide
- Troubleshooting

#### TODO 5.3: Integration Testing
- iOS app controls
- macOS integration
- Server enforcement
- Audit logging

## Testing Plan

### Unit Tests
- Command pattern matching
- Path validation logic
- Security rule evaluation
- Audit log generation

### Integration Tests
- End-to-end security flow
- iOS/macOS configuration sync
- Permission request handling
- Emergency stop functionality

### Manual Testing Checklist
- [ ] Block `rm -rf /` command
- [ ] Restrict file operations to safe directories
- [ ] iOS app can configure security
- [ ] macOS presets work correctly
- [ ] Audit log captures all events
- [ ] Permission requests reach apps
- [ ] Emergency stop works
- [ ] Settings persist across restarts

## Success Metrics
- Zero unauthorized command executions
- All destructive operations confined to safe directories
- User-friendly security configuration
- Complete audit trail
- No performance degradation
- Clear security status visibility

## AI Assistant Instructions
When continuing this implementation:
1. Always check command-security.js for existing patterns
2. Test security rules with both positive and negative cases
3. Ensure UI changes work on both iPhone and iPad
4. Keep audit logs concise but informative
5. Default to restrictive settings for safety
6. Document all security decisions in code comments

## Security Rule Examples

### Blocked Command Patterns
```javascript
const blockedPatterns = [
  /rm\s+-rf\s+\//,           // rm -rf /
  /format/i,                  // format commands
  /diskutil\s+eraseDisk/,    // disk erase
  /dd\s+if=.*of=\/dev\//,    // dd to devices
  />\/dev\/null\s+2>&1/,      // output suppression (suspicious)
];
```

### Safe Directory Validation
```javascript
const safeDirectories = [
  '/Users/*/projects/**',
  '/Users/*/Documents/**',
  '/tmp/**',
  '/var/tmp/**'
];
```

### Permission Levels
```javascript
const permissionLevels = {
  read: ['Read', 'Grep', 'List'],
  write: ['Write', 'Edit', 'MultiEdit'],
  execute: ['Bash', 'Task'],
  system: ['SystemSettings', 'NetworkConfig']
};
```

**Current Status**: Phase 1 COMPLETED - Server-side security infrastructure fully functional
**Next Step**: Phase 2 - iOS App Security Settings
**Last Updated**: 2025-08-12

## Phase 1 Test Results ✅
- Command blocking: Working (blocks `rm -rf /`, `format`, etc.)
- Directory restrictions: Working (validates against safe directories)
- Security API: All endpoints functional
- Audit logging: Capturing all security validations
- Configuration updates: Working via API
- Security presets: Standard preset applied by default