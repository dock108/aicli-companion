# User Test Notes

## Active Issues

### Issue #1: iOS Project Status Indicator Not Working
**Priority**: Low  
**Component**: iOS App - Project Status Display  
**Beta Blocker**: No (Not needed for beta)  
**Discovered**: 2025-08-19
**Status**: Deferred

**Note**: Status indicator functionality is not necessary for beta release. Users can see when messages are being processed through the chat interface itself. This can be revisited post-beta if user feedback indicates it would improve the experience.

### Issue #2: CloudKit Integration for Cross-Device Sync
**Priority**: High  
**Component**: iOS App - CloudKit Integration  
**Beta Blocker**: No  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Implement CloudKit integration to enable cross-device synchronization of chat sessions and messages. The app should sync conversation history, session states, and project contexts across all devices logged into the same iCloud account. Investigate and implement:

1. Enable CloudKit capability in the iOS app target
2. Create CloudKit container and record types for messages, sessions, and project metadata
3. Implement MessagePersistenceService extensions to sync with CloudKit
4. Add conflict resolution for messages edited on multiple devices
5. Handle offline mode with proper sync queue when connection restored
6. Implement subscription notifications for real-time updates across devices
7. Add privacy and security controls for CloudKit data
8. Test sync performance with large message histories

Expected behavior: When a user sends messages on iPhone, they should appear on iPad/Mac instantly. Session context and conversation history should seamlessly transfer between devices. Currently, each device maintains isolated local storage with no cross-device communication.

**Files to investigate/modify**:
- `ios/Sources/AICLICompanion/Services/MessagePersistenceService.swift`
- `ios/Sources/AICLICompanion/Services/CloudKitSyncService.swift` (needs creation)
- `ios/AICLICompanion.xcodeproj` (for CloudKit capability)
- `ios/Sources/AICLICompanion/Models/Message.swift` (for CKRecord compatibility)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (for sync triggers)

**Testing Requirements**:
- Test with multiple devices on same iCloud account
- Verify message sync latency < 3 seconds
- Test conflict resolution when same session edited on two devices
- Verify offline queue and sync on reconnection
- Test with 1000+ message history performance

### Issue #3: Message Queue Management Per Chat Session
**Priority**: High  
**Component**: Server - Message Processing  
**Beta Blocker**: No  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Implement a message queue system that handles multiple messages per chat session. Currently, rapid successive messages may cause race conditions or lost messages. Design and implement:

1. Create a queue management system that maintains message order per session
2. Ensure messages are processed sequentially within each session
3. Allow parallel processing across different sessions
4. Add queue status visibility to track pending messages
5. Implement proper error handling for queue overflow scenarios
6. Add metrics for queue depth and processing time

Expected behavior: Users should be able to send multiple messages quickly without losing any, and each message should be processed in the order sent while maintaining session context.

**Files to investigate**:
- `server/src/services/message-queue.js` (to be created)
- `server/src/services/websocket-message-handlers.js`
- `server/src/services/aicli-session-manager.js`
- `ios/Sources/AICLICompanion/Services/MessageQueueService.swift` (to be created)

### Issue #4: Auto-Response Iteration Mode
**Priority**: Medium  
**Component**: Server/iOS Integration  
**Beta Blocker**: No  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Design an auto-response mode that allows Claude to continue iterating on a task until completion. Implement:

1. A trigger mechanism (keyboard shortcut or UI button) to enable "auto-iterate" mode
2. Claude continues working on the task, sending updates as it progresses
3. Automatic detection when Claude has nothing left to iterate on (completion phrases like "task complete", "finished", etc.)
4. Emergency stop mechanism (hotkey or button) to interrupt auto-iteration
5. Visual indicator showing auto-mode is active
6. Message batching to prevent UI flooding during rapid iterations

Expected behavior: User activates auto-mode, Claude continues working and updating progress until the task is complete or user manually stops it.

**Files to investigate**:
- `server/src/services/aicli-auto-iterate.js` (to be created)
- `ios/Sources/AICLICompanion/ViewModels/AutoIterateViewModel.swift` (to be created)
- `ios/Sources/AICLICompanion/Views/Chat/AutoIterateControls.swift` (to be created)

### Issue #5: AI-Powered Message Summarization for Long Responses
**Priority**: Medium  
**Component**: iOS App - Message Display  
**Beta Blocker**: No  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Implement intelligent message summarization for long Claude responses. Create a system that:

1. Detects when messages exceed a certain length threshold (e.g., 500 words)
2. Automatically generates a concise summary using an LLM endpoint
3. Shows collapsed view with summary by default
4. Allows expansion to see full message
5. Preserves code blocks in full (never summarize code)
6. Highlights key actions taken or decisions made in the summary
7. Optional: Local summarization using on-device ML models for privacy

Expected behavior: Long messages show a brief summary with key points, expandable to full content. Code blocks always shown in full.

**Files to investigate**:
- `ios/Sources/AICLICompanion/Services/MessageSummarizationService.swift` (to be created)
- `ios/Sources/AICLICompanion/Views/Chat/CollapsibleMessageView.swift` (to be created)
- `server/src/services/summarization.js` (to be created if server-side)
- Consider Core ML integration for on-device processing

### Issue #7: Enhanced Claude Environment Details Display
**Priority**: Low  
**Component**: iOS App - Debug/Info Panel  
**Beta Blocker**: No  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Create an enhanced view for Claude environment information and raw output. Implement:

1. Expandable debug panel showing full Claude CLI environment details
2. Raw JSON/stream output viewer for debugging
3. Session metadata display (session ID, creation time, message count)
4. Token usage statistics if available from Claude CLI
5. Response timing and latency metrics
6. Tool usage breakdown (which tools Claude used and how often)
7. Collapsible sections for different types of information
8. Copy-to-clipboard functionality for raw data
9. Optional verbose mode toggle for detailed logging

Expected behavior: Users can access a detailed debug view showing all available Claude session information, raw responses, and performance metrics in an organized, expandable interface.

**Files to investigate**:
- `ios/Sources/AICLICompanion/Views/Debug/EnvironmentDetailsView.swift` (to be created)
- `ios/Sources/AICLICompanion/ViewModels/DebugViewModel.swift` (to be created)
- `server/src/services/aicli-telemetry.js` (enhance existing)
- `server/src/routes/debug.js` (to be created for debug endpoints)

### Issue #8: Initial App Load Freezing with Input Queue Behavior
**Priority**: High  
**Component**: iOS App - Initial Load Performance  
**Beta Blocker**: Potentially (Poor first impression)  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Investigate and fix the iOS app freezing during initial load, followed by rapid processing of queued user input. The app appears to freeze for several seconds on launch, becoming unresponsive to user interaction. Once it unfreezes, it rapidly cycles through any input received during the frozen period. This may be an Xcode development build issue but needs investigation. Check:

1. Analyze app launch sequence in AppDelegate/Scene delegate for blocking operations
2. Profile the initial WebSocket connection establishment for synchronous blocking calls
3. Check if MessagePersistenceService initialization is performing heavy I/O on main thread
4. Review project list loading and any synchronous network calls during startup
5. Investigate if this is specific to debug builds or occurs in release builds too
6. Check for main thread blocking during Core Data/SwiftData initialization
7. Profile with Instruments to identify the exact freeze source
8. Review any synchronous authentication or configuration loading

Expected behavior: App should launch smoothly with responsive UI immediately. Any heavy initialization should happen asynchronously with appropriate loading indicators. User input should either be properly queued or the UI should indicate it's not ready for input.

**Files to investigate**:
- `ios/Sources/AICLICompanion/AICLICompanionApp.swift` (app launch sequence)
- `ios/Sources/AICLICompanion/Services/WebSocketService.swift` (connection init)
- `ios/Sources/AICLICompanion/Services/MessagePersistenceService.swift` (data loading)
- `ios/Sources/AICLICompanion/ViewModels/ProjectListViewModel.swift` (initial project load)
- Check for any `.onAppear` modifiers doing synchronous work
- Profile with Time Profiler instrument to identify bottlenecks

**Testing notes**:
- Test in both Debug and Release configurations
- Test on actual device vs simulator
- Monitor console for any timeout warnings
- Check if issue persists after first launch (cold vs warm start)

### Issue #10: Clickable File Links in Chat
**Priority**: Medium  
**Component**: iOS App - Message Display / Server Integration  
**Beta Blocker**: No  
**Discovered**: 2025-08-21

**Prompt for AI Investigation**:
Implement clickable file names in chat messages that connect to the server and display the formatted file content. When Claude mentions file paths in responses (e.g., "Modified src/server.js:42"), users should be able to tap/click on these file references to view the actual file with proper syntax highlighting. Implement:

1. Detect file path patterns in message content (e.g., `file.ext`, `path/to/file.ext`, `file.ext:lineNumber`)
2. Make detected file paths clickable/tappable with visual indication (underline, color)
3. On tap, request file content from server via new API endpoint
4. Display file in a modal/sheet with syntax highlighting based on file extension
5. Support line number navigation if specified (file.ext:42 jumps to line 42)
6. Handle various file path formats Claude might use
7. Implement file content caching to avoid repeated server requests
8. Add "Copy Path" and "Copy Content" actions in file viewer
9. Handle files that don't exist or user lacks permissions to read

Expected behavior: User sees "Modified src/components/Header.jsx:156" in Claude's response, taps on it, and a formatted view of Header.jsx opens with line 156 highlighted. File content is properly syntax highlighted and readable.

**Files to investigate/modify**:
- `ios/Sources/AICLICompanion/Views/Chat/Components/MessageBubble.swift` (detect and style file links)
- `ios/Sources/AICLICompanion/Views/FileViewer/FileViewerSheet.swift` (create file viewer)
- `ios/Sources/AICLICompanion/Services/FileContentService.swift` (fetch file content)
- `server/src/routes/files.js` (add GET endpoint for file content)
- `ios/Sources/AICLICompanion/Utils/MessageParser.swift` (parse file references)
- Consider using Highlightr or similar for syntax highlighting

**Technical considerations**:
- Security: Validate file paths to prevent directory traversal
- Performance: Cache viewed files for session duration
- UX: Show loading state while fetching file content
- Support common path formats: relative, absolute, with line numbers


### Issue #16: Root Directory Chat Assistant
**Priority**: Low  
**Component**: Server/iOS Integration  
**Beta Blocker**: No - Enhancement for post-beta  
**Discovered**: 2025-08-21

**Note**: This is an enhancement idea for post-beta development. Not required for beta release.

**Concept**:
Add the ability to have a conversation with Claude at the root directory level (parent of all projects) to perform cross-project operations and file management tasks. This would enable users to ask Claude to do things like:
- Move files between projects
- Create new project folders
- Search across all projects
- Organize files and directories
- Perform batch operations across multiple projects
- Get an overview of the entire workspace

**Potential Implementation Ideas**:
1. Add a special "Workspace" or "Root" option in project selection
2. When selected, Claude operates at the parent directory level
3. Could show a different UI indicator when in "workspace mode"
4. Server would need to handle commands at the root level safely
5. Additional security considerations for broader file system access

**Use Cases**:
- "Move all test files from project-a to project-b"
- "Create a new project called 'my-new-app' with a basic folder structure"
- "Find all TODO comments across all my projects"
- "Show me which projects have package.json files"
- "Archive old projects I haven't touched in 30 days"

**Why Not Beta**: 
This is a nice-to-have enhancement that adds complexity. The core chat functionality within individual projects is sufficient for beta. This can be explored based on user feedback about workflow needs.

---

## Critical Testing Requirements

### Authentication Testing Matrix (MUST TEST BEFORE BETA)
**Added**: 2025-08-21  
**Priority**: CRITICAL - Must be thoroughly tested before beta release

#### Test Scenarios to Execute:

**1. Server Configuration Tests**
- [ ] Server with `AUTH_REQUIRED=false` (default)
  - iOS app should connect without any auth
  - All features should work normally
  
- [ ] Server with `AUTH_REQUIRED=true` and valid `AUTH_TOKEN` set
  - iOS app WITHOUT token configured → Should show auth error
  - iOS app WITH correct token → Should connect successfully
  - iOS app WITH incorrect token → Should show auth error
  
- [ ] Server with `AUTH_REQUIRED=true` but NO `AUTH_TOKEN` set
  - Server should fail to start with clear error message

**2. iOS App Configuration Tests**
- [ ] No auth token in settings (default)
  - Should work with non-auth server
  - Should fail gracefully with auth-required server
  
- [ ] Valid auth token in settings
  - Should work with matching auth server
  - Should still work with non-auth server
  
- [ ] Invalid/wrong auth token in settings
  - Should fail with clear error on auth server
  - Should still work with non-auth server (token ignored)
  
- [ ] Malformed auth token (special characters, spaces, etc.)
  - Should handle gracefully without crashing

**3. Connection Flow Tests**
- [ ] Start server with auth, connect iOS without token
  - Should see clear "Authentication Required" message
  - Should NOT crash or hang
  
- [ ] Start server with auth, connect iOS with wrong token
  - Should see "Invalid Token" or similar error
  - Should allow retry with different token
  
- [ ] Switch server from non-auth to auth while app connected
  - Should handle gracefully (disconnect/reconnect flow)
  
- [ ] Switch server from auth to non-auth while app connected
  - Should continue working

**4. WebSocket Specific Tests**
- [ ] Test WebSocket connection with auth token in header
- [ ] Test WebSocket reconnection after auth failure
- [ ] Test WebSocket with expired/rotated tokens
- [ ] Test multiple iOS clients with same token (should work)
- [ ] Test multiple iOS clients with different tokens

**5. Error Message Tests**
- [ ] Verify all auth errors show user-friendly messages
- [ ] No token leakage in error messages
- [ ] Clear instructions on how to add token in settings
- [ ] No infinite retry loops on auth failure

**6. Edge Cases**
- [ ] Server crashes and restarts with different auth config
- [ ] Token with maximum length (test limits)
- [ ] Empty string as token (should be treated as no token)
- [ ] Token rotation while clients connected
- [ ] Network interruption during auth handshake
- [ ] Server behind proxy with auth headers stripped

**7. Security Tests**
- [ ] Token not visible in logs (server or client)
- [ ] Token not stored in plain text on iOS (should use Keychain)
- [ ] Token not sent to non-auth servers
- [ ] Token not included in crash reports or analytics
- [ ] HTTPS/WSS only when auth is enabled (no plain HTTP/WS)

#### Testing Commands:

```bash
# Start server WITHOUT auth (default)
npm start

# Start server WITH auth
AUTH_REQUIRED=true AUTH_TOKEN=test-token-12345 npm start

# Test with wrong token
curl -H "Authorization: Bearer wrong-token" http://localhost:3000/api/health

# Test with correct token
curl -H "Authorization: Bearer test-token-12345" http://localhost:3000/api/health

# Test WebSocket with auth
wscat -c ws://localhost:3000 -H "Authorization: Bearer test-token-12345"
```

#### Expected Behaviors:

✅ **Success Cases:**
- Non-auth server + iOS without token = Works
- Auth server + iOS with matching token = Works
- Clear error messages for all failure cases
- Graceful degradation, no crashes

❌ **Failure Cases to Verify:**
- Auth server + iOS without token = Clear auth required message
- Auth server + iOS with wrong token = Clear invalid token message
- Malformed tokens = Handled gracefully
- Token in wrong format = Clear format error

#### Post-Test Checklist:
- [ ] All auth combinations tested
- [ ] No security vulnerabilities found
- [ ] Error messages are user-friendly
- [ ] No token leakage anywhere
- [ ] Documentation updated with auth setup
- [ ] Settings UI clearly shows auth status

---

## Testing Protocol

### How to Document New Issues
When discovering issues during user testing, add them using this format:

```markdown
### Issue #X: [Brief Title]
**Priority**: [High/Medium/Low]
**Component**: [iOS App/Server/macOS App/Integration]
**Beta Blocker**: [Yes/No]
**Discovered**: [Date]

**Prompt for AI Investigation**:
[Write a clear, action-oriented prompt that an AI can use to investigate and fix the issue. Include:
- Specific problem description
- Steps to reproduce if known
- Expected vs actual behavior
- Relevant files or components to check
- Any error messages or logs]
```

---

**Document Created**: 2025-08-19  
**Last Updated**: 2025-08-21 (Reorganized structure, added Issue #16: Root directory chat concept)