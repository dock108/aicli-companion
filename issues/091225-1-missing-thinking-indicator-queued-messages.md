# Issue 091225-1: Missing Thinking Indicator When Queued Messages Go to In-Progress

**Priority**: High  
**Component**: iOS App - Chat UI  
**Beta Blocker**: Yes - UI feedback missing  
**Discovered**: 2025-09-12  
**Status**: New  

## Problem Description

When a queued message transitions to in-progress status, there's no thinking indicator shown in the iOS app. The UI continues to look like it's waiting for a message, giving no visual feedback that Claude is actually processing the request.

## Observed Behavior

- Message is queued and shows as pending
- Message transitions to in-progress on the server
- iOS app does not show thinking indicator
- UI appears stuck in "waiting" state
- No visual feedback that processing has begun
- Users may think nothing is happening

## Expected Behavior

- When message goes from queued to in-progress, show thinking indicator
- Clear visual transition from "queued" to "processing"
- Thinking bubble or animation should appear immediately
- Users should see that Claude is actively working on their request

## Impact

Users have no visual confirmation that their message is being processed, leading to:
- Uncertainty about whether the system is working
- Potential duplicate message sends
- Poor user experience during the wait
- Confusion about system status

## Potential Root Causes

1. **Missing Status Update**: In-progress status not triggering UI update
2. **State Management Issue**: Chat state not properly updating from queued to in-progress
3. **WebSocket Message Handling**: Status change message not properly processed
4. **UI Component Logic**: Thinking indicator only triggered by certain events
5. **Race Condition**: Status update arriving before UI is ready

## Suggested Solutions

### Immediate Fix
1. Ensure in-progress status triggers thinking indicator
2. Add explicit handling for queued → in-progress transition
3. Update ChatView to show thinking state for in-progress messages

### Complete Solution
1. Audit all message status transitions
2. Ensure each status has appropriate UI representation
3. Add smooth transitions between states
4. Consider adding queue position indicator
5. Implement proper state machine for message lifecycle

## Message Status Flow

Current statuses that need UI representation:
- **Queued**: Show queue indicator or "waiting" state
- **In-Progress**: Show thinking indicator/animation
- **Completed**: Show response
- **Failed**: Show error state

## Files to Investigate

- `ChatView.swift` - Main chat UI and thinking indicator logic
- `ChatViewModel.swift` - Message state management
- `WebSocketManager.swift` - Status update message handling
- `Message.swift` - Message status definitions
- Any thinking indicator components

## Testing Requirements

1. Send message while Claude is busy (to trigger queue)
2. Verify thinking indicator appears when processing starts
3. Test rapid status transitions
4. Verify all status states have proper UI
5. Test with multiple queued messages
6. Check WebSocket message handling for status updates

## Related Issues

- Chat UI Instability (Test Note 7) - General UI issues
- Typing Bubble Delay (complete-37) - Similar thinking indicator issues

## Notes

This is a critical UX issue that makes the app appear unresponsive during a key interaction point. The fix should ensure users always have clear visual feedback about what the system is doing with their message.