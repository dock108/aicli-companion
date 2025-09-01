# Issue #22: Root Directory Chat Assistant

**Priority**: Low  
**Component**: iOS App - Workspace Mode  
**Beta Blocker**: No - Enhancement for post-beta  
**Discovered**: 2025-08-21  
**Status**: New  

## Problem Description

Add the ability to have a conversation with Claude at the root directory level (parent of all projects) to perform cross-project operations and file management tasks in the iOS app. The iOS app would provide the UI for workspace mode selection, while the server handles the actual root directory access. This would enable users to ask Claude to do things like move files between projects, create new project folders, search across all projects, organize files and directories, perform batch operations across multiple projects, and get an overview of the entire workspace.

**Note**: This is an enhancement idea for post-beta development. Not required for beta release.

## Investigation Areas

1. Add a special "Workspace" or "Root" option in project selection
2. When selected, Claude operates at the parent directory level
3. Could show a different UI indicator when in "workspace mode"
4. Server would need to handle commands at the root level safely
5. Additional security considerations for broader file system access

## Expected Behavior

Users can select a "Workspace" mode to have Claude operate across all projects, enabling cross-project file operations and workspace-level management tasks.

## Use Cases

- "Move all test files from project-a to project-b"
- "Create a new project called 'my-new-app' with a basic folder structure"
- "Find all TODO comments across all my projects"
- "Show me which projects have package.json files"
- "Archive old projects I haven't touched in 30 days"

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/ProjectSelectionView.swift` (add workspace option)
- `server/src/services/aicli-session-manager.js` (handle root directory context)
- `server/src/utils/path-security.js` (security validation for root operations)
- `ios/Sources/AICLICompanion/ViewModels/WorkspaceViewModel.swift` (to be created)

## Why Not Beta

This is a nice-to-have enhancement that adds complexity. The core chat functionality within individual projects is sufficient for beta. This can be explored based on user feedback about workflow needs.

## Testing Requirements

### Manual Testing Steps
1. Test workspace mode selection
2. Verify cross-project operations
3. Test security boundaries
4. Validate file operations

### Test Scenarios
- [ ] Workspace mode activation
- [ ] Cross-project file operations
- [ ] Security validation
- [ ] UI mode indicators

## Status

**Current Status**: New - Deferred to post-beta  
**Last Updated**: 2025-08-22