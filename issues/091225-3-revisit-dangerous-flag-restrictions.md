# Issue 091225-3: Revisit --dangerously-skip-permissions Flag Restrictions

**Priority**: Medium  
**Component**: Server - Security/Permissions  
**Beta Blocker**: No  
**Discovered**: 2025-09-12  
**Status**: New  

## Context

Now that we've identified and resolved the SIGTERM timeout issue that was causing problems earlier, we should revisit the use of the `--dangerously-skip-permissions` flag and explore adding more restrictions to improve security while maintaining functionality.

## Background

The `--dangerously-skip-permissions` flag was likely needed to work around permission issues or timeouts that were actually being caused by the 5-minute SIGTERM limit in Claude CLI. With that issue now understood and handled properly, we may be able to implement more granular permissions.

## Current State

- Server runs Claude CLI with `--dangerously-skip-permissions` flag
- This gives Claude full system access without restrictions
- Originally needed to avoid permission-related issues
- SIGTERM timeout issue (exit code 143) has been identified and handled

## Proposed Investigation

### 1. Test Without Dangerous Flag
- Remove the flag and test normal operations
- Document any permission errors that occur
- Identify minimum required permissions

### 2. Implement Granular Permissions
- Use more specific permission flags if available
- Consider file system restrictions
- Implement path-based access controls
- Add read-only vs write permissions where appropriate

### 3. Security Improvements
- Restrict access to sensitive directories
- Prevent modification of system files
- Limit network access if not needed
- Add audit logging for file operations

## Benefits of Addressing This

1. **Improved Security**: Reduce attack surface and potential for accidental damage
2. **Better Compliance**: Meet security requirements for production deployment
3. **User Trust**: Users more comfortable with restricted permissions
4. **Error Prevention**: Prevent accidental modification of important files

## Testing Requirements

1. Full regression testing without dangerous flag
2. Document all permission requirements
3. Test with various Claude CLI operations
4. Verify timeout handling still works
5. Check file operations, both read and write
6. Test across different project types

## Related Issues

- Claude 5-minute timeout with SIGTERM (complete-091125-claude-5-minute-timeout.md)
- Original permission issues that led to using the flag

## Implementation Approach

1. Create test branch without dangerous flag
2. Run comprehensive test suite
3. Document all permission errors
4. Implement minimal required permissions
5. Add permission configuration options
6. Update documentation with security best practices

## Notes

This is a security enhancement that became possible after understanding the real cause of earlier issues. The SIGTERM timeout was likely misidentified as a permission problem, leading to the use of the dangerous flag as a workaround. Now we can implement proper security boundaries.