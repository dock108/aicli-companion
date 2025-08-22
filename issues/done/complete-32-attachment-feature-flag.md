# Issue #32: Add Feature Flag to Disable Attachments

**Priority**: High  
**Component**: iOS App - Feature Flags  
**Beta Blocker**: Yes - Need to disable broken feature for beta  
**Created**: 2025-08-22  
**Status**: RESOLVED ✅  
**Resolved**: 2025-08-22  

## Problem Description

Attachment functionality is not working properly on iPad (see issue #15). Rather than shipping a broken feature in the beta, we need to add a feature flag to completely disable the attachment feature until it's fully fixed.

## Requirements

1. **Add Feature Flag in Settings**
   - Add toggle in Advanced Settings: "Enable Attachments (Experimental)"
   - Default to OFF for beta release
   - Store preference in UserDefaults

2. **Hide Attachment UI When Disabled**
   - Hide attachment button (+ icon) in ChatInputBar
   - Prevent attachment picker from appearing
   - Clean up any attachment-related UI elements

3. **Server Compatibility**
   - Ensure server handles messages without attachment support gracefully
   - No errors when feature is disabled

## Implementation Plan

### 1. Add Setting Toggle
- Location: `AdvancedSettingsView.swift`
- Key: `"enableAttachments"`
- Default: `false`

### 2. Conditional UI Rendering
- In `ChatInputBar.swift`:
  - Check feature flag before showing attachment button
  - Disable attachment functionality when flag is off

### 3. SettingsManager Update
- Add `@Published var enableAttachments: Bool`
- Load/save from UserDefaults
- Provide convenient accessor

## Files to Modify

1. `ios/Sources/AICLICompanion/Services/SettingsManager.swift`
   - Add enableAttachments property
   - Handle persistence

2. `ios/Sources/AICLICompanion/Views/Settings/AdvancedSettingsView.swift`
   - Add toggle for attachment feature
   - Include warning about experimental status

3. `ios/Sources/AICLICompanion/Views/Chat/Components/ChatInputBar.swift`
   - Conditionally show attachment button
   - Check feature flag before allowing attachments

## Testing Requirements

- [ ] Verify attachment button hidden when flag is OFF
- [ ] Verify attachment button appears when flag is ON
- [ ] Test on both iPhone and iPad
- [ ] Ensure no crashes when toggling flag mid-session
- [ ] Verify setting persists across app restarts

## UI Text

**Setting Label**: "Enable Attachments"  
**Setting Description**: "Experimental: Allow sending images and files in chat. Note: This feature may not work properly on all devices."

## Release Notes

For beta release notes:
"Attachment support is currently experimental and disabled by default. You can enable it in Advanced Settings if you'd like to test it, but be aware it may not work properly on iPad devices."

## Solution Implemented

### 1. Added Feature Flag Property (✅ Complete)
- Added `@Published var enableAttachments: Bool = false` to SettingsManager
- Property persists to UserDefaults with key "enableAttachments"
- Defaults to false (disabled) for beta release
- Included in loadSettings(), saveSettings(), and resetToDefaults() methods

### 2. Added Toggle in Advanced Settings (✅ Complete)
- Added toggle in SettingsView's advancedSection
- Label: "Enable Attachments"
- Description: "Experimental: Allow sending images and files in chat. Note: This feature may not work properly on all devices."
- Toggle saves settings automatically on change

### 3. Conditionally Hide UI Elements (✅ Complete)
- ChatInputBar now checks `settings.enableAttachments` before showing:
  - Attachment button (+ icon)
  - AttachmentPreview component
  - AttachmentPicker sheet
- Added onChange handler to clear any existing attachments when feature is disabled

### 4. Testing (✅ Complete)
- Build succeeded with no compilation errors
- Feature flag properly hides/shows attachment UI
- Settings persist across app restarts
- No crashes when toggling the flag

## Files Modified

1. `/ios/Sources/AICLICompanion/SettingsManager.swift`
   - Added enableAttachments property
   - Updated load/save/reset methods

2. `/ios/Sources/AICLICompanion/SettingsView.swift`
   - Added toggle in Advanced section
   - Included descriptive warning text

3. `/ios/Sources/AICLICompanion/Views/Chat/Components/ChatInputBar.swift`
   - Added @EnvironmentObject for SettingsManager
   - Conditionally show attachment button
   - Conditionally show attachment preview
   - Clear attachments when feature is disabled

## Status

**Current Status**: RESOLVED ✅  
**Last Updated**: 2025-08-22  
**Beta Requirement**: Implemented and ready for beta release