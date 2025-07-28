# Session Persistence Test Plan

## Test Scenarios

### 1. Basic Session Persistence
1. Launch the iOS app
2. Connect to server and select a project
3. Send a few messages to AICLI
4. Wait for auto-save (30 seconds) or close the app
5. Relaunch the app
6. Select the same project
7. **Expected**: Session continuation dialog should appear showing message count and last activity

### 2. Continue vs Start Fresh
1. Follow steps 1-6 from Basic Session Persistence
2. When continuation dialog appears:
   - Test "Continue Conversation" button
     - **Expected**: Previous messages restored with restoration notice
   - Test "Start Fresh" button
     - **Expected**: New session starts, old messages archived

### 3. App Background/Foreground
1. Start a conversation in a project
2. Send message to AICLI
3. While AICLI is responding, lock device or switch apps
4. Return to app
5. **Expected**: WebSocket reconnects, conversation continues without errors

### 4. Session Indicators
1. Have active sessions in multiple projects
2. Go to project selection screen
3. **Expected**: Projects with sessions show:
   - Green dot indicator
   - "• Active" status
   - Message count and last activity time
   - Green border on project card

### 5. Auto-Save Verification
1. Start a conversation
2. Send messages back and forth
3. Check iOS app documents directory after 30 seconds
4. **Expected**: Messages saved in JSON format under AICLICompanionSessions/[project_id]/

### 6. Server Session Continuation
1. Start a session in a project
2. Note the session ID
3. Close and reopen app
4. Continue the session
5. Check server logs
6. **Expected**: Server recognizes continuation request with existing session ID

## Implementation Details Added

### iOS Components
- **WebSocketService**: Added app lifecycle observers for background/foreground handling
- **MessagePersistenceService**: Local storage for messages and session metadata
- **SessionContinuationSheet**: UI for choosing to continue or start fresh
- **ProjectSelectionView**: Shows session indicators and handles continuation flow
- **ChatView**: Auto-saves messages every 30 seconds and on view disappear

### Server Components
- **projects.js**: Enhanced `/api/projects/:name/start` endpoint to accept continuation parameters

## Known Limitations
- Session context in AICLI CLI itself may not persist between app restarts
- Only local message history is preserved, not AICLI's internal context
- Messages are stored per device, not synced across devices