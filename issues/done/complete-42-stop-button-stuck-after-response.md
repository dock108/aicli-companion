# Issue #42: Stop Button Stuck After Response

**Priority**: High  
**Component**: iOS App - State Management  
**Beta Blocker**: Yes (UI stuck in wrong state)  
**Discovered**: 2025-08-23  
**Status**: Fixed  

## Problem Description

The stop button sometimes remains visible after Claude responds, preventing users from sending new messages. The send button should return when processing completes.

## Root Cause

Race condition with Task blocks:
1. Setting `isProcessing = true` was wrapped in `Task { @MainActor in }`
2. Clearing `isProcessing = false` was also in a Task block
3. Task scheduling could cause the clear to happen before the set

## Solution Implemented

Removed unnecessary Task wrappers since the code is already on MainActor:

### Before (Broken)
```swift
// Setting
Task { @MainActor in
    ProjectStatusManager.shared.statusFor(project).isProcessing = true
}

// Clearing
Task { @MainActor in
    ProjectStatusManager.shared.statusFor(project).isProcessing = false
}
```

### After (Fixed)
```swift
// Setting
ProjectStatusManager.shared.statusFor(project).isProcessing = true

// Clearing  
ProjectStatusManager.shared.statusFor(project).isProcessing = false
```

## Files Modified

1. **ChatViewModel.swift**:
   - Removed Task wrapper when setting isProcessing = true
   - Removed Task wrapper when clearing on error
   - Added debug logging

2. **ChatNotificationHandler.swift**:
   - Removed Task wrapper when clearing isProcessing = false
   - Added debug logging

## Debug Logging Added

```swift
// When setting
print("🔴 Setting processing state for project: \(project.path)")
print("✅ Processing state set. isProcessing = \(isProcessing)")

// When clearing
print("🔄 Clearing processing state for project: \(project.path)")
print("✅ Processing state cleared. isProcessing = \(isProcessing)")
```

## Testing

1. Send a message
2. Verify stop button appears
3. Wait for Claude's response
4. Verify send button returns (stop button disappears)
5. Check logs for state transitions

## Status

**Current Status**: Fixed  
**Last Updated**: 2025-08-23  
**Implementation**: Removed Task wrappers to prevent race conditions
**Build Status**: ✅ BUILD SUCCEEDED