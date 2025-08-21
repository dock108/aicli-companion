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

### Issue #9: Create New Project Folder In-App
**Priority**: High  
**Component**: iOS App - Project Management  
**Beta Blocker**: Possibly (Significant UX friction)  
**Discovered**: 2025-08-19

**Prompt for AI Investigation**:
Implement ability to create new project folders directly from within the iOS app. Currently users must leave the app to create folders in Finder/Terminal before they appear in the project list, creating significant friction for new users. Implement:

1. Add "New Project" or "+" button in project selection view
2. Present sheet/dialog for project name and optional parent directory selection
3. Create server API endpoint to safely create new directories
4. Validate project names (no special chars that break filesystems)
5. Set sensible default location (Desktop? Documents? User-configurable in settings?)
6. Handle permissions and error cases (folder exists, no write permission, etc.)
7. Auto-refresh project list after creation
8. Automatically select and navigate to newly created project
9. Consider template support (create with README, .gitignore, etc.)

Expected behavior: User taps "New Project", enters a name, and the folder is created and immediately available for use without leaving the app. Should work seamlessly on both iOS and macOS.

**Files to investigate/modify**:
- `ios/Sources/AICLICompanion/Views/Projects/ProjectSelectionView.swift` (add creation UI)
- `ios/Sources/AICLICompanion/ViewModels/ProjectListViewModel.swift` (creation logic)
- `server/src/routes/projects.js` (add POST endpoint for folder creation)
- `server/src/services/project-manager.js` (safe folder creation service)
- Similar changes needed in macOS app

**Security considerations**:
- Sanitize folder names to prevent path traversal attacks
- Restrict creation to allowed base directories only
- Validate user has permissions for target location

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

### Issue #14: Message Processing Fails Silently with Large Messages or Special Characters
**Priority**: High  
**Component**: Server - Message Processing / Error Handling  
**Beta Blocker**: Yes (Silent failures are unacceptable UX)  
**Discovered**: 2025-08-21
**Status**: Awaiting error logs

**Prompt for AI Investigation**:
Investigate and fix silent failures when processing certain messages, potentially related to message size or special characters. When certain messages are sent, the server appears to fail processing but no error is returned to the iOS app, leaving users with no feedback about what went wrong. Issues to investigate:

1. Check server message size limits and buffer handling for large messages
2. Investigate special character encoding issues (Unicode, emojis, escape sequences)
3. Review error handling pipeline - ensure ALL errors propagate back to client
4. Add comprehensive error boundaries around message processing
5. Implement proper error responses via APNS when processing fails
6. Add detailed logging for message processing failures
7. Check if Claude CLI has message size limits that aren't being handled
8. Review JSON parsing/stringification for edge cases
9. Ensure WebSocket and HTTP error responses reach the iOS app
10. Add timeout handling with proper error messages

Expected behavior: When message processing fails for any reason, the iOS app should receive a clear error message explaining what went wrong (e.g., "Message too large", "Invalid characters", "Processing timeout"). Never fail silently.

**Files to investigate**:
- `server/src/services/aicli-message-handler.js` (message processing pipeline)
- `server/src/services/push-notification.js` (error response delivery)
- `server/src/middleware/error-handler.js` (global error handling)
- `server/src/services/websocket-message-handlers.js` (WebSocket error paths)
- `server/src/utils/validation.js` (input validation and sanitization)
- `ios/Sources/AICLICompanion/Services/WebSocketService.swift` (client error handling)

**Error scenarios to test**:
- Very large messages (>100KB)
- Messages with special Unicode characters
- Messages with unescaped quotes or backslashes
- Rapid successive messages that might overflow buffers
- Messages sent during server restart/reload
- Network interruptions during message processing

**Required improvements**:
- Add message size validation with clear limits
- Implement proper character encoding/escaping
- Add error telemetry to track failure patterns
- Create error recovery mechanisms
- Add user-facing error messages for all failure modes

**Note**: Error logs to be added when available to help diagnose specific failure patterns.


---

**Document Created**: 2025-08-19  
**Last Updated**: 2025-08-21