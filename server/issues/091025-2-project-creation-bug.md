# Issue 091025-2: Project Creation Returns Success When Project Already Exists

**Priority**: Medium  
**Component**: Server - Workspace Routes  
**Beta Blocker**: No  
**Discovered**: 2025-09-10  
**Status**: Open  
**Type**: Bug  

## Problem Description

The `create_project` operation in workspace routes incorrectly returns success when attempting to create a project that already exists. This is due to improper error handling and the use of `recursive: true` in `fs.mkdir`, which doesn't fail when the directory exists.

## Current Behavior

When `create_project` is called with a project name that already exists:
1. The function attempts to create the directory with `fs.mkdir({ recursive: true })`
2. Because `recursive: true` is used, no error is thrown if the directory exists
3. The function returns `{ success: true }` even though no new project was created
4. This gives false feedback to the user that a new project was created

## Expected Behavior

When attempting to create a project that already exists:
1. The function should check if the directory exists before attempting creation
2. If it exists, return an appropriate error response
3. Only return success when a new project directory is actually created
4. Provide clear feedback about what happened

## Root Cause

Located in `server/src/routes/workspace.js`:

```javascript
// Current problematic code
await fs.mkdir(fullPath, { recursive: true });
// This doesn't fail if directory exists, so execution continues
```

The issue is compounded by:
1. No pre-existence check before attempting creation
2. Using `recursive: true` which silently succeeds on existing directories
3. Catch block that swallows errors without proper handling

## Reproduction Steps

1. Create a project with name "test-project"
2. Attempt to create another project with the same name "test-project"
3. Observe that the API returns success even though no new project was created
4. Check filesystem - only one directory exists, not two

## Proposed Fix

```javascript
async function createProject(projectPath, projectName) {
  const fullPath = path.join(projectPath, projectName);
  
  // Check if project already exists
  try {
    await fs.access(fullPath);
    // If we get here, the directory exists
    return {
      success: false,
      error: 'PROJECT_EXISTS',
      message: `Project "${projectName}" already exists at this location`
    };
  } catch (error) {
    // Directory doesn't exist, proceed with creation
  }
  
  try {
    // Create without recursive flag to catch immediate parent issues
    await fs.mkdir(fullPath);
    return {
      success: true,
      message: `Project "${projectName}" created successfully`,
      path: fullPath
    };
  } catch (error) {
    return {
      success: false,
      error: error.code || 'CREATE_FAILED',
      message: `Failed to create project: ${error.message}`
    };
  }
}
```

## Impact

- **User Experience**: Users receive incorrect feedback about project creation
- **Data Integrity**: No data loss, but confusing state
- **API Contract**: API returns success for failed operations
- **Testing**: Test currently documents the buggy behavior instead of correct behavior

## Testing Requirements

After fix is implemented:
1. Test creating a new project succeeds
2. Test creating duplicate project fails with clear error
3. Test creating project in non-existent parent directory fails appropriately
4. Test error messages are clear and actionable
5. Update the test in `workspace.test.js` to expect correct behavior

## Related Files

- `/server/src/routes/workspace.js` - Contains the bug
- `/server/src/test/routes/workspace.test.js` - Test documenting buggy behavior
- `/server/src/services/project-creator.js` - May need similar fix

## Notes

This bug was discovered through test documentation that explicitly noted the incorrect behavior. The test should be updated once the bug is fixed to expect the correct behavior rather than documenting the bug.

## Success Criteria

- [ ] Project creation fails appropriately when project exists
- [ ] Clear error message returned to user
- [ ] Test updated to verify correct behavior
- [ ] No regression in other project operations
- [ ] Consider adding validation for project names (e.g., no special characters)