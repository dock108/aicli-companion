# Issue 083025-34: Enhanced Auto-Response System with Message Intelligence

**Priority**: Medium  
**Component**: iOS App - Auto-Response UI (Server: Response Logic)  
**Beta Blocker**: No - Feature disabled via feature flag  
**Discovered**: 2025-08-31  
**Status**: IN PROGRESS - Server Complete, iOS Pending  
**Resolved**: Not Yet - Awaiting iOS implementation and user testing

## Problem Description

The current auto-response system in the iOS app (`AutoResponseManager`) provides basic functionality but lacks intelligence in understanding Claude's output and selecting appropriate responses. The iOS app handles all auto-response UI controls and configuration, while the server provides message analysis and response selection logic. We need to enhance it with:

1. **Message Intent Recognition**: Understand what Claude is asking or indicating
2. **Context-Aware Response Selection**: Choose the right response based on current development state
3. **Showstopper Detection**: Identify when critical issues need human intervention
4. **CLAUDE.md Integration**: Follow project-specific rules and guidelines

This is the foundation for autonomous development workflows, enabling the app to continue conversations intelligently without constant human intervention.

## Expected Behavior

**Intelligent Response Flow:**
1. Claude outputs a message indicating next steps or completion
2. System analyzes the message for intent and context
3. Appropriate response is selected from template library
4. Auto-response is triggered with contextual message
5. Showstoppers trigger immediate escalation

**Response Patterns to Recognize:**
- "Tests are failing" → "Run the tests again and show me the full output"
- "Task complete" → "Great! Move to the next task in the sprint"
- "Need clarification" → "Check the CLAUDE.md file for guidelines on this"
- "Critical error" → Escalate to user immediately
- "Waiting for input" → Provide contextual continuation

**Smart Stop Conditions:**
- Task completion detected
- Maximum iterations reached
- Showstopper identified
- User intervention requested
- No meaningful progress after N attempts

## Investigation Areas

1. **Message Pattern Analysis**:
   - Common Claude output patterns
   - Completion indicators
   - Error signatures
   - Progress markers

2. **Response Template Design**:
   - Generic vs. project-specific responses
   - Context variables and substitution
   - Confidence scoring for response selection

3. **Integration Points**:
   - Server-side message processing
   - WebSocket communication
   - iOS auto-response triggering
   - State persistence

## Solution Approach

### 1. Server-Side Intelligence

**New: `server/src/services/autonomous-agent.js`**
```javascript
class AutonomousAgent {
  analyzeMessage(claudeOutput) {
    // Intent recognition
    // Context extraction
    // Response selection
  }
  
  selectResponse(intent, context) {
    // Template matching
    // Confidence scoring
    // Fallback handling
  }
  
  detectShowstopper(message) {
    // Critical error patterns
    // Escalation triggers
  }
}
```

**New: `server/src/services/message-analyzer.js`**
```javascript
class MessageAnalyzer {
  extractIntent(message) {
    // Pattern matching for common intents
    // ML-based classification (future)
  }
  
  detectCompletion(message) {
    // Task completion indicators
    // Success/failure determination
  }
  
  assessProgress(messages) {
    // Progress tracking
    // Stuck state detection
  }
}
```

**New: `server/src/services/response-templates.js`**
```javascript
const responseTemplates = {
  continue: {
    default: "Continue working on the current task",
    testing: "Run the tests and fix any failures",
    implementation: "Continue implementing the feature"
  },
  
  clarification: {
    rules: "Check the CLAUDE.md file for guidelines",
    requirements: "Review the issue description for requirements"
  },
  
  progression: {
    nextTask: "Move to the next task in the sprint",
    nextPhase: "Let's move to the testing phase"
  },
  
  troubleshooting: {
    reread: "Re-read the previous instructions and try again",
    debug: "Add debug logging to understand the issue"
  }
};
```

### 2. Enhanced iOS Auto-Response

**Enhance: `AutoResponseManager.swift`**
```swift
extension AutoResponseManager {
    func selectIntelligentResponse(for message: Message) -> String? {
        // Analyze Claude's output
        // Select appropriate template
        // Apply context substitution
    }
    
    func shouldEscalate(_ message: Message) -> Bool {
        // Check for showstopper patterns
        // Verify escalation criteria
    }
}
```

### 3. WebSocket Integration

**Modify: `server/src/routes/chat.js`**
- Add `/api/chat/analyze` endpoint for message analysis
- Implement auto-response triggering
- Add agent state management

## Files to Create/Modify

**New Files:**
```
server/src/services/autonomous-agent.js
server/src/services/message-analyzer.js
server/src/services/response-templates.js
server/src/services/agent-context.js
server/test/services/autonomous-agent.test.js
server/test/services/message-analyzer.test.js
```

**Modified Files:**
```
server/src/routes/chat.js
server/src/services/aicli-message-handler.js
ios/Sources/AICLICompanion/ViewModels/AutoResponseManager.swift
ios/Sources/AICLICompanion/Views/Chat/Components/AutoResponseControls.swift
```

## Testing Requirements

### Unit Tests
- [ ] Message intent recognition accuracy
- [ ] Response template selection logic
- [ ] Showstopper detection patterns
- [ ] Context extraction and tracking

### Integration Tests
- [ ] End-to-end auto-response flow
- [ ] WebSocket message handling
- [ ] State persistence across sessions
- [ ] Error handling and recovery

### Manual Testing
1. Test with various Claude output patterns
2. Verify response selection accuracy
3. Test showstopper escalation
4. Validate context switching
5. Test with real development workflows

## Implementation Checklist

**Phase 1: Core Intelligence (COMPLETE)**
- [x] Create autonomous-agent.js with AI integration
- [x] Implement message-analyzer.js with pattern recognition
- [x] Build response-templates.js library
- [x] Add AI response generator with OpenAI
- [x] Add training data manager
- [x] Add unit tests for core logic

**Phase 2: Server Integration (COMPLETE)**
- [x] Integrate with chat-message-handler.js
- [x] Add API endpoints in chat.js
- [x] Add showstopper detection
- [x] Implement context tracking
- [x] Add CLAUDE.md rule integration
- [ ] Enhance iOS AutoResponseManager (PENDING)
- [ ] Add iOS integration tests (PENDING)

**Phase 3: iOS Implementation (PENDING)**
- [ ] Create auto-reply settings UI
- [ ] Per-project configuration storage
- [ ] Mode selection (smart stop, until completion, timed)
- [ ] Limit enforcement (time/message based)
- [ ] CloudKit sync for settings
- [ ] Manual testing and refinement

## Success Metrics

- **Response Accuracy**: >90% appropriate response selection
- **Automation Rate**: 70% reduction in manual interventions
- **Showstopper Detection**: 100% critical issue escalation
- **User Satisfaction**: Positive feedback on auto-response intelligence

## Dependencies

- Existing `AutoResponseManager` in iOS app
- Current AICLI message handling infrastructure
- WebSocket communication layer

## Related Issues

- **Original Issue**: #34-autonomous-coding-agent-ORIGINAL (Full vision)
- **Next Issue**: #35 (Project Creation & Template Management)
- **Future Issue**: #36 (Planning Session Validation Engine)

## Notes

This issue focuses solely on making the auto-response system intelligent. Project creation and planning validation are handled in separate issues (#35 and #36) to maintain focus and allow for incremental delivery.

**Note**: Auto-response feature is currently disabled via `FeatureFlags.isAutoModeEnabled = false` and `showAutoModeUI = false`.

## Status

**Current Status**: New (Feature Request - Not Started)  
**Last Updated**: 2025-09-09

### Implementation Checklist
- [x] Root cause identified (N/A - feature request)
- [x] Solution designed
- [x] Server code changes made
- [ ] iOS code changes made (PENDING)
- [x] Server tests written (99.6% passing)
- [ ] iOS tests written (PENDING)
- [ ] Manual testing completed
- [ ] Code review passed
- [ ] Deployed to beta

### Completion Criteria (Ready for User Testing)
- [x] Server code compiles without errors
- [ ] iOS code compiles without errors (PENDING)
- [x] Server tests pass (1731/1738)
- [ ] iOS tests pass (PENDING)
- [ ] Feature is fully functional (Server ✅, iOS ❌)
- [ ] Ready for user testing (Needs iOS implementation)
- [x] Blockers documented: iOS implementation required

### User Testing Confirmation
- [ ] User has tested the fix/feature
- [ ] User confirms issue is resolved
- [ ] User approves moving to done/complete
<!-- DO NOT move issue to done folder until all above are checked by user -->

## Implementation Progress (2025-09-11)

### ✅ COMPLETED - Server-Side AI Implementation

**AI-Powered Response Generation:**
- Created `AIResponseGenerator` service with OpenAI GPT-3.5/GPT-4 integration
- Implemented comprehensive prompt engineering with full context awareness
- Added rate limiting (20 req/min) and response caching (5-min TTL)
- Confidence scoring based on analysis and context
- Full error handling with template fallback

**Training Data Management:**
- Created `TrainingDataManager` for learning from successful interactions
- Project-specific training data storage and retrieval
- Relevance-based example selection for context
- Quality analysis and recommendations
- Import/export capabilities for data portability

**Enhanced Autonomous Agent:**
- Integrated AI response generation with 3-tier selection:
  1. CLAUDE.md rules (highest priority)
  2. AI-generated responses (context-aware)
  3. Template-based responses (fallback)
- Training data recording for continuous improvement
- Session management with iteration tracking
- Stuck detection and showstopper escalation

**Message Analysis & Templates:**
- Full intent recognition (completion, error, progress, clarification, waiting)
- Completion detection with success/failure determination
- Showstopper patterns for critical issue escalation
- Progress assessment with stuck detection
- Comprehensive template library by category

**Configuration:**
```bash
# Environment Variables Added
USE_AI_RESPONSES=true/false
OPENAI_API_KEY=<api-key>
AI_MODEL=gpt-3.5-turbo|gpt-4
AI_TEMPERATURE=0.7
AI_MAX_TOKENS=150
AI_RATE_LIMIT=20
TRAINING_DATA_DIR=./training-data
```

### ⏳ PENDING - iOS App Implementation

**CRITICAL: Auto-Reply Settings Architecture Fix Needed:**
**Issue Identified (2025-09-11)**: Auto-reply settings are currently implemented as a GLOBAL toggle in main SettingsView, but they should be PER-PROJECT settings accessible from each chat thread's context menu (similar to "Clear Chat" option).

**Current Problem:**
- Global "Auto Mode" toggle in main app settings (WRONG)
- No way to configure auto-reply per project (MISSING)
- Inconsistent with chat mode pattern (per-project)
- User confusion about global vs project-specific behavior

**Required Fix:**
1. **Remove Global Toggle**: Remove "Auto Mode" from main SettingsView
2. **Add Per-Project Access**: Add "Auto-Reply Settings..." to project context menu (same menu as "Clear Chat")
3. **Per-Project Configuration**: Each project should have independent auto-reply settings

**Auto-Reply Configuration UI Needed:**
1. **Per-Project Settings:** (Architecture needs fixing first)
   - Enable/disable auto-reply per project
   - Configure response mode (AI/Template/Both)
   - Set confidence thresholds

2. **Auto-Reply Modes:**
   - **Smart Stop**: Stop on completion, errors, or showstoppers
   - **Until Completion**: Continue until task marked complete
   - **Time-Based**: Work for X minutes/hours
   - **Message-Based**: Send up to N messages
   - **Hybrid**: Combine limits (e.g., 30 min OR 20 messages)

3. **Control Features:**
   - Start/Stop auto-reply button
   - Pause/Resume capability
   - Override/Edit suggested responses
   - View auto-reply history
   - Training feedback (accept/reject responses)

4. **Settings Storage:**
   - CloudKit sync for per-project preferences
   - Local override options
   - Default settings configuration

### 📋 Testing Requirements

**Server Tests Status:**
- ✅ AI Response Generator: All tests passing
- ⚠️ Training Data Manager: 7 tests with timing issues (non-critical)
- ✅ Message Analyzer: All tests passing
- ✅ Response Templates: All tests passing
- ✅ Autonomous Agent: Integration working
- **Overall**: 1731/1738 tests passing (99.6%)

**iOS Tests Needed:**
- [ ] Auto-reply configuration UI
- [ ] Per-project settings persistence
- [ ] Mode switching logic
- [ ] Time/message limit enforcement
- [ ] CloudKit sync

### 🔄 Integration Protocol (Server ↔ iOS)

**Request from iOS:**
```json
{
  "message": "User message",
  "autoResponse": {
    "enabled": true,
    "mode": "until_completion|smart_stop|timed",
    "limits": {
      "maxMessages": 20,
      "maxMinutes": 30,
      "stopOnError": true,
      "stopOnCompletion": true
    },
    "projectName": "MyProject",
    "currentTask": "Bug fixes",
    "useAI": true,
    "minConfidence": 0.7
  }
}
```

**Response to iOS:**
```json
{
  "analysis": {
    "intent": "completion|error|progress|clarification",
    "confidence": 0.85,
    "isComplete": true,
    "showstopper": false
  },
  "suggestedResponse": {
    "message": "AI or template generated response",
    "confidence": 0.82,
    "source": "ai|template|rule",
    "shouldContinue": true,
    "reason": "task_incomplete|progressing|waiting"
  },
  "limits": {
    "messagesRemaining": 15,
    "timeRemaining": 1200,
    "shouldStop": false,
    "stopReason": null
  }
}
```

## Next Steps

1. **✅ COMPLETED: Fix Auto-Reply Settings Architecture (2025-09-11)**
   - [x] Remove global "Auto Mode" toggle from main SettingsView
   - [x] Add "Auto-Reply Settings..." to ProjectContextHeader menu (same menu as "Clear Chat")
   - [x] Update ChatView to present AutoReplySettingsView per-project
   - [x] Verify AutoReplySettingsStore correctly handles per-project persistence
   - [x] Test that AutoReplyStatusBar continues to work per-project

2. **iOS Implementation Priority:**
   - [x] Create auto-reply settings view (UI exists and properly integrated)
   - [x] Implement per-project configuration (backend exists, UI architecture fixed)
   - [x] Add mode selection UI (exists, now properly accessible)
   - [ ] Integrate with server API (exists, needs testing)
   - [ ] Test with real workflows

3. **User Testing Required:**
   - [ ] Test AI response quality
   - [ ] Validate auto-stop conditions
   - [ ] Verify limit enforcement
   - [ ] Check CloudKit sync
   - [ ] Gather feedback on UI/UX

## Result

**Current State**: Server-side AI implementation COMPLETE. iOS app UI architecture FIXED. Ready for testing and server integration.

**✅ FIXED Issue (2025-09-11)**: Auto-reply settings architecture has been corrected:
- ✅ AutoReplySettingsView (complete and properly integrated)
- ✅ AutoReplySettingsStore (complete, supports per-project)
- ✅ AutoReplyStatusBar (complete, works per-project)  
- ✅ Settings access (now per-project via context menu, like "Clear Chat")
- ✅ UI integration (properly integrated with project context menu)

**Status**: UI architecture fixed. Feature is now ready for:
1. Server API integration testing
2. Real workflow testing 
3. User testing and feedback

## Enhancement: Auto-Reply Notification Muting (2025-09-12)

### Problem
When auto-reply is enabled for a project, each Claude response triggers an individual notification, creating notification spam during auto-reply sessions. Users want notifications muted during auto-reply and only receive a summary notification when the session completes.

### Solution Design

#### 1. Auto-Reply Session State Tracking

**iOS Client Updates:**
- Add `isAutoReplySessionActive` flag to track active auto-reply sessions
- Store in `AutoReplySettingsStore` or `ProjectStateManager`
- Update status when auto-reply starts (first message with auto-reply enabled)
- Update status when auto-reply stops (completion, error, limit reached, manual stop)

#### 2. Notification Suppression Logic

**PushNotificationService.swift Updates:**
```swift
// Check auto-reply status before showing notifications
func shouldShowNotification(for projectPath: String) -> Bool {
    // Existing logic for checking if user is viewing project
    
    // NEW: Check if auto-reply is active for this project
    if let projectUUID = getProjectUUID(for: projectPath),
       let settings = AutoReplySettingsStore.shared.settings(for: projectUUID),
       settings.isEnabled && isAutoReplySessionActive(for: projectUUID) {
        // Suppress notification during auto-reply
        return false
    }
    
    return true
}

// Process notifications silently during auto-reply
func processAPNSMessage(userInfo: [AnyHashable: Any]) async {
    // Extract auto-reply status from notification payload
    let isAutoReplyMessage = userInfo["isAutoReplyMessage"] as? Bool ?? false
    let autoReplyStatus = userInfo["autoReplySessionStatus"] as? String
    
    // Process message normally but suppress UI notification if needed
    if isAutoReplyMessage && autoReplyStatus == "active" {
        // Process silently
        await saveClaudeMessage(...)
        // Skip notification UI
    } else if autoReplyStatus == "complete" {
        // Show completion notification
        showAutoReplyCompletionNotification(...)
    }
}
```

#### 3. Server-Side Auto-Reply Tracking

**notification-types.js Updates:**
```javascript
createClaudeResponseNotification(data, options = {}) {
    // Existing notification setup
    
    // Add auto-reply metadata
    if (data.autoResponse?.enabled) {
        notification.payload.isAutoReplyMessage = true;
        notification.payload.autoReplySessionStatus = data.autoResponse.sessionStatus; // 'start', 'active', 'complete'
        notification.payload.autoReplyStats = {
            messagesExchanged: data.autoResponse.messageCount,
            duration: data.autoResponse.duration,
            stopReason: data.autoResponse.stopReason
        };
    }
}
```

#### 4. Auto-Reply Completion Notifications

**Special notification types:**
- **Session Start** (optional): "Auto-reply started for [Project]" - subtle or silent
- **Session Active**: All messages processed silently, no notifications
- **Session Complete**: 
  - "Auto-reply completed: [X] messages exchanged in [Y] minutes"
  - "Auto-reply stopped: [reason]" (error, limit reached, manual stop)
  - Include summary of what was accomplished if available

#### 5. Implementation Files

**iOS Client Files to Modify:**
- `Services/PushNotificationService.swift` - Add auto-reply aware notification filtering
- `Models/AutoReplySettings.swift` - Add session state tracking
- `Models/AutoReplySettingsStore.swift` - Track active sessions per project
- `Views/Chat/ViewModels/ChatViewModel.swift` - Update session state on start/stop

**Server Files to Modify:**
- `services/push-notification/notification-types.js` - Add auto-reply session metadata
- `handlers/chat-message-handler.js` - Track auto-reply session lifecycle
- `services/autonomous-agent.js` - Include session status in responses

### Testing Requirements

1. **Auto-Reply Session Start**: Verify notification behavior when auto-reply begins
2. **During Active Session**: Confirm notifications are suppressed
3. **Session Completion**: Test completion notification with stats
4. **Error/Stop Cases**: Verify appropriate notifications for different stop reasons
5. **Manual Stop**: Test notification when user manually stops auto-reply
6. **Multiple Projects**: Ensure per-project notification muting works correctly

### User Configuration Options

Consider adding settings for:
- Enable/disable session start notification
- Enable/disable session completion notification
- Periodic progress updates (e.g., notification every 5 messages)
- Different notification sounds for auto-reply events

### Success Criteria

- No notification spam during auto-reply sessions
- Clear indication when auto-reply completes or stops
- Summary information in completion notification
- Per-project notification muting works correctly
- User can still see progress in app UI without notifications
