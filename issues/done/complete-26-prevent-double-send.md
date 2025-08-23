# Issue #26: Prevent Sending Messages While Awaiting Claude Response

**Priority**: High  
**Component**: iOS App - Message Input UI  
**Beta Blocker**: Yes (Prevents message queue confusion)  
**Discovered**: 2025-08-22  
**Status**: New  

## Problem Description

Users can currently send multiple messages before Claude responds to the first one, which can cause confusion and potentially break the conversation flow since we don't have message queueing implemented yet. The send button should be disabled/greyed out when the last message in the conversation was sent by the user and we're waiting for Claude's response.

## Investigation Areas

1. Check if logic already exists in codebase from previous testing
2. Implement send button state based on last message sender
3. Grey out send button similar to iMessage when unavailable
4. Visual feedback that we're waiting for Claude
5. Re-enable immediately when Claude's response arrives
6. Handle error cases where response never comes
7. Consider showing "Claude is thinking..." or similar indicator
8. Ensure state persists correctly across app restarts

## Expected Behavior

- Send button disabled/greyed out after user sends a message
- Clear visual indication that we're waiting for Claude (similar to iMessage unavailable state)
- Send button re-enables immediately when Claude responds
- Text input remains active (user can still type while waiting)
- If Claude errors out, send button should re-enable with error message

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/Chat/ChatInputView.swift` (send button state)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (message state tracking)
- `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift` (overall state management)
- Check git history for previous implementation attempts
- Look for existing `isWaitingForResponse` or similar flags

## Implementation Approach

### 1. State Management
- Track `isWaitingForResponse` in ChatViewModel
- Set to true when user sends message
- Set to false when Claude responds or errors

### 2. UI Updates
- Bind send button enabled state to !isWaitingForResponse
- Use system grey color for disabled state
- Consider adding progress indicator

### 3. Edge Cases
- Handle timeout scenarios (re-enable after X time)
- Handle connection loss (show error, re-enable)
- Handle app restart while waiting

## Testing Requirements

### Manual Testing Steps
1. Send a message
2. Verify send button greys out immediately
3. Try clicking greyed out button (should do nothing)
4. Wait for Claude response
5. Verify button re-enables immediately

### Test Scenarios
- [ ] Normal message → response flow
- [ ] Error response re-enables button
- [ ] Timeout re-enables button
- [ ] Connection loss handling
- [ ] App restart while waiting

## Notes

- This is a temporary solution until proper message queueing is implemented (Issue #3)
- Even with queue, this UX pattern may be valuable to prevent accidental sends
- Similar to iMessage behavior when recipient is unavailable
- Much of the logic may already exist in the codebase from previous testing

## Root Cause Analysis

The infrastructure for preventing double-sends was already in place but not fully connected:
1. `ProjectState` had an `isWaitingForResponse` flag
2. `shouldBlockSending` checked both `isLoading` and `isWaitingForResponse`
3. ChatInputBar was already disabling the button when `isSendBlocked`
4. However, `isWaitingForResponse` was never being set/cleared

## Solution Implemented

### 1. Set Waiting State When Sending
In `ChatViewModel.sendMessage()`:
- Set `loadingStateManager.setWaitingForResponse(true)`
- Update project state: `state.isWaitingForResponse = true`

### 2. Clear Waiting State on Response
In `ChatNotificationHandler.clearLoadingStateIfNeeded()`:
- Clear project state: `state.isWaitingForResponse = false`

### 3. Clear Waiting State on Error
In `ChatViewModel` error handling:
- Set `loadingStateManager.setWaitingForResponse(false)`
- Clear project state: `state.isWaitingForResponse = false`

### 4. Unified Clearing Method
Updated `ChatViewModel.clearLoadingState()` to also clear project state

## Files Modified

1. `/ios/Sources/AICLICompanion/Views/Chat/ViewModels/ChatViewModel.swift`
   - Set `isWaitingForResponse` when sending message
   - Clear on error
   - Updated `clearLoadingState` method

2. `/ios/Sources/AICLICompanion/Views/Chat/ViewModels/ChatNotificationHandler.swift`
   - Clear `isWaitingForResponse` when response arrives

## Status

**Current Status**: Resolved  
**Last Updated**: 2025-08-22  
**Solution**: Connected existing infrastructure by properly setting/clearing the `isWaitingForResponse` flag