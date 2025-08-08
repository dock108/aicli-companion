# Troubleshooting Guide

Common issues and solutions for Claude Companion.

## Connection Issues

### Server Not Found in Auto-Discovery

**Symptoms**: Server doesn't appear in iOS app discovery list

**Solutions**:
1. Ensure both devices are on the same network
2. Check firewall settings - allow Node.js incoming connections
3. Verify Bonjour is enabled:
   ```bash
   ENABLE_BONJOUR=true npm start
   ```
4. Try manual connection with IP address and port

### Authentication Failed

**Symptoms**: "Invalid token" or connection refused

**Solutions**:
1. Verify token matches between server and app
2. Check token in `.env` file or server output
3. Ensure no extra spaces in token field
4. Generate new token if needed:
   ```bash
   claude-companion-server --generate-token
   ```

### Connection Timeouts

**Symptoms**: Connection attempts time out

**Solutions**:
1. Check server is running: `curl http://localhost:3001/health`
2. Verify correct port in app settings
3. Test with local IP instead of localhost
4. Disable VPN if active

## Claude CLI Issues

### Claude Code CLI Not Found

**Symptoms**: "Claude Code CLI not found" error

**Solutions**:
1. Install Claude CLI:
   ```bash
   npm install -g @anthropic/claude-code
   ```
2. Verify installation:
   ```bash
   claude --version
   ```
3. Set custom path if needed:
   ```bash
   CLAUDE_CLI_PATH=/usr/local/bin/claude npm start
   ```

### Permission Denied Errors

**Symptoms**: Claude can't access files or execute commands

**Solutions**:
1. Check file permissions in working directory
2. Configure allowed tools in `.env`:
   ```env
   CLAUDE_ALLOWED_TOOLS=Read,Write,Edit,Bash
   ```
3. For trusted environments only:
   ```env
   CLAUDE_SKIP_PERMISSIONS=true
   ```

### High Memory Usage

**Symptoms**: Server consuming excessive memory

**Solutions**:
1. Monitor active sessions: `GET /api/sessions`
2. Close unused sessions from the app
3. Restart server to clear all sessions
4. Check for memory leaks in custom integrations

## iOS App Issues

### App Crashes on Launch

**Solutions**:
1. Delete and reinstall the app
2. Clear app data: Settings → Claude Companion → Clear Data
3. Update to latest version
4. Check iOS compatibility (requires iOS 15+)

### Messages Not Sending

**Symptoms**: Messages stay in "Sending..." state

**Solutions**:
1. Check connection status indicator
2. Pull down to refresh connection
3. Force quit and restart app
4. Check server logs for errors

### UI Not Updating After Build

**Solutions**:
1. Clean Xcode build folder: `Shift+Cmd+K`
2. Delete derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeCompanion*
   ```
3. Reset package cache:
   ```bash
   cd ios && rm -rf .build build
   ```
4. Delete app from simulator and reinstall

## Desktop Host App Issues

### Browse Button Not Working

**Symptoms**: File dialog doesn't open

**Solutions**:
1. Ensure Rust is installed properly
2. Grant file access permissions to the app
3. Check Tauri dialog plugin is included
4. Run in dev mode to see console errors:
   ```bash
   npm run tauri dev
   ```

### Server Path Not Found

**Symptoms**: "Server directory not found" error

**Solutions**:
1. The issue has been fixed in latest version
2. Ensure you're in the correct directory
3. For development, run from project root
4. Check `src/index.js` exists in server directory

### Parameter Mismatch Errors

**Symptoms**: JavaScript/Rust communication errors

**Fixed**: Parameter names now use snake_case consistently:
- `force_external` instead of `forceExternal`

## Build Issues

### iOS Build Failures

**Solutions**:
1. Update Xcode to version 15+
2. Resolve Swift package dependencies:
   ```bash
   swift package resolve
   ```
3. Select valid development team
4. Check provisioning profiles

### Tauri Build Failures

**Solutions**:
1. Install Rust toolchain:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```
2. Update dependencies:
   ```bash
   cargo update
   ```
3. Clear target directory:
   ```bash
   rm -rf src-tauri/target
   ```

## Performance Issues

### Slow Response Times

**Solutions**:
1. Check Claude CLI isn't rate limited
2. Monitor server resource usage
3. Reduce concurrent sessions
4. Enable response streaming
5. Check network latency

### App Freezing

**Solutions**:
1. Limit conversation history display
2. Clear old conversations
3. Disable animations in iOS settings
4. Update to latest app version

## Security Issues

### Vulnerability Warnings

**Current Known Issues**:
- `glib` vulnerability - Update with:
  ```bash
  cd server/hostapp/src-tauri && cargo update -p glib
  ```

**General Security**:
1. Keep all dependencies updated
2. Use strong authentication tokens
3. Enable TLS for production
4. Restrict CORS origins

## Getting More Help

### Debugging Steps

1. **Check Logs**:
   - Server logs: Terminal output or log files
   - iOS logs: Xcode console
   - Desktop app: Developer tools console

2. **Enable Debug Mode**:
   ```bash
   DEBUG=* npm start
   ```

3. **Capture Network Traffic**:
   - Use Chrome DevTools for WebSocket inspection
   - Check iOS app network logs

### Reporting Issues

When reporting issues, include:
- Error messages and stack traces
- Steps to reproduce
- Environment details (OS, versions)
- Relevant log excerpts
- Screenshots if UI-related

### Community Support

- GitHub Issues: Bug reports and feature requests
- Discussions: General questions and help
- Stack Overflow: Tag with `claude-companion`

---

**Last Updated**: 2025-07-27