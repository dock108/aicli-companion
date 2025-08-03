# Claude Companion Server - Troubleshooting Guide

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