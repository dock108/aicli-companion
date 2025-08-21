# Issue #13: Conversation Doesn't Load on First Click

**Priority**: High  
**Component**: iOS App - Navigation/Chat Loading  
**Beta Blocker**: Yes - Core navigation broken  
**Discovered**: 2025-08-21

## Problem Description

Clicking on a conversation in the sidebar doesn't load it on the first click. Users have to click on a different conversation first, then go back to the desired one for it to actually load. This creates a frustrating navigation experience and makes the app feel broken.

## Reproduction Steps

1. Open app with multiple existing conversations
2. Click on a conversation that isn't currently selected
3. Observe that messages don't load
4. Click on a different conversation
5. Click back on the original desired conversation
6. Now it loads properly

## Investigation Areas

1. Check conversation selection binding in sidebar/navigation view
2. Verify ChatViewModel properly responds to conversation ID changes
3. Look for race conditions in message loading when switching conversations
4. Check if NavigationLink or selection state is properly triggering view updates
5. Investigate if message persistence service has async loading issues
6. Verify proper @Published property updates in view models
7. Check for duplicate conversation IDs causing selection confusion
8. Look for any debouncing or throttling that might delay selection
9. Test if issue occurs with both empty and populated conversations

## Expected Behavior

Clicking on any conversation in the sidebar should immediately load and display that conversation's messages without requiring multiple clicks or workarounds.

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/Navigation/SidebarView.swift` (selection handling)
- `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift` (conversation loading)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (conversation switching logic)
- `ios/Sources/AICLICompanion/ViewModels/NavigationViewModel.swift` (if exists)
- `ios/Sources/AICLICompanion/Services/MessagePersistenceService.swift` (message loading)
- `ios/Sources/AICLICompanion/ProjectSelectionView.swift` (project selection)
- Check for any `.onAppear` or `.onChange` modifiers that might be interfering

## Status

**Current Status**: Investigating  
**Last Updated**: 2025-08-21