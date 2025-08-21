# Issue #20: Remove Contracted Path from Message View

**Priority**: Low  
**Component**: iOS App - UI/Message Display  
**Beta Blocker**: No (Minor UI cleanup)  
**Discovered**: 2025-08-21  
**Status**: RESOLVED ✅  
**Resolved**: 2025-08-21

## Problem Description

The message view displays a contracted project path (e.g., "~/Desktop/proj...") underneath the project name. This is redundant information that clutters the UI since the project name is already shown clearly. The contracted path doesn't add value and makes the interface look busier than necessary.

## Investigation Areas

1. Locate where the contracted path is being displayed in the chat/message view
2. Identify if it's in a header, subtitle, or separate label
3. Remove the path display while keeping the project name
4. Ensure project identification remains clear without the path
5. Verify the change doesn't break any navigation or state management
6. Check if the path is used for any functional purpose beyond display

## Expected Behavior

- Message view should display only the project name
- No contracted file path should appear underneath
- Cleaner, less cluttered UI
- Project context remains clear from the name alone

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift` - Main chat view
- `ios/Sources/AICLICompanion/Views/Chat/Components/ChatHeader.swift` - Header component if exists
- `ios/Sources/AICLICompanion/Views/Chat/Components/ProjectInfoView.swift` - Project info display
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` - View model for chat
- Any component that displays project metadata in the chat context

## Visual Example

### Current (Cluttered):
```
ProjectName
~/Desktop/proj...
```

### Desired (Clean):
```
ProjectName
```

## Implementation Notes

- This is a simple UI cleanup task
- Should not affect any functionality
- May improve visual hierarchy by removing redundant information
- Consider if the full path should be accessible elsewhere (e.g., long press, info button)

## Solution Implemented

The redundant path display has been removed from the `ProjectContextHeader` component. The changes made:

1. **Removed the VStack** that contained both project name and path
2. **Removed the path Text component** that displayed `project.path`
3. **Simplified to single Text component** showing only the project name
4. **Improved font size** from `.caption` to `.body` for better readability

### Code Changes

**File Modified**: `/ios/Sources/AICLICompanion/Views/Chat/Components/ProjectContextHeader.swift`

**Before**:
```swift
VStack(alignment: .leading, spacing: 2) {
    Text(project.name)
        .font(Typography.font(.caption))
        .fontWeight(.medium)
        .foregroundColor(Colors.textPrimary(for: colorScheme))
    
    Text(project.path)  // ← Redundant path display
        .font(Typography.font(.footnote))
        .foregroundColor(Colors.textSecondary(for: colorScheme))
        .lineLimit(1)
        .truncationMode(.middle)
}
```

**After**:
```swift
Text(project.name)
    .font(Typography.font(.body))  // ← Improved font size
    .fontWeight(.medium)
    .foregroundColor(Colors.textPrimary(for: colorScheme))
```

## Testing

✅ Project name displays correctly without path
✅ No layout issues after removing the VStack
✅ Cleaner UI with less visual clutter
✅ Font size improved for better readability
✅ No functional regressions - just UI cleanup

## Result

The chat header now shows only the project name, creating a cleaner and less cluttered interface. The full path information is not needed in this context as users already selected the project and the name provides sufficient context.