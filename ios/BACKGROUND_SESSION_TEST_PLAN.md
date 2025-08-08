# Background Session Management Test Plan

## Test Scenarios

### 1. User Sends Message and Leaves Before Response
**Steps:**
1. Open a project without existing session
2. Send a message to Claude
3. Immediately navigate away (back to project list)
4. Wait for Claude's response to arrive
5. Re-open the same project

**Expected Result:**
- Messages should be persisted with the session ID from Claude's response
- Both user and assistant messages should be visible when re-opening project
- No data loss should occur

### 2. Multiple Projects with Pending Messages
**Steps:**
1. Open Project A, send message, leave immediately
2. Open Project B, send message, leave immediately  
3. Wait for both responses to arrive
4. Check both projects

**Expected Result:**
- Each project should have its own messages correctly persisted
- No cross-contamination between projects

### 3. App Backgrounding During Message Send
**Steps:**
1. Send a message in a project
2. Background the app before response arrives
3. Wait for response
4. Foreground the app and check messages

**Expected Result:**
- Messages should be persisted correctly
- Session ID should be captured even while app was backgrounded

### 4. Error Handling
**Steps:**
1. Send message and leave before response
2. Simulate network error or timeout
3. Re-open project

**Expected Result:**
- User message should still be visible
- Error state should be handled gracefully
- No crash or data corruption

### 5. Session Restoration After App Restart
**Steps:**
1. Create sessions in multiple projects
2. Force quit the app
3. Restart and check each project

**Expected Result:**
- All sessions should be restored with correct messages
- Session IDs should be preserved
- Message order should be maintained

## Verification Points

- Check `BackgroundSessionCoordinator` logs for pending message storage
- Verify WebSocket global handlers are receiving messages
- Confirm session IDs are extracted from Claude responses
- Validate MessagePersistenceService saves with correct session IDs
- Ensure no memory leaks with background operations