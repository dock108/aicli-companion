# Security Model: Prompt-Based Trust Architecture

## Overview

AICLI Companion uses a **prompt-based security model** with `--dangerously-skip-permissions` for optimal performance and reliability. Security is enforced through carefully crafted system prompts rather than CLI-level restrictions.

> ⚠️ **Important**: This system trusts Claude Code CLI completely and relies on prompt-based guidelines for security boundaries. It is designed for trusted environments where users understand they are granting full system access to an AI assistant.

## Security Architecture

### Core Principle: Trust with Guidance

Instead of technical restrictions, we use comprehensive system prompts that:
- Clearly define allowed vs restricted operations  
- Establish project vs workspace boundaries
- Provide explicit security guidelines to Claude
- Rely on Claude's adherence to instructions

### Why This Approach?

1. **Eliminates SIGTERM Issues**: No more tool limits causing interrupted conversations
2. **Better Performance**: No permission prompts or delays during operation
3. **Cleaner Codebase**: Removes complex restart and session management logic
4. **More Reliable**: Fewer failure points and edge cases
5. **Appropriate for AI**: AI assistants work best with clear guidelines, not artificial barriers

## Operating Modes

### Project Mode
When working within a specific project directory:

```
✅ ALLOWED WITHIN PROJECT:
- Full file system access (read, write, edit, delete)
- Execute any Bash commands and tools
- Create, modify, and delete files and directories
- Install dependencies and run development tools

⛔ RESTRICTED OUTSIDE PROJECT:
- READ-ONLY access to files outside project (reference only)
- NO writing, editing, or deleting files outside project scope
- NO executing commands that modify system or other projects
- NO accessing sensitive files (credentials, SSH keys, system configs)
```

### Workspace Mode
When operating in cross-project workspace mode:

```
✅ ALLOWED OPERATIONS:
📖 READ-ONLY ANALYSIS:
- Browse and read files across ALL existing projects
- Analyze project structures and dependencies
- Compare implementations between projects

🆕 NEW PROJECT CREATION:
- Create entirely new project directories
- Generate starter files for NEW projects only
- Set up initial configuration files

⛔ STRICT RESTRICTIONS:
- NO modifications to ANY existing project files
- NO writing/editing in established projects
- NO Bash commands that modify existing projects
```

## Security Prompts

### Project Mode Prompt Structure
```
[PROJECT MODE SECURITY CONTEXT]

⚠️ CRITICAL: You are operating with FULL SYSTEM ACCESS via --dangerously-skip-permissions.
   The security model relies entirely on your adherence to these guidelines.

🎯 PROJECT SCOPE: /path/to/project

✅ ALLOWED WITHIN PROJECT DIRECTORY: [detailed permissions]
⛔ RESTRICTED OUTSIDE PROJECT DIRECTORY: [detailed restrictions]
🛡️ SECURITY PRINCIPLES: [guidelines and verification steps]

USER REQUEST: [actual user prompt]
```

### Workspace Mode Prompt Structure
```
[WORKSPACE MODE SECURITY CONTEXT]

⚠️ CRITICAL: You are operating with FULL SYSTEM ACCESS via --dangerously-skip-permissions.
   The security model relies entirely on your adherence to these workspace restrictions.

🌐 WORKSPACE SCOPE: Cross-project operations and new project creation

✅ ALLOWED OPERATIONS: [detailed read-only and creation permissions]
⛔ STRICT RESTRICTIONS: [detailed modification restrictions]
🛡️ SECURITY PRINCIPLES: [guidelines and verification steps]

USER REQUEST: [actual user prompt]
```

## Configuration

### Enabling Prompt-Based Security

In `server/src/services/aicli-process-runner/config.js`:

```javascript
export class AICLIConfig {
  constructor(options = {}) {
    // Permission configuration
    this.permissionMode = 'default';
    this.allowedTools = ['Read', 'Write', 'Edit']; // Not used when skipPermissions = true
    this.disallowedTools = [];
    this.skipPermissions = true; // 🔑 This enables prompt-based security
  }
}
```

### No Environment Variables Required

Unlike traditional permission systems, this approach requires no additional configuration:
- No `AICLI_SAFE_DIRECTORIES`
- No `AICLI_BLOCKED_COMMANDS` 
- No `AICLI_SECURITY_PRESET`
- No complex permission API endpoints

## Benefits

### ✅ Advantages
- **No SIGTERM interruptions**: Conversations can continue indefinitely
- **Simplified architecture**: Removes hundreds of lines of complex restart logic
- **Better user experience**: No permission prompts or delays
- **More reliable**: Fewer failure modes and edge cases
- **Appropriate trust model**: Users understand they're granting AI access

### ⚠️ Considerations
- **Requires trust**: Users must trust Claude to follow prompt guidelines
- **No technical enforcement**: Security boundaries are guidance-based
- **User responsibility**: Users should understand the implications of full access

## Best Practices

### For Developers
1. **Understand the model**: You're granting full system access to Claude
2. **Use project mode**: Work within specific project directories when possible
3. **Review operations**: Be aware of what Claude is doing in your environment
4. **Backup important data**: As with any development tool that has write access

### For Organizations
1. **Train users**: Ensure users understand the trust-based security model
2. **Use isolated environments**: Consider running on VMs or containers for additional isolation
3. **Monitor activity**: Review logs and activity patterns
4. **Have incident response**: Know how to respond if something goes wrong

### For System Administrators
1. **Network isolation**: Limit network access from the Claude CLI environment
2. **File system isolation**: Use containerization or VMs for additional boundaries
3. **Regular backups**: Ensure critical systems are backed up regularly
4. **Monitoring**: Watch for unusual activity patterns

## Security Principles

### Trust-Based Architecture
This system is built on the principle that:
- Claude Code CLI is a legitimate development tool
- Users understand they're granting file system access to an AI
- Clear prompts effectively guide AI behavior
- The benefits of uninterrupted operation outweigh technical restrictions

### Defense in Depth
While relying on prompt-based security, consider additional layers:
- **Environment isolation**: Use VMs or containers
- **File system permissions**: Set appropriate user permissions
- **Network restrictions**: Limit outbound network access
- **Regular monitoring**: Watch for unexpected behavior

### Incident Response
If something goes wrong:
1. **Stop the server**: Kill the process immediately
2. **Review logs**: Check what operations were performed
3. **Assess damage**: Determine what files were affected
4. **Restore from backup**: Use your backup strategy
5. **Update prompts**: Refine security guidance if needed

## Migration from Permission-Based Systems

If migrating from systems with technical permission controls:

1. **Review current restrictions**: Understand what was previously blocked
2. **Update documentation**: Ensure users understand the new trust model  
3. **Test in safe environments**: Verify the system works as expected
4. **Train users**: Educate on the prompt-based security approach
5. **Monitor closely**: Watch activity during the transition period

## Monitoring and Logging

### What to Monitor
- File operations outside project directories
- Unusual command execution patterns
- Failed operations or errors
- Network activity from Claude CLI
- Resource usage patterns

### Log Analysis
Look for patterns like:
- Operations outside expected project boundaries
- Repeated failed operations
- Unusual file access patterns
- Commands not typical for development work

## Support and Troubleshooting

### Common Issues
1. **Claude not respecting boundaries**: Review and strengthen prompt language
2. **Unexpected file modifications**: Check that project paths are correctly identified
3. **User confusion**: Ensure users understand the trust-based model

### Getting Help
1. Check server logs for operation details
2. Review the prompt templates for clarity
3. Verify project path detection is working correctly
4. Ensure users understand they have full system access

## Conclusion

This prompt-based security model prioritizes reliability and user experience while maintaining appropriate boundaries through clear communication with Claude. It's designed for environments where users understand and accept the trade-offs of granting full system access to an AI assistant in exchange for better performance and reliability.

The key to success with this model is user education, appropriate environment isolation, and clear prompt design that effectively communicates security expectations to Claude.