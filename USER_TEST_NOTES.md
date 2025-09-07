# User Test Notes

## Test Note 1: Response Timeout Issue
**Date**: 2025-09-06

### Issue Description
Super long time to response messages seem to trigger a timeout somewhere despite still working.

### Observed Behavior
- Push notification eventually arrives with the message
- Message doesn't appear in the chat interface
- Chat UI remains stuck on "thinking" state
- **Multiple "failed to process APNS" alerts appear at regular intervals**
- **These APNS failures occur even while Claude is still actively thinking on the server side**

### Impact
Users experience a broken flow where responses are received via push but not displayed in the active chat session. The repeated APNS failure alerts add to confusion about the system state.

### Potential Areas to Investigate
- WebSocket connection timeout settings
- HTTP request timeout configurations
- Session timeout handling
- Message correlation between push notifications and chat UI
- Client-side timeout handling in the iOS app
- **APNS retry logic that may be too aggressive**
- **Why APNS processing fails while server is still working**
- **Timeout mismatch between client expectations and server processing time**

---

## Test Note 2: Broken Documentation Links
**Date**: 2025-09-06

### Issue Description
Documentation links appear to be broken throughout the application.

### Observed Behavior
- Clicking any documentation link shows "failed to load file" error
- All doc links affected, not isolated to specific sections

### Impact
Users cannot access documentation or help resources from within the app.

### Potential Areas to Investigate
- File path resolution in the documentation viewer
- URL scheme handling for doc links
- Missing or moved documentation files
- Permissions or access issues for doc files
- Base URL or path configuration for documentation

---

## Test Note 3: Thinking Response UI Scrolling Issue
**Date**: 2025-09-06

### Issue Description
The thinking response indicator doesn't automatically scroll the chat view up, causing it to be hidden behind the message input bar.

### Observed Behavior
- Thinking indicator appears but gets obscured by the message type bar
- Requires manual scrolling to see the thinking indicator
- May be intermittent (not happening consistently every time)

### Impact
Users may not realize the app is processing their request if the thinking indicator is hidden, leading to confusion about whether their message was received.

### Potential Areas to Investigate
- Auto-scroll behavior when thinking indicator appears
- Chat view content inset adjustments
- Keyboard avoidance and view positioning logic
- Timing of scroll animations vs thinking indicator appearance
- Conditional logic that might cause intermittent behavior

---

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

## Test Note 5: Missing New Message Indicators on Main Screen
**Date**: 2025-09-06

### Issue Description
The main screen lacks any indication of new messages, making it impossible to know when responses arrive without opening the chat.

### Current State
- No new message indicator/badge
- No message preview
- No visual feedback when new messages arrive
- Users must manually check chats to see if there are responses

### Impact
Users miss important responses and have no way to know when Claude has replied without actively checking, significantly degrading the user experience.

### Recommended Features
- Re-enable new message indicator/badge on main screen
- Add message preview (first line or snippet of new message)
- Consider notification dot or count badge
- Maybe show timestamp of last message
- Could add subtle animation when new message arrives
- Preview could show sender (User/Claude) and truncated message text

---

## Test Note 6: Chat Mode Should Persist Per Chat, Not Globally
**Date**: 2025-09-06

### Issue Description
Chat mode (planning/normal) currently appears to persist globally across all chats, but it should be maintained individually per chat/project.

### Current Behavior
- Switching between projects/chats maintains the same mode
- If in planning mode in one project, switching to another project keeps planning mode active
- This can lead to accidental wrong mode usage when quickly switching between projects

### Expected Behavior
- Each chat/project should remember its own mode setting
- Switching to a different project should restore that project's last used mode
- Mode should be stored as part of the chat/conversation state, not as a global setting

### Impact
Users accidentally use the wrong mode when switching between projects, potentially causing unintended behavior (e.g., being in normal mode when they expect planning mode for a specific project).

### Implementation Considerations
- Store mode preference with each chat/conversation
- Load appropriate mode when switching chats
- Ensure mode indicator clearly shows current state
- Consider defaulting new chats to a sensible mode (likely normal)

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