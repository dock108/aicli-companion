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