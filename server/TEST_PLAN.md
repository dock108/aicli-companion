# End-to-End Message Delivery Test Plan

## Test Scenarios

### 1. Basic Message Delivery
- [ ] Start server
- [ ] Open iOS app and connect to a project
- [ ] Send a message from iOS app
- [ ] Verify Claude responds and message appears in chat
- [ ] Check server logs for message queuing and delivery

### 2. Background Message Persistence
- [ ] Send a message from iOS app
- [ ] While Claude is responding, background the iOS app
- [ ] Wait for Claude to finish responding
- [ ] Open iOS app again
- [ ] Verify the complete response is displayed
- [ ] Check that message acknowledgment is sent

### 3. Server Restart Persistence
- [ ] Send a message and get a response
- [ ] Stop the server
- [ ] Start the server again
- [ ] Open iOS app
- [ ] Verify previous messages are loaded from persistence
- [ ] Check that acknowledgments are sent for loaded messages

### 4. Multiple Messages While Offline
- [ ] Disconnect iOS app (airplane mode or kill app)
- [ ] Send multiple messages to the session via another client
- [ ] Reconnect iOS app
- [ ] Verify all queued messages are delivered
- [ ] Check acknowledgments for each message

### 5. Clear Chat Functionality
- [ ] Have an active conversation with messages
- [ ] Clear chat in iOS app
- [ ] Verify old session is closed
- [ ] Verify new session ID is generated
- [ ] Send a new message and verify it works

### 6. Duplicate Prevention
- [ ] Send a message and receive response
- [ ] Force reconnect (kill and restart app)
- [ ] Verify no duplicate messages appear
- [ ] Check that already-received messages are not re-acknowledged

## Expected Behaviors

### Message Queue
- Messages should always be queued regardless of client connection status
- Queue should persist across server restarts
- Messages should remain in queue until acknowledged

### Acknowledgments
- iOS app should send acknowledgment when messages are displayed
- Server should track which clients have acknowledged each message
- Unacknowledged messages should be re-delivered on reconnect

### Session Management
- Sessions should persist across app backgrounding
- Clear chat should generate new session ID
- Old session should be properly closed

## Log Verification

Check for these log entries:

1. Message queuing:
   ```
   📥 Queued message msg_xxx (type: conversationResult) for persistence
   ```

2. Message delivery:
   ```
   📬 Delivering X messages to client xxx for session xxx
   ```

3. Acknowledgments:
   ```
   ✅ Acknowledged message: msg_xxx
   ```

4. Persistence:
   ```
   💾 Saved message queue for session xxx (X messages)
   ```

5. Session management:
   ```
   ✅ Chat cleared. Old session: xxx, New session: xxx
   ```