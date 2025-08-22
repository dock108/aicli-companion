# Issue #6: Chat Scroll Position Resets to Top

**Priority**: High  
**Component**: iOS App - Chat View Scroll Management  
**Beta Blocker**: Yes - UX critical  
**Discovered**: 2025-08-19

## Problem Description

Users report that the chat view scroll position resets to the top of the conversation when navigating away and returning. This is especially annoying in long conversations. The issue occurs when:
- Switching between projects and returning to a conversation  
- Leaving the app and coming back (app backgrounding/foregrounding)
- Possibly when new messages arrive

## Problem Analysis

After reviewing the code, I've identified several issues with the current scroll position management:

1. **Global UserDefaults Storage**: The app uses a single global `lastReadMessageId` in UserDefaults, which gets overwritten when switching between projects. This causes scroll position loss when returning to previous conversations.

2. **Inconsistent Scroll Logic**: The `ChatMessageList` has complex scroll management with multiple flags (`hasInitiallyScrolled`, `isScrollingProgrammatically`, `isUserScrolling`) that can conflict and cause unexpected behavior.

3. **Message Loading Triggers**: When switching projects or returning from background, messages are reloaded which can trigger unwanted scroll position resets.

4. **Missing Project-Specific Persistence**: Scroll position is not saved per-project, so each project conversation doesn't maintain its own scroll state.

## Implementation Plan

### 1. Add Project-Specific Scroll Position Storage
- Store scroll position per project path instead of globally
- Save both the last visible message ID and whether user was at bottom
- Use keys like `scrollPosition_<projectPath>` and `wasAtBottom_<projectPath>`

### 2. Improve ChatMessageList Scroll Management
- Simplify the scroll state tracking logic
- Separate initial load scrolling from navigation scrolling
- Add proper debouncing for scroll position saves
- Fix the scroll-to-bottom behavior for new messages

### 3. Enhance Navigation Scroll Preservation
- Save scroll position in `onDisappear` 
- Restore correct position in `onAppear`
- Handle app backgrounding/foregrounding properly
- Prevent unnecessary scrolls during project switches

### 4. Implement Smart Auto-Scroll Logic
- Auto-scroll to bottom only when:
  - User sends a new message
  - User was already at bottom when assistant responds
  - Loading a conversation for the first time (and no saved position)
- Don't auto-scroll when:
  - User is reviewing history
  - Returning to an existing conversation with saved position
  - App comes back from background

## Files to Modify

1. **ChatMessageList.swift** - Main scroll logic improvements
   - Fix scroll position persistence to be project-specific
   - Simplify scroll state management
   - Improve auto-scroll logic

2. **ChatView.swift** - Add project-specific scroll position handling
   - Save scroll state on view disappear
   - Restore scroll state on view appear
   - Handle project switching properly

3. **MessagePersistenceService.swift** (if needed) - Add scroll position persistence methods
   - Add methods to save/load scroll position per project
   - Integrate with existing message persistence

## Expected Behavior After Fix

- Each project conversation maintains its own scroll position
- Switching projects and returning preserves exact scroll location
- New messages only trigger auto-scroll when user is at bottom
- App backgrounding/foregrounding maintains scroll position
- Follows standard messaging app patterns (WhatsApp/iMessage)

## Testing Scenarios

1. **Project Switching**: 
   - Open project A, scroll to middle of conversation
   - Switch to project B
   - Return to project A - should restore scroll position

2. **App Backgrounding**:
   - Scroll to specific position in conversation
   - Background the app
   - Return to app - should maintain scroll position

3. **New Messages**:
   - When at bottom: new messages should auto-scroll
   - When reviewing history: new messages should NOT auto-scroll
   - User messages should always scroll to bottom

4. **Long Conversations**:
   - Test with conversations having 100+ messages
   - Ensure smooth scrolling and position preservation

## Status

**Current Status**: ✅ FIXED - Compiled and app running successfully  
**Last Updated**: 2025-08-21

### Implementation Complete

All changes have been implemented and tested:
- ✅ Project-specific scroll position storage implemented
- ✅ Smart scroll restoration logic added
- ✅ Auto-scroll behavior improved for user vs assistant messages
- ✅ App backgrounding/foregrounding handled properly
- ✅ Code compiled successfully with no errors
- ✅ SwiftLint validation passed
- ✅ App running successfully

The chat scroll position now properly preserves position when:
- Switching between projects
- Backgrounding and foregrounding the app
- Receiving new messages while reviewing history
- Returning to previous conversations