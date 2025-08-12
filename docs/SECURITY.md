# Security Configuration Guide

## Overview

Claude Companion provides comprehensive security controls to manage what commands Claude can execute and which directories it can access. This guide explains how to configure and use these security features.

## Quick Start

### Default Security

By default, Claude Companion runs with the **Standard** security preset, which:
- Blocks obviously dangerous commands (rm -rf /, format, etc.)
- Requires confirmation for destructive operations
- Enables audit logging
- Allows operations in all directories (until you configure safe directories)

### Setting Safe Directories

To restrict Claude to specific directories, set the `AICLI_SAFE_DIRECTORIES` environment variable:

```bash
# In server/.env
AICLI_SAFE_DIRECTORIES=/Users/username/projects,/Users/username/documents,/tmp
```

### Choosing a Security Preset

Three presets are available:

1. **Unrestricted** - No restrictions (use with caution)
2. **Standard** - Balanced security (default)
3. **Restricted** - Read-only mode with minimal permissions

Set via environment variable:
```bash
AICLI_SECURITY_PRESET=standard
```

## Security Features

### 1. Command Filtering

Block specific commands or patterns:

```bash
# Block individual commands
AICLI_BLOCKED_COMMANDS=rm -rf,format,diskutil erase

# Block all commands (restricted mode)
AICLI_BLOCKED_COMMANDS=*
```

### 2. Directory Access Control

Limit Claude to specific directories:

```bash
# Only allow operations in these directories
AICLI_SAFE_DIRECTORIES=/Users/me/projects,/tmp

# Claude will be blocked from:
# - System directories (/etc, /usr, /bin)
# - Home directory (except allowed paths)
# - Root directory operations
```

### 3. Destructive Command Protection

Require confirmation for potentially destructive commands:

```bash
AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION=true
AICLI_DESTRUCTIVE_COMMANDS=rm -rf,mv,dd,format
```

### 4. Read-Only Mode

Prevent all write operations:

```bash
AICLI_READONLY_MODE=true
```

### 5. File Size Limits

Limit the size of files Claude can create/modify:

```bash
# 10MB limit (in bytes)
AICLI_MAX_FILE_SIZE=10485760
```

### 6. Audit Logging

Track all security validations:

```bash
AICLI_ENABLE_AUDIT=true
```

View audit logs via API:
```bash
curl http://localhost:3001/api/security/audit
```

## Configuration Methods

### Method 1: Environment Variables (Server)

Edit `server/.env`:

```env
# Security Configuration
AICLI_SECURITY_PRESET=standard
AICLI_SAFE_DIRECTORIES=/Users/me/projects,/Users/me/documents
AICLI_BLOCKED_COMMANDS=rm -rf /,format
AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION=true
AICLI_MAX_FILE_SIZE=10485760
AICLI_READONLY_MODE=false
AICLI_ENABLE_AUDIT=true
```

### Method 2: iOS App

1. Open Settings in the Claude Companion iOS app
2. Navigate to Security section
3. Choose a security preset or customize:
   - Toggle command filtering
   - Add/remove safe directories
   - Configure blocked commands
   - Enable read-only mode

### Method 3: macOS Host App

1. Open Claude Companion Host preferences
2. Go to Security tab
3. Configure:
   - Security preset
   - Safe directories
   - Blocked command patterns
   - Advanced options

### Method 4: API Configuration

Update settings programmatically:

```bash
# Update security configuration
curl -X PUT http://localhost:3001/api/security/settings \
  -H "Content-Type: application/json" \
  -d '{
    "preset": "standard",
    "safeDirectories": ["/Users/me/projects"],
    "blockedCommands": ["rm -rf", "format"],
    "readOnlyMode": false
  }'

# Test a command
curl -X POST http://localhost:3001/api/security/test \
  -H "Content-Type: application/json" \
  -d '{
    "command": "rm -rf /",
    "workingDirectory": "/tmp"
  }'
```

## Security API Endpoints

### GET /api/security/settings
Get current security configuration

### PUT /api/security/settings
Update security configuration

### GET /api/security/audit
View security audit log

### POST /api/security/test
Test if a command would be allowed

### GET /api/security/presets
View available security presets

### GET /api/security/permissions
View pending permission requests

### POST /api/security/permissions/:id/approve
Approve a permission request

### POST /api/security/permissions/:id/deny
Deny a permission request

## Security Presets

### Unrestricted
```json
{
  "blockedCommands": [],
  "requireConfirmation": false,
  "readOnlyMode": false
}
```
**Use Case**: Development environments where you trust Claude completely

### Standard (Default)
```json
{
  "blockedCommands": [
    "rm -rf /",
    "rm -rf /*",
    "format",
    "diskutil eraseDisk",
    "dd if=/dev/zero of=/dev/",
    "mkfs",
    ":(){ :|:& };:"
  ],
  "requireConfirmation": true,
  "readOnlyMode": false
}
```
**Use Case**: Normal development work with safety guardrails

### Restricted
```json
{
  "blockedCommands": ["*"],
  "requireConfirmation": true,
  "readOnlyMode": true
}
```
**Use Case**: Code review, analysis, or untrusted environments

## Advanced Features

### Permission Requests

When destructive commands require confirmation:

1. Claude requests permission via the server
2. Server sends push notification to iOS/macOS apps
3. User approves/denies in the app
4. Command proceeds or is blocked based on response

### Activity Monitoring

Track all Claude operations:

- Command executions (allowed/blocked)
- File operations
- Security violations
- Error patterns
- Suspicious activity alerts

### Emergency Stop

Immediately halt all Claude operations:

1. iOS App: Settings → Security → Emergency Stop
2. macOS App: Menu Bar → Stop All Operations
3. API: `POST /api/security/emergency-stop`

## Best Practices

### For Development

```env
AICLI_SECURITY_PRESET=standard
AICLI_SAFE_DIRECTORIES=~/projects,~/documents,/tmp
AICLI_ENABLE_AUDIT=true
```

### For Production/Shared Environments

```env
AICLI_SECURITY_PRESET=restricted
AICLI_SAFE_DIRECTORIES=/specific/project/path
AICLI_READONLY_MODE=true
AICLI_ENABLE_AUDIT=true
```

### For Code Review

```env
AICLI_SECURITY_PRESET=restricted
AICLI_READONLY_MODE=true
AICLI_ALLOWED_TOOLS=Read,Grep,List
```

## Troubleshooting

### Commands Being Blocked

1. Check audit log: `GET /api/security/audit`
2. Test command: `POST /api/security/test`
3. Review blocked patterns in configuration
4. Ensure working directory is in safe directories list

### Permission Requests Not Arriving

1. Verify push notifications are configured
2. Check iOS/macOS app is connected
3. Review server logs for errors
4. Ensure `AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION=true`

### Security Settings Not Applied

1. Restart server after configuration changes
2. Verify environment variables are set correctly
3. Check for typos in configuration
4. Review server startup logs

## Security Considerations

### What This Protects Against

- Accidental deletion of important files
- Unauthorized access to system directories
- Execution of malicious commands
- Unintended modifications outside project scope
- Resource exhaustion from large file operations

### What This Doesn't Protect Against

- Malicious code within allowed directories
- Logic bugs in allowed operations
- Network-based attacks
- Supply chain attacks in dependencies
- Side-channel attacks

### Recommendations

1. Always use safe directories in production
2. Enable audit logging for compliance
3. Regularly review audit logs for suspicious patterns
4. Use restricted mode for untrusted contexts
5. Keep blocked command list updated
6. Test security configuration regularly
7. Monitor activity for anomalies
8. Have an incident response plan

## Examples

### Secure Development Setup

```env
# Balanced security for daily development
AICLI_SECURITY_PRESET=standard
AICLI_SAFE_DIRECTORIES=~/projects,~/documents
AICLI_BLOCKED_COMMANDS=rm -rf /,format,:(){ :|:& };:
AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION=true
AICLI_MAX_FILE_SIZE=52428800  # 50MB
AICLI_ENABLE_AUDIT=true
```

### High Security Setup

```env
# Maximum security for sensitive environments
AICLI_SECURITY_PRESET=restricted
AICLI_SAFE_DIRECTORIES=/var/app/current
AICLI_READONLY_MODE=true
AICLI_ALLOWED_TOOLS=Read,Grep
AICLI_ENABLE_AUDIT=true
```

### Testing Environment

```env
# Permissive setup for testing
AICLI_SECURITY_PRESET=unrestricted
AICLI_SAFE_DIRECTORIES=/tmp/test
AICLI_ENABLE_AUDIT=true
```

## Support

For security-related issues or questions:

1. Check the audit log for details
2. Review this documentation
3. Check server logs: `npm run logs`
4. Report security vulnerabilities privately
5. Open an issue for feature requests

Remember: Security is a shared responsibility. Configure appropriately for your use case and regularly review your security posture.