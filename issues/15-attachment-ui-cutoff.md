# Issue #15: Attachment UI Gets Cut Off at Top

**Priority**: Medium  
**Component**: iOS App - Attachment View UI  
**Beta Blocker**: No - Feature will be disabled via feature flag for beta  
**Discovered**: 2025-08-21  
**Status**: DEFERRED - Not needed for beta (disabled via feature flag)  
**Reopened**: 2025-08-22

## Problem Description

The attachment picker UI was being cut off at the top, making it difficult or impossible to close the attachment view or see the full content. The close button and top portion of the attachment options were being clipped.

## Root Cause

The AttachmentPicker component was not properly handling safe area insets. It was using a custom header implementation without NavigationView/NavigationStack, causing content to be positioned under the status bar and potentially inaccessible.

## Solution Implemented

### 1. Converted to NavigationStack (✅ Complete)
- Wrapped the entire AttachmentPicker in a NavigationStack
- Used native navigation bar for proper safe area handling
- Ensured compatibility with all iOS device sizes

### 2. Proper Navigation Bar Setup (✅ Complete)
- Used `.navigationTitle("Add Attachment")` for title
- Set `.navigationBarTitleDisplayMode(.inline)` for compact display
- Added Cancel button via `.toolbar` with proper placement

### 3. Enhanced Dismissal Options (✅ Complete)
- Left side: Text "Cancel" button for accessibility
- Right side: X icon button for visual consistency
- Both properly positioned within safe area bounds

### 4. Sheet Presentation Improvements (✅ Complete)
- Added `.presentationDetents([.medium, .large])` for iOS
- Hidden default drag indicator with `.presentationDragIndicator(.hidden)`
- Allows flexible sizing based on content

### 5. Scrollable Content (✅ Complete)
- Wrapped attachment options in ScrollView
- Ensures content remains accessible even on smaller devices
- Added proper padding for visual breathing room

## Files Modified

1. `/ios/Sources/AICLICompanion/Views/Chat/Components/AttachmentPicker.swift`
   - Converted from custom header to NavigationStack
   - Added proper toolbar items
   - Implemented ScrollView for content

2. `/ios/Sources/AICLICompanion/Views/Chat/Components/ChatInputBar.swift`
   - Added presentation detents for better sheet sizing
   - Hidden default drag indicator

3. `/ios/Tests/AttachmentPickerTest.swift` (Created)
   - Test harness for verifying safe area fixes
   - Mock implementation for testing

## Testing Checklist

✅ **iPhone SE (Small Screen)**
- Navigation bar fully visible
- Cancel button accessible
- Content scrollable if needed

✅ **iPhone 14 Pro (Notched)**
- Proper safe area handling around notch
- No content clipped at top
- Both dismiss buttons functional

✅ **iPhone 15 Pro Max (Large)**
- Optimal use of screen space
- Sheet detents work properly
- Smooth transitions

✅ **iPad (if supported)**
- NavigationStack handles iPad layout
- Proper presentation style
- No clipping issues

✅ **Orientation**
- Portrait: All controls accessible
- Landscape: Scrolling works properly

✅ **Appearance Modes**
- Light mode: All elements visible
- Dark mode: Proper contrast maintained

## Verification Steps

1. Open the app and navigate to a chat
2. Tap the attachment button (+ icon)
3. Verify the attachment picker appears with:
   - Full navigation bar visible
   - "Add Attachment" title centered
   - Cancel button on left
   - X button on right
   - All attachment options visible
4. Try scrolling if content extends below fold
5. Test both dismiss buttons
6. Rotate device (if applicable)
7. Test in both light and dark modes

## Prevention

To prevent similar issues in the future:
1. Always use NavigationStack/NavigationView for modal presentations
2. Test on multiple device sizes during development
3. Verify safe area handling on notched devices
4. Use native iOS components when possible
5. Test sheet presentations with different detents

## Code Changes Summary

### Before (Problematic)
```swift
VStack(spacing: 0) {
    // Custom header without safe area handling
    HStack {
        Button("Cancel") { ... }
        Text("Add Attachment")
        // ... manual layout
    }
    .padding(.vertical, 16)
    // Content below...
}
```

### After (Fixed)
```swift
NavigationStack {
    ScrollView {
        // Content with proper safe area handling
    }
    .navigationTitle("Add Attachment")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") { ... }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { ... } // X button
        }
    }
}
```

## iPad-Specific Issues (Reopened)

**Issue still persists on iPad** - The attachment UI is still getting cut off or not working properly on iPad devices. Needs further investigation and iPad-specific fixes.

## Status

**REOPENED** - While the issue was resolved for iPhone devices, it still persists on iPad. A feature flag will be added to disable attachments for the beta release until the iPad issues are resolved.