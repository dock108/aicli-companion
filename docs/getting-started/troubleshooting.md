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

**Last Updated**: 2025-07-27# Claude Companion Server - Troubleshooting Guide

## Overview

This guide helps diagnose and resolve common issues with Claude Companion Server. Issues are organized by category with symptoms, causes, and solutions.

## Quick Diagnostics

### Health Check
```bash
# Check if server is running
curl http://localhost:3001/health

# Expected response:
{
  "status": "healthy",
  "version": "1.0.0",
  "claudeCodeAvailable": true,
  "timestamp": "2024-01-03T10:00:00.000Z"
}
```

### Check Logs
```bash
# PM2 logs
pm2 logs claude-companion-server --lines 100

# System logs
tail -f logs/combined.log

# Error logs only
tail -f logs/err.log
```

### Telemetry Check
```bash
# Get current metrics
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/api/telemetry
```

## Common Issues

### 1. Connection Issues

#### WebSocket Connection Fails

**Symptoms:**
- Client receives "WebSocket connection failed" error
- Connection immediately closes after opening
- "403 Forbidden" or "401 Unauthorized" errors

**Causes & Solutions:**

1. **Authentication Token Mismatch**
   ```bash
   # Verify token in environment
   echo $AUTH_TOKEN
   
   # Check client is sending token
   ws://localhost:3001/ws?token=YOUR_TOKEN
   ```

2. **Reverse Proxy Misconfiguration**
   ```nginx
   # Ensure these headers are set
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   ```

3. **Firewall Blocking WebSocket**
   ```bash
   # Check if port is open
   sudo netstat -tlnp | grep 3001
   
   # Test WebSocket directly
   wscat -c ws://localhost:3001/ws?token=YOUR_TOKEN
   ```

#### WebSocket Keeps Disconnecting

**Symptoms:**
- Connections drop after ~60 seconds
- "Connection reset by peer" errors
- Frequent reconnection attempts

**Solutions:**

1. **Increase nginx Timeouts**
   ```nginx
   location /ws {
     proxy_read_timeout 86400;
     proxy_send_timeout 86400;
     proxy_connect_timeout 86400;
   }
   ```

2. **Enable Keep-Alive**
   ```javascript
   // Server should send periodic pings
   // Check WS_HEARTBEAT_INTERVAL is set
   ```

3. **Check Client Implementation**
   ```javascript
   // Client should respond to pings
   ws.on('ping', () => ws.pong());
   ```

### 2. Session Management Issues

#### Duplicate Sessions Created

**Symptoms:**
- Multiple sessions for same project directory
- Lost conversation context
- Parallel Claude processes

**Diagnosis:**
```bash
# Check active sessions
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/api/sessions

# Look for duplicate workingDirectory values
```

**Solutions:**

1. **Verify Session Deduplication**
   ```bash
   # Check logs for session reuse
   grep "Reusing existing session" logs/combined.log
   ```

2. **Clear Stale Sessions**
   ```javascript
   // Manually expire sessions if needed
   // Sessions should auto-expire after SESSION_TIMEOUT
   ```

#### Session Not Found Errors

**Symptoms:**
- "Invalid session" errors
- Commands fail with "session expired"
- iOS app can't reconnect to session

**Solutions:**

1. **Check Session Persistence**
   ```bash
   # Verify session exists
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:3001/api/sessions/SESSION_ID
   ```

2. **Use Session Continuation Endpoint**
   ```bash
   # For iOS reconnection
   curl -X POST -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"sessionId":"SESSION_ID","workingDirectory":"/path"}' \
     http://localhost:3001/api/sessions/continue
   ```

### 3. Message Delivery Issues

#### Empty or Blank Messages

**Symptoms:**
- UI shows empty message bubbles
- streamData events with no content
- Missing Claude responses

**Diagnosis:**
```bash
# Check message filtering
grep "Filtering empty stream chunk" logs/combined.log

# Check telemetry for filtered messages
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3001/api/telemetry | jq '.messages.filtered'
```

**Solutions:**

1. **Verify Stream Chunk Validation**
   ```javascript
   // Chunks should have content
   if (chunk.type === 'content' && !chunk.data?.content?.trim()) {
     // This will be filtered
   }
   ```

2. **Check Message Queue**
   ```bash
   # Look for queue delivery issues
   grep "Delivering queued messages" logs/combined.log
   ```

#### Messages Not Delivered from Queue

**Symptoms:**
- Messages lost during disconnection
- Queued messages never arrive
- Out-of-order message delivery

**Solutions:**

1. **Check Queue Size Limits**
   ```bash
   # Verify MESSAGE_QUEUE_MAX_SIZE
   echo $MESSAGE_QUEUE_MAX_SIZE
   
   # Check if queue is full
   grep "Queue full" logs/err.log
   ```

2. **Verify Client Subscription**
   ```javascript
   // Client must subscribe after connection
   {
     "type": "subscribe",
     "data": {
       "events": ["assistantMessage", "streamData"]
     }
   }
   ```

### 4. Claude CLI Issues

#### Claude Command Not Found

**Symptoms:**
- "Claude executable not found" errors
- Health check shows `claudeCodeAvailable: false`

**Solutions:**

1. **Verify Claude Installation**
   ```bash
   # Check if Claude is installed
   which claude
   
   # Test Claude directly
   claude --version
   ```

2. **Set Correct Path**
   ```bash
   # Update environment variable
   export CLAUDE_EXECUTABLE_PATH=/usr/local/bin/claude
   
   # Or update .env file
   CLAUDE_EXECUTABLE_PATH=/usr/local/bin/claude
   ```

#### Claude Process Hangs

**Symptoms:**
- Commands never complete
- No response from Claude
- Server becomes unresponsive

**Solutions:**

1. **Check Claude Process**
   ```bash
   # Find hanging Claude processes
   ps aux | grep claude
   
   # Kill if necessary
   pkill -f "claude chat"
   ```

2. **Enable Process Timeout**
   ```javascript
   // Check if CLAUDE_PROCESS_TIMEOUT is set
   // Default should be reasonable (e.g., 5 minutes)
   ```

### 5. Push Notification Issues

#### Notifications Not Sent

**Symptoms:**
- No push notifications received
- "Push notifications not configured" in logs

**Diagnosis:**
```bash
# Check push notification stats
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3001/api/push-notifications/stats
```

**Solutions:**

1. **Verify APNS Configuration**
   ```bash
   # Check certificate paths
   ls -la $APNS_CERT_PATH $APNS_KEY_PATH
   
   # Verify certificate validity
   openssl x509 -in $APNS_CERT_PATH -text -noout | grep "Not After"
   ```

2. **Check Device Registration**
   ```bash
   # Look for device registration
   grep "Registered device token" logs/combined.log
   ```

3. **Test Push Notifications**
   ```bash
   curl -X POST -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"clientId":"CLIENT_ID","message":"Test"}' \
     http://localhost:3001/api/push-notifications/test
   ```

#### Bad Device Token Errors

**Symptoms:**
- "BadDeviceToken" errors in logs
- Notifications stop working for specific devices

**Solutions:**

1. **Clear Bad Tokens**
   ```bash
   curl -X DELETE -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:3001/api/push-notifications/bad-tokens
   ```

2. **Re-register Device**
   ```javascript
   // Client should re-register token
   {
     "type": "registerDevice",
     "data": {
       "deviceToken": "new-token-here"
     }
   }
   ```

### 6. Performance Issues

#### High Memory Usage

**Symptoms:**
- Server using excessive RAM
- "JavaScript heap out of memory" errors
- Slow response times

**Diagnosis:**
```bash
# Check memory usage
pm2 describe claude-companion-server | grep memory

# Monitor over time
pm2 monit
```

**Solutions:**

1. **Increase Memory Limit**
   ```javascript
   // In ecosystem.config.js
   node_args: '--max-old-space-size=2048'
   ```

2. **Check for Memory Leaks**
   ```bash
   # Look for retained sessions
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:3001/api/sessions | jq '.sessions | length'
   ```

3. **Enable Session Cleanup**
   ```bash
   # Verify cleanup is running
   grep "Session cleanup completed" logs/combined.log
   ```

#### Slow Response Times

**Symptoms:**
- Commands take long to execute
- WebSocket messages delayed
- Timeouts on API calls

**Solutions:**

1. **Check System Resources**
   ```bash
   # CPU usage
   top -p $(pgrep -f claude-companion)
   
   # Disk I/O
   iotop -p $(pgrep -f claude-companion)
   ```

2. **Review Telemetry Metrics**
   ```bash
   # Check processing times
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:3001/api/telemetry | \
     jq '.performance.avgMessageProcessingTime'
   ```

### 7. Deployment Issues

#### Server Won't Start

**Symptoms:**
- PM2 shows "errored" status
- "EADDRINUSE" errors
- Missing dependencies

**Solutions:**

1. **Check Port Availability**
   ```bash
   # See what's using the port
   sudo lsof -i :3001
   
   # Kill if needed
   sudo kill -9 PID
   ```

2. **Verify Dependencies**
   ```bash
   # Reinstall dependencies
   npm ci --production
   
   # Check for missing modules
   npm ls
   ```

3. **Check Permissions**
   ```bash
   # Verify file permissions
   ls -la /path/to/server
   
   # Fix if needed
   sudo chown -R claude-companion:claude-companion .
   ```

## Debug Mode

### Enable Verbose Logging

```bash
# Set debug environment variable
DEBUG=* pm2 restart claude-companion-server

# Or update in ecosystem.config.js
env: {
  DEBUG: 'claude-companion:*',
  LOG_LEVEL: 'debug'
}
```

### Capture Debug Information

```bash
#!/bin/bash
# debug-capture.sh

# Create debug directory
mkdir -p debug-$(date +%Y%m%d_%H%M%S)
cd debug-*

# Capture system info
echo "=== System Info ===" > system.txt
uname -a >> system.txt
node --version >> system.txt
npm --version >> system.txt

# Capture process info
echo "=== Process Info ===" > process.txt
pm2 describe claude-companion-server >> process.txt
ps aux | grep claude >> process.txt

# Capture recent logs
pm2 logs claude-companion-server --nostream --lines 1000 > logs.txt

# Capture configuration (sanitized)
echo "=== Configuration ===" > config.txt
env | grep -E '^(NODE_|CLAUDE_|WS_|SESSION_)' | \
  sed 's/TOKEN=.*/TOKEN=REDACTED/' >> config.txt

# Capture network info
echo "=== Network Info ===" > network.txt
netstat -tlnp 2>/dev/null | grep -E '(3001|claude)' >> network.txt
ss -s >> network.txt

# Create archive
cd ..
tar -czf debug-archive.tar.gz debug-*/
```

## Recovery Procedures

### Emergency Restart

```bash
# Stop all Claude processes
pkill -f claude

# Stop server
pm2 stop claude-companion-server

# Clear temporary files
rm -rf /tmp/claude-*

# Restart server
pm2 start claude-companion-server

# Verify health
sleep 5
curl http://localhost:3001/health
```

### Session Recovery

```bash
# Export active sessions (if possible)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3001/api/sessions > sessions-backup.json

# After restart, sessions should auto-recover from persistence
# If not, manual session creation may be needed
```

### Clear All State

```bash
# WARNING: This will reset everything
pm2 stop claude-companion-server

# Clear message queues
redis-cli FLUSHDB  # If using Redis

# Clear session files
rm -rf sessions/

# Clear logs
rm -rf logs/*

# Restart fresh
pm2 start claude-companion-server
```

## Getting Help

### Information to Provide

When reporting issues, include:

1. **Server version**
   ```bash
   npm list claude-companion-server
   ```

2. **Environment info**
   ```bash
   node --version
   npm --version
   pm2 --version
   ```

3. **Recent logs**
   ```bash
   pm2 logs claude-companion-server --lines 100
   ```

4. **Telemetry snapshot**
   ```bash
   curl -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:3001/api/telemetry
   ```

5. **Steps to reproduce the issue**

### Support Channels

1. GitHub Issues: https://github.com/yourcompany/claude-companion-server/issues
2. Discord: https://discord.gg/claudecompanion
3. Email: support@claudecompanion.com

## Prevention Tips

1. **Monitor Regularly**
   - Set up automated health checks
   - Review logs daily
   - Track telemetry trends

2. **Update Carefully**
   - Test updates in staging first
   - Keep backups before updates
   - Read changelog for breaking changes

3. **Capacity Planning**
   - Monitor resource usage trends
   - Scale before hitting limits
   - Plan for peak usage

4. **Security**
   - Rotate auth tokens regularly
   - Keep dependencies updated
   - Monitor for suspicious activity