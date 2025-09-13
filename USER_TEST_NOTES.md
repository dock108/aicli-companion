# User Test Notes


## Test Note 4: Settings Popout Needs Overhaul
**Date**: 2025-09-06

### Issue Description
The settings popout is messy and confusing with various references that don't appear to have functional logic behind them.

### Observed Issues
- "Beta" references that may not be connected to actual beta features
- "Debug" options that might not have implementation
- Other references/options without clear purpose or functionality
- Overall organization and layout needs improvement

### Impact
Users are confused by non-functional or unclear settings options, reducing trust in the app and making it difficult to find actual working settings.

### Recommendations for Overhaul
- Audit all settings to verify which ones actually have working logic
- Remove or hide non-functional settings
- Reorganize settings into logical groups
- Add clear descriptions for each setting
- Ensure all displayed settings actually do something
- Consider separating developer/debug settings from user settings
- Improve visual hierarchy and layout

---

## Test Note 7: Chat Thread UI Instability with Long Messages
**Date**: 2025-09-06

### Issue Description
When sending a long message, the chat thread UI becomes unstable with various visual glitches.

### Observed Behavior
- Chat content flashes
- Messages disappear and reappear
- Rapid scrolling up and down
- Overall "wonky" behavior that disrupts the user experience

### Impact
Sending long messages creates a disorienting experience that makes the app feel buggy and unreliable, potentially causing users to lose track of their conversation flow.

### Potential Causes
- Layout recalculation issues with dynamic text sizing
- Animation conflicts during message insertion
- ScrollView performance issues with large content
- Race conditions in UI updates
- Auto-scroll fighting with content size changes
- Text measurement happening multiple times

### Areas to Investigate
- Message rendering lifecycle
- ScrollView behavior with dynamic content
- Animation timing and conflicts
- Text view size calculation for long messages
- Debouncing or throttling UI updates during message send

---

## Test Note 8: App Reload and Lockout After Idle Period
**Date**: 2025-09-06

### Issue Description
After being away from the app for a while, it appears to reload everything causing a significant lockout period.

### Observed Behavior
- App seems to reload/refresh all data after idle period
- Creates a 10-13 second lockout where app is unresponsive
- User cannot interact with the app during this time

### Impact
Returning users face a frustrating delay that makes the app feel slow and unresponsive, disrupting workflow when quickly checking messages or resuming work.

### Potential Causes
- Aggressive memory management causing full reload
- Session re-establishment taking too long
- CloudKit sync operations blocking UI
- Loading all chat history synchronously
- WebSocket reconnection delays
- Token refresh or authentication re-validation

### Areas to Investigate
- App lifecycle management (background/foreground transitions)
- Data loading strategies (lazy vs eager loading)
- Implement progressive loading instead of blocking reload
- Cache management to avoid full reloads
- Background refresh optimization
- Consider showing cached data immediately while refreshing in background

### Related Issue - Connection to Dropped Messages
**Important**: This reload/lockout behavior may be causing dropped messages and lost threads. The UI instability from Test Note 7 (long messages) combined with this reload issue could result in:
- Messages sent during the lockout period being lost
- Thread continuity breaking when the app reloads
- Responses arriving during reload not being properly captured
- Session state confusion leading to orphaned messages

---

## Test Note 9: iOS Keyboard Issue After Sending Message
**Date**: 2025-09-09 (Updated: 2025-09-10)

### Issue Description
On iOS devices (both iPhone and iPad), when the keyboard remains open after hitting send, the UI goes wonky AND the message is sent but still appears in the text entry box.

### Observed Behavior
- Keyboard stays open after tapping send button
- UI becomes unstable/wonky
- Message is successfully sent to the backend
- Message text remains in the input field despite being sent
- Creates confusion about whether message was actually sent

### Impact
Users may accidentally send duplicate messages thinking the first one didn't go through, and the wonky UI creates a poor user experience on iOS devices.

### Potential Causes
- iOS keyboard dismissal behavior
- Text field not clearing properly after send
- Race condition between send action and UI update
- iOS multitasking or keyboard dock mode interfering (iPad)
- Focus management issues in iOS

### Areas to Investigate
- TextField focus and keyboard dismissal on iOS
- Message send completion handler and UI cleanup
- iOS keyboard behaviors and split view scenarios (iPad)
- Ensure text field is cleared immediately after send validation
- Test with external keyboards and keyboard dock modes
- Test on both iPhone and iPad to identify any device-specific behaviors

---

## Test Note 10: Planning Mode Persistence Issue
**Date**: 2025-09-10

### Issue Description
Claude sometimes gets stuck in planning mode even when the interface shows it has returned to normal mode.

### Observed Behavior
- User interface displays "normal" mode status
- Claude continues to operate as if in planning mode
- Cannot modify code files despite UI showing normal mode
- Mode state appears to be out of sync between UI and actual behavior

### Impact
Users cannot get Claude to execute code changes even after planning mode appears to be disabled, requiring workarounds or session restarts to resolve.

### Potential Causes
- State synchronization issue between UI and backend
- Mode transition not completing properly
- Cached mode state not updating
- Race condition during mode switching
- Session state persistence issue

### Areas to Investigate
- Mode state management and synchronization
- Verify mode transitions are atomic and complete
- Check for any caching layers that might hold stale mode state
- Ensure UI mode indicator reflects actual operational mode
- Add logging to track mode transitions and identify where desync occurs

---

## Test Note 11: Chat Scroll Position on Reopen
**Date**: 2025-09-10

### Issue Description
When reopening the app, the chat thread doesn't scroll to the bottom (latest messages) as expected. Instead, it opens near the top of the conversation, typically around the second response.

### Observed Behavior
- Chat opens at an arbitrary position near the top of the thread
- Not at the very top, but around the second message/response
- Users must manually scroll down to see recent messages
- Latest conversation context is not immediately visible

### Impact
Users lose their place in the conversation and must manually navigate to recent messages, creating friction when resuming a conversation and potentially missing new responses.

### Potential Causes
- Scroll position restoration using incorrect anchor point
- ScrollView state being restored to a saved position instead of bottom
- Race condition between content loading and scroll positioning
- Incorrect calculation of content height during initial render
- Default scroll behavior overriding intended position

### Areas to Investigate
- ScrollView initialization and position setting
- Check if scroll position is being persisted and restored incorrectly
- Ensure scroll-to-bottom occurs after all messages are rendered
- Verify content height calculations are complete before positioning
- Consider adding explicit scroll-to-bottom on app resume/reopen

---

## Test Note 13: Cannot Dismiss Keyboard to View Chat
**Date**: 2025-09-10

### Issue Description
Users cannot dismiss the keyboard while in a chat to view more of the conversation. This is particularly problematic given the typically long messages in conversations with Claude.

### Observed Behavior
- Keyboard remains persistent when user wants to read messages
- No obvious way to dismiss keyboard to see more chat content
- Keyboard takes up significant screen space
- Particularly problematic with long Claude responses that need scrolling

### Impact
Users cannot properly read full conversations, especially longer responses from Claude, because the keyboard blocks a significant portion of the screen. This severely impacts readability and user experience.

### Potential Causes
- Missing tap-to-dismiss gesture on chat area
- TextField maintaining focus inappropriately
- Keyboard dismiss button not implemented or not visible
- ScrollView not configured to dismiss keyboard on drag
- Missing keyboard toolbar with dismiss action

### Areas to Investigate
- Implement tap gesture on chat area to dismiss keyboard
- Add keyboard dismiss on scroll/drag gesture
- Consider adding a keyboard toolbar with done/dismiss button
- Ensure proper keyboard avoidance behavior
- Test interaction between keyboard dismissal and message sending
- Review iOS keyboard management best practices for chat interfaces

---

## Feature Suggestion: Automated Plan Execution with Auto-Response Engine
**Date**: 2025-09-10

### Feature Description
Combine planning mode with the auto-response engine to create a workflow where Claude creates a detailed plan that, once approved, executes to completion without user interruptions.

### Proposed Workflow
1. User activates "Plan & Execute" mode
2. Claude enters planning mode to create comprehensive implementation plan
3. Plan is presented to user for review and validation
4. Upon approval, system switches to execution mode with auto-response enabled
5. Claude executes the entire plan autonomously to completion
6. User receives final summary of completed work

### Key Benefits
- **Uninterrupted Execution**: Once approved, plan runs to completion without user intervention
- **Predictable Scope**: User knows exactly what will be done before execution starts
- **Time Efficiency**: User can approve plan and return later to see completed work
- **Quality Assurance**: Plan review acts as safety checkpoint before autonomous execution
- **Clear Documentation**: Plan serves as documentation of what was implemented

### Technical Requirements
- Integration between planning mode and auto-response engine
- Plan approval UI/mechanism in the app
- State management to track plan execution progress
- Ability to pause/abort execution if needed
- Progress indicators showing which plan steps are complete
- Error handling for when plan steps fail

### Use Cases
- Large refactoring tasks
- Multi-file feature implementations
- Systematic bug fixes across codebase
- Test suite creation
- Documentation generation
- Dependency updates and migrations

### Considerations
- Need rollback mechanism if execution fails partway
- Should capture all outputs/changes for user review
- May want approval levels (auto-approve minor changes, require approval for major ones)
- Could store approved plans as templates for future use
- Progress persistence in case of connection issues

---

## Test Note 14: Possible Missing Push Notifications (Under Observation)
**Date**: 2025-09-10

### Issue Description
Suspicion that not all push notifications (APNS) are being received, though the issue is not confirmed. Chats and app functionality appear fine, but there may be notification delivery issues.

### Observed Behavior (Preliminary)
- Chats appear complete in the app
- App functionality seems normal
- Possible missing push notifications
- **May occur when message arrives while actively in another chat**
- May be related to notification coalescing or overlapping
- One notification might be hiding/replacing another
- Needs more observation to confirm pattern

### Impact
Users might miss real-time alerts about new messages, potentially discovering responses only when manually checking the app.

### Potential Causes (Speculative)
- APNS delivery issues or throttling
- Notification coalescing by iOS when multiple arrive close together
- Notification replacement when using same identifier
- **App suppressing notifications when already in foreground/active chat**
- Notification handling logic may skip alerts when user is in different chat
- Silent notification failures
- Background refresh not triggering properly
- Network connectivity issues during notification delivery
- App notification settings or entitlements issues

### Areas to Monitor
- Track correlation between sent messages and received notifications
- **Test specifically when actively using another chat in the app**
- Check if notifications are more likely to be missed in certain scenarios
- Monitor for patterns (time of day, message frequency, app state)
- Verify notification payload and identifiers aren't causing replacements
- Check foreground vs background notification handling
- Test if notifications for inactive chats show when app is in foreground
- Check APNS delivery logs if available
- Test with different notification priorities and types
- Monitor for any iOS notification center anomalies

### Status
**Under Observation** - Not confirmed as an issue yet, needs more data points to establish if there's an actual problem or just perceived missing notifications.

---

## Test Note 12: Claude Consistently Times Out at 5 Minutes with SIGTERM
**Date**: 2025-09-10

### Issue Description
Claude consistently times out and exits with SIGTERM (exit code 143) at exactly the 5-minute mark during command execution through the companion server.

### Observed Behavior
- Claude reliably hits a 5-minute timeout during long-running conversations
- Process exits with code 143 (SIGTERM) after approximately 75-110 tool uses
- Server detects this and sends a continuation message: "I've completed many tasks and need to pause here. Send another message to continue where I left off."
- Session ID is preserved, allowing continuation
- Happens consistently across different types of tasks and conversations

### Impact
While the system handles this gracefully and users can continue their conversation, it interrupts the flow of long-running tasks and may cause confusion when Claude stops mid-task. Users need to manually send another message to continue, which breaks concentration and workflow.

### Technical Details
- Exit code: 143 (SIGTERM)
- Timeout: Exactly 5 minutes from command start
- Tool use count at timeout: ~75-110 operations
- Server correctly treats this as successful completion, not an error
- APNS and WebSocket both receive the continuation message
- ChatView correctly updates from "thinking" to normal state

### Areas to Investigate
- Whether this is a Claude CLI configuration limit or hardcoded behavior
- Possibility of extending the timeout through CLI flags or configuration
- Whether chunking long tasks could avoid hitting the limit
- Impact on complex multi-step operations that take longer than 5 minutes
- User experience improvements to make continuation more seamless

---

## CLI Tools for AI Coding Assistants to Consider Supporting

### Currently Supported
- **Claude Code CLI** (Anthropic)
  - Official CLI from Anthropic
  - Node.js based
  - Full featured with file system access
  - WebSocket/HTTP communication

### Other Notable CLI Tools to Consider

#### 1. **OpenAI Codex CLI**
- **Provider**: OpenAI
- **Type**: Command line coding agent
- **Language**: Node.js (brew/npm installs)
- **Features**:
  - Interactive TUI and non-interactive `exec` mode
  - Reads/writes files and runs commands with approval modes
  - Project-aware context
- **API**: OpenAI API or ChatGPT auth
- **Integration**: API key or login-based

#### 2. **Aider CLI**
- **Provider**: Paul Gauthier (Open Source)
- **Type**: Command line coding assistant
- **Language**: Python
- **Features**:
  - Git-aware editing
  - Multiple file context
  - Works with various LLMs (OpenAI, Anthropic, local)
  - Automatic git commits
- **API**: Python package, supports multiple LLM backends
- **Integration**: Python API or subprocess

#### 3. **GitHub Copilot CLI**
- **Provider**: GitHub/Microsoft
- **Type**: Command line interface for Copilot
- **Language**: Node.js
- **Features**:
  - Git integration
  - Command suggestions
  - Shell script generation
  - Explain commands
- **API**: GitHub/Copilot APIs
- **Integration**: OAuth/GitHub App authentication

#### 4. **Continue.dev Server/API**
- **Provider**: Continue.dev
- **Type**: Open source assistant server/API
- **Language**: Python/TypeScript
- **Features**:
  - Multiple LLM support (OpenAI, Anthropic, local)
  - Extensible via plugins
  - Self-hostable server with REST API
- **API**: REST API (self-hosted)
- **Integration**: API key based

#### 5. **Codeium CLI/API**
- **Provider**: Codeium
- **Type**: AI coding assistant
- **Language**: Go/TypeScript
- **Features**:
  - Code completion and chat
  - Team features
- **API**: REST API with authentication
- **Integration**: API key based

#### 6. **Sourcegraph Cody CLI**
- **Provider**: Sourcegraph
- **Type**: AI coding assistant
- **Language**: Go/TypeScript
- **Features**:
  - Codebase-aware context
  - Multiple LLM support
  - Code search integration
- **API**: GraphQL API
- **Integration**: Sourcegraph instance or cloud

### Integration Considerations

#### Priority Candidates for Integration:
1. **OpenAI Codex CLI** - Official CLI, strong automation support
2. **Aider** - Open source, good documentation, multiple LLM support
3. **Continue.dev** - Open source, extensible, good API
4. **GitHub Copilot CLI** - Large user base, official Microsoft support
5. **Codeium** - Free tier, growing popularity
6. **Sourcegraph Cody CLI** - Codebase-aware with enterprise options

#### Technical Requirements:
- Authentication mechanism (API keys, OAuth, etc.)
- Message format standardization
- Session management approach
- Error handling for different response formats
- Rate limiting considerations
- Pricing/subscription model compatibility

#### Implementation Approach:
1. Create abstraction layer for different CLI tools
2. Standardize message format between app and server
3. Implement provider-specific adapters
4. Handle authentication per provider
5. Unified error handling and status codes

---

## Test Note 15: Need Way to Refresh Project List
**Date**: 2025-09-12

### Issue Description
There is no way to refresh the project list, which may be particularly problematic on iPad.

### Observed Behavior
- Project list doesn't update when new projects are added/removed
- No pull-to-refresh or refresh button available
- May be more noticeable on iPad due to multitasking usage patterns
- Users must close and reopen app to see updated project list

### Impact
Users cannot see newly created projects or remove deleted ones without restarting the app, disrupting workflow especially when managing multiple projects.

### Potential Solutions
- Add pull-to-refresh gesture on project list
- Add refresh button in navigation bar or toolbar
- Implement automatic refresh on app foreground
- Add refresh option in context menu
- Consider periodic background refresh

### iPad-Specific Considerations
- iPad users more likely to keep app open in split view/slide over
- May switch between Claude CLI and companion app frequently
- Project changes made via CLI won't reflect in open iPad app
- Multitasking makes app restarts more disruptive on iPad

---

## Test Note 16: Unsent Message Lost When Navigating Away
**Date**: 2025-09-12

### Issue Description
If you type a message in a chat box and navigate away or to a new chat before sending, the message is lost.

### Observed Behavior
- User types message in chat input field
- User navigates to different chat or leaves chat view
- Original typed message is completely lost
- No draft saving or warning about unsent message
- User must retype entire message if they return

### Impact
Users lose potentially long or complex messages they were composing, causing frustration and requiring them to recreate their thoughts. This is especially problematic for detailed technical questions or multi-part requests.

### Potential Causes
- No draft persistence for chat input
- TextField state not preserved on navigation
- Missing warning dialog for unsent messages
- No per-chat draft storage
- View lifecycle clearing text field state

### Recommended Solutions
1. **Draft Persistence**: Save draft messages per chat
2. **Navigation Warning**: Alert user when leaving with unsent text
3. **Auto-save**: Periodically save draft to local storage
4. **Restore on Return**: Reload draft when returning to chat
5. **Draft Indicator**: Show visual indicator when draft exists

### Areas to Investigate
- Implement per-chat draft storage in local state
- Add navigation interceptor to check for unsent text
- Store drafts in UserDefaults or CoreData
- Consider draft expiry/cleanup strategy
- Test draft persistence across app restarts

---

## Test Note 17: Badges Don't Clear on iPad
**Date**: 2025-09-12

### Issue Description
Badges (notification indicators) don't seem to clear properly on iPad.

### Observed Behavior
- Badge counts remain visible after viewing messages
- Badges may not clear when entering a chat
- Issue appears to be iPad-specific
- App badge and/or chat badges may be affected

### Impact
Users see incorrect unread counts, leading to confusion about which chats have new messages and potentially causing unnecessary checking of already-read conversations.

### Potential Causes
- iPad-specific badge clearing logic issues
- Different app lifecycle on iPad (multitasking, split view)
- Badge update timing issues
- UserNotifications framework behavior differences on iPad
- Background refresh not updating badges correctly

### Areas to Investigate
- Test badge clearing in different iPad scenarios (split view, slide over)
- Check if issue occurs in both app icon badges and in-app badges
- Verify UNUserNotificationCenter badge update calls
- Test with different notification delivery methods
- Check if badges clear differently in foreground vs background
- Review iPad-specific notification handling code
- Test across different iPad models and iOS versions