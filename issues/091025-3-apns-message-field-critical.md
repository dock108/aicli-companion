# Issue 091025-3: CRITICAL - APNS Notifications Not Clearing Thinking Indicator

**Priority**: URGENT/CRITICAL  
**Component**: Server - APNS Notification Payload  
**Beta Blocker**: YES - All messages appear stuck in "thinking" state  
**Discovered**: 2025-09-10  
**Status**: Fixed - Awaiting Testing  
**Type**: Critical Bug  

## Problem Description

ALL Claude responses are failing to clear the thinking indicator in the iOS app due to a field name mismatch introduced by recent APNS payload optimization. Messages are being delivered but the app shows perpetual "thinking" state.

## Current Behavior

1. Server sends APNS notification with `messagePreview` field (not `message`)
2. iOS app looks for `message` field in PushNotificationService.swift line 387
3. When `message` field is missing and `requiresFetch` is false, notification is ignored
4. Thinking indicator never clears, making app appear frozen
5. Affects ALL messages, not just large ones

## Root Cause

In `server/src/services/push-notification/notification-types.js`:
- Line 270 destructures and excludes the `message` field: `const { message: _message, ...metadataOnly }`
- Line 280-282 adds `messagePreview` field instead
- iOS app expects `message` field, not `messagePreview`

## Impact

- **CRITICAL**: App appears broken/frozen for all users
- All messages show perpetual thinking state
- Users cannot tell when responses are complete
- Makes app unusable for real work

## Fix Required

The iOS app needs to handle the `messagePreview` field when `message` is not present:

```swift
// PushNotificationService.swift line 387
} else if let claudeMessage = userInfo["message"] as? String ?? userInfo["messagePreview"] as? String,
          let projectPath = userInfo["projectPath"] as? String {
```

OR restore the `message` field in the server payload (but keep it small).

## Reproduction

1. Send ANY message to Claude
2. Server logs show "Claude response delivered via APNS"
3. App continues showing thinking indicator indefinitely
4. Message content never appears

## Fix Implemented

Updated `PushNotificationService.swift` line 387 to handle both `message` and `messagePreview` fields:
```swift
} else if let claudeMessage = (userInfo["message"] as? String) ?? (userInfo["messagePreview"] as? String),
          let projectPath = userInfo["projectPath"] as? String {
```

This ensures the app processes notifications regardless of which field name is used.

## Verification

After fix:
1. Send message
2. Thinking indicator should clear when response arrives
3. Message content should appear
4. Test with both small and large messages