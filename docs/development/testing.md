# Testing Guide

Comprehensive testing guide for AICLI Companion, covering unit tests, integration tests, and user acceptance testing.

## Testing Overview

### Test Categories
1. **Unit Tests**: Individual component testing
2. **Integration Tests**: Component interaction testing
3. **E2E Tests**: Full system testing
4. **UAT Scenarios**: User acceptance testing

### Coverage Requirements
- **Target**: 80% overall coverage
- **Critical Paths**: 95% coverage
- **New Code**: 90% coverage required

## JavaScript/Node.js Testing

### Test Framework
- **Runner**: Vitest (fast, ESM-first)
- **DOM**: Happy-DOM (lightweight)
- **Mocking**: Built-in vi mocks
- **Coverage**: v8 provider

### Running Tests

```bash
# Run all tests
npm test

# Watch mode for development
npm run test:watch

# Coverage report
npm run test:coverage

# UI mode
npm run test:ui
```

### Test Structure

```javascript
// Example test file: services/claude-code.test.js
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ClaudeCodeService } from '../claude-code.js';

describe('ClaudeCodeService', () => {
  let service;
  
  beforeEach(() => {
    service = new ClaudeCodeService();
    vi.clearAllMocks();
  });
  
  describe('executeCommand', () => {
    it('should execute command successfully', async () => {
      // Arrange
      const mockSpawn = vi.fn().mockReturnValue({
        stdout: { on: vi.fn() },
        stderr: { on: vi.fn() },
        on: vi.fn((event, cb) => {
          if (event === 'close') cb(0);
        })
      });
      
      // Act
      const result = await service.executeCommand('test');
      
      // Assert
      expect(result.success).toBe(true);
      expect(mockSpawn).toHaveBeenCalledWith('claude', ['test']);
    });
  });
});
```

### Mocking Strategies

**External Dependencies**:
```javascript
// Mock Node.js modules
vi.mock('child_process', () => ({
  spawn: vi.fn()
}));

// Mock network requests
vi.mock('node-fetch', () => ({
  default: vi.fn(() => Promise.resolve({
    ok: true,
    json: () => Promise.resolve({ data: 'test' })
  }))
}));
```

**Tauri APIs** (for host app):
```javascript
// __mocks__/@tauri-apps/api/core.js
export const invoke = vi.fn();
export const listen = vi.fn();
```

## iOS/Swift Testing

### Test Framework
- **XCTest**: Built-in iOS testing
- **Quick/Nimble**: BDD-style tests (optional)
- **Snapshot Testing**: UI regression tests

### Running Tests

```bash
# Command line
cd ios
swift test

# Xcode
# Product → Test (⌘U)
```

### Test Structure

```swift
// Example test: WebSocketServiceTests.swift
import XCTest
@testable import ClaudeCompanion

class WebSocketServiceTests: XCTestCase {
    var service: WebSocketService!
    
    override func setUp() {
        super.setUp()
        service = WebSocketService()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    func testConnection() async throws {
        // Given
        let server = ServerInfo(
            host: "localhost",
            port: 3001,
            token: "test-token"
        )
        
        // When
        try await service.connect(to: server)
        
        // Then
        XCTAssertEqual(service.connectionState, .connected)
    }
    
    func testMessageParsing() throws {
        // Test WebSocket message parsing
        let json = """
        {
            "type": "welcome",
            "data": { "version": "1.0.0" }
        }
        """
        
        let message = try service.parseMessage(json)
        XCTAssertEqual(message.type, .welcome)
    }
}
```

### UI Testing

```swift
// Example UI test
class ChatUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }
    
    func testSendMessage() throws {
        // Navigate to chat
        app.buttons["Chat"].tap()
        
        // Type message
        let textField = app.textFields["MessageInput"]
        textField.tap()
        textField.typeText("Hello Claude")
        
        // Send
        app.buttons["Send"].tap()
        
        // Verify message appears
        XCTAssertTrue(app.staticTexts["Hello Claude"].exists)
    }
}
```

## Rust Testing

### Running Tests

```bash
cd server/hostapp/src-tauri
cargo test

# With output
cargo test -- --nocapture

# Specific test
cargo test test_server_management
```

### Test Structure

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;
    
    #[test]
    fn test_get_local_ip() {
        let ip = get_local_ip().unwrap();
        assert!(ip.starts_with("192.168") || ip.starts_with("10."));
    }
    
    #[tokio::test]
    async fn test_health_check() {
        let response = check_server_health("http://localhost:3001")
            .await
            .unwrap();
        assert_eq!(response.status, "healthy");
    }
}
```

## Integration Testing

### API Integration Tests

```javascript
// test/integration/api.test.js
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { app } from '../../src/app.js';

describe('API Integration', () => {
  let server;
  
  beforeAll(() => {
    server = app.listen(0); // Random port
  });
  
  afterAll(() => {
    server.close();
  });
  
  it('should handle full request cycle', async () => {
    const response = await request(server)
      .post('/api/ask')
      .set('Authorization', 'Bearer test-token')
      .send({
        prompt: 'Test prompt',
        workingDirectory: '/tmp'
      });
      
    expect(response.status).toBe(200);
    expect(response.body.success).toBe(true);
  });
});
```

### WebSocket Integration Tests

```javascript
// test/integration/websocket.test.js
import { WebSocket } from 'ws';
import { describe, it, expect } from 'vitest';

describe('WebSocket Integration', () => {
  it('should handle connection and messages', async () => {
    const ws = new WebSocket('ws://localhost:3001/ws?token=test');
    
    await new Promise((resolve) => {
      ws.on('open', resolve);
    });
    
    ws.send(JSON.stringify({
      type: 'ping',
      requestId: 'test-123'
    }));
    
    const response = await new Promise((resolve) => {
      ws.on('message', (data) => {
        resolve(JSON.parse(data));
      });
    });
    
    expect(response.type).toBe('pong');
    ws.close();
  });
});
```

## User Acceptance Testing (UAT)

### Test Environment Setup

1. **Devices Required**:
   - iPhone 12 or newer
   - iPad Air or newer
   - iOS 15.0+ installed

2. **Network Setup**:
   - Local WiFi network
   - Optional: Cellular testing
   - Network Link Conditioner

### UAT Test Scenarios

#### Scenario 1: First-Time Setup
**Objective**: New user can connect successfully

**Steps**:
1. Fresh app install
2. Launch and navigate to settings
3. Enable auto-discovery
4. Select server from list
5. Enter auth token
6. Test connection
7. Save profile

**Expected**: Connection successful, profile persists

#### Scenario 2: Basic Interaction
**Objective**: Core chat functionality works

**Steps**:
1. Open chat interface
2. Send "List files"
3. Verify response formatting
4. Send follow-up question
5. Check context maintained

**Expected**: Responses formatted correctly, context preserved

#### Scenario 3: Tool Usage
**Objective**: Tool indicators display properly

**Steps**:
1. Request file read
2. Observe tool indicator
3. Request multiple operations
4. Verify all tools shown

**Expected**: Real-time tool activity visible

#### Scenario 4: Offline Support
**Objective**: Messages queue when offline

**Steps**:
1. Disable network
2. Send 3 messages
3. Re-enable network
4. Observe queue processing

**Expected**: Messages sent in order when reconnected

#### Scenario 5: Performance Test
**Objective**: App handles large conversations

**Steps**:
1. Load 100+ message conversation
2. Scroll rapidly
3. Search within conversation
4. Monitor performance

**Expected**: Smooth scrolling, quick search

### UAT Checklist

- [ ] All scenarios pass on iPhone
- [ ] All scenarios pass on iPad  
- [ ] Tested on minimum iOS (15.0)
- [ ] Tested on latest iOS
- [ ] WiFi connection tested
- [ ] Cellular connection tested
- [ ] Poor network conditions tested
- [ ] No critical bugs found
- [ ] Performance acceptable
- [ ] Accessibility verified

## Testing Best Practices

### 1. Test Organization
- Group related tests with `describe`
- Use clear test names
- Follow AAA pattern (Arrange, Act, Assert)
- Keep tests focused and isolated

### 2. Mock Management
- Mock external dependencies
- Use test doubles appropriately
- Clear mocks between tests
- Verify mock interactions

### 3. Async Testing
- Use async/await for clarity
- Set appropriate timeouts
- Handle promise rejections
- Test both success and error paths

### 4. Coverage Guidelines
- Aim for behavior coverage, not line coverage
- Test edge cases and error conditions
- Focus on critical paths
- Don't test implementation details

### 5. Performance Testing
- Monitor test execution time
- Use performance marks
- Test with realistic data sizes
- Profile memory usage

## Continuous Integration

### GitHub Actions Workflow

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test-server:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 18
      - run: npm ci
      - run: npm test
      - run: npm run test:coverage
      
  test-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - run: cd ios && swift test
```

### Pre-commit Hooks

```bash
# .husky/pre-commit
#!/bin/sh
npm test
npm run lint
```

## Debugging Failed Tests

### JavaScript Tests
```bash
# Run single test file
npm test path/to/test.js

# Run with debugging
node --inspect-brk node_modules/.bin/vitest run
```

### iOS Tests
- Set breakpoints in test code
- Use `lldb` commands
- Check test logs in Xcode
- Use `XCTAssertEqual` for clear failures

### Common Issues
1. **Async timeouts**: Increase timeout for slow operations
2. **Mock leaks**: Ensure `vi.clearAllMocks()` in `afterEach`
3. **Race conditions**: Use proper async/await
4. **Environment differences**: Check CI vs local env

---

**Last Updated**: 2025-08-09# End-to-End Message Delivery Test Plan

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
# User Acceptance Testing (UAT) Scenarios

## Overview

This document outlines the UAT test scenarios for the Claude Code Mobile Companion App. Each scenario represents a real-world use case that should be tested manually on actual devices.

## Test Environment

- **iOS Devices**: iPhone 12 or newer, iPad Air or newer
- **iOS Versions**: iOS 15.0+
- **Server**: Running on local machine accessible via network
- **Network**: Both WiFi and Cellular connections

## UAT Test Scenarios

### Scenario 1: First-Time Setup and Connection

**Objective**: Verify new user can successfully set up and connect to companion server

**Prerequisites**:

- Fresh app installation
- Server running on local machine

**Steps**:

1. Launch the app for the first time
2. Navigate to connection settings
3. Enable auto-discovery
4. Select discovered server from list
5. Enter authentication token
6. Test connection
7. Save connection profile

**Expected Results**:

- Server appears in discovery list within 5 seconds
- Connection test succeeds
- Profile is saved and persists after app restart

**Pass Criteria**: ✅ All steps complete without errors

---

### Scenario 2: Basic Chat Interaction

**Objective**: Verify basic Claude Code interaction works correctly

**Prerequisites**:

- Connected to server
- Valid working directory set

**Steps**:

1. Open chat interface
2. Type "What files are in the current directory?"
3. Send message
4. Wait for Claude response
5. Verify file listing is displayed correctly
6. Ask follow-up question about specific file
7. Verify response maintains context

**Expected Results**:

- Messages send immediately
- Claude responses appear with proper formatting
- File listings show with syntax highlighting
- Context is maintained between messages

**Pass Criteria**: ✅ All interactions complete successfully

---

### Scenario 3: Tool Usage Visualization

**Objective**: Verify tool activity indicators work correctly

**Prerequisites**:

- Connected to server
- In a project directory

**Steps**:

1. Ask Claude to "Read the README.md file"
2. Observe tool activity indicator
3. Ask Claude to "Search for TODO comments in all JavaScript files"
4. Observe multiple tool activities
5. Ask Claude to "Run npm test"
6. Observe command execution indicator

**Expected Results**:

- Tool indicators appear immediately when tools start
- Tool names and parameters are visible
- Progress indicators animate smoothly
- Indicators disappear when tools complete

**Pass Criteria**: ✅ All tool activities display correctly

---

### Scenario 4: File Management Integration

**Objective**: Verify file browser integration works

**Prerequisites**:

- Connected to server
- In a project directory

**Steps**:

1. Tap file browser button in chat
2. Navigate through directory structure
3. Select a code file
4. Choose "Analyze this file"
5. Return to chat and see analysis
6. Select multiple files
7. Ask Claude to compare them

**Expected Results**:

- File browser opens smoothly
- Directory navigation is responsive
- File selection works correctly
- Selected files appear in chat context
- Claude analyzes selected files

**Pass Criteria**: ✅ File management features work as expected

---

### Scenario 5: Offline Queue Management

**Objective**: Verify offline functionality works correctly

**Prerequisites**:

- Connected to server initially
- Some chat history exists

**Steps**:

1. Disable network connection
2. Type new message
3. Attempt to send (should queue)
4. Type 2 more messages and queue them
5. Re-enable network
6. Observe queue processing
7. Verify all messages sent in order

**Expected Results**:

- Offline indicator appears immediately
- Messages queue with visual indication
- Queue badge shows count
- Messages send automatically on reconnection
- Order is preserved

**Pass Criteria**: ✅ Offline queue works correctly

---

### Scenario 6: Development Workflow Support

**Objective**: Verify project-aware features work

**Prerequisites**:

- Connected to server
- In a Git repository with uncommitted changes

**Steps**:

1. Open workflow panel
2. View Git status card
3. Tap "View changes"
4. Ask Claude about the changes
5. Check build system detection
6. Run suggested build command
7. View test results if available

**Expected Results**:

- Git status shows correctly
- Changes are formatted properly
- Build system is detected accurately
- Commands execute from UI
- Results display in chat

**Pass Criteria**: ✅ Workflow features integrate smoothly

---

### Scenario 7: Conversation Management

**Objective**: Verify conversation features work correctly

**Prerequisites**:

- Multiple conversations exist
- Some with significant history

**Steps**:

1. Open conversation history
2. Search for specific keyword
3. Filter by date range
4. Mark conversation as favorite
5. Export conversation as JSON
6. Share exported file
7. Delete old conversation
8. Verify it's removed

**Expected Results**:

- Search returns relevant results
- Filters work correctly
- Favorites appear at top
- Export creates valid JSON
- Share sheet appears
- Deletion is immediate

**Pass Criteria**: ✅ All management features work

---

### Scenario 8: Performance Under Load

**Objective**: Verify app performs well with large conversations

**Prerequisites**:

- Long conversation (100+ messages)
- Multiple code blocks and tool outputs

**Steps**:

1. Open long conversation
2. Scroll to bottom quickly
3. Scroll up through history
4. Tap on code blocks to expand
5. Copy large code output
6. Search within conversation
7. Monitor app responsiveness

**Expected Results**:

- Scrolling remains smooth (60 fps)
- No noticeable lag
- Memory usage stays reasonable
- Code blocks render quickly
- Search completes fast
- No crashes or freezes

**Pass Criteria**: ✅ Performance remains acceptable

---

### Scenario 9: Accessibility Testing

**Objective**: Verify app is fully accessible

**Prerequisites**:

- VoiceOver enabled
- Reduce Motion enabled
- Large text size set

**Steps**:

1. Navigate entire app with VoiceOver
2. Send and receive messages
3. Use all major features
4. Verify announcements work
5. Test with keyboard (iPad)
6. Verify color contrast
7. Test haptic feedback

**Expected Results**:

- All elements have proper labels
- Navigation is logical
- Announcements are clear
- Keyboard navigation works
- Colors meet WCAG standards
- Haptics provide feedback

**Pass Criteria**: ✅ App is fully accessible

---

### Scenario 10: Error Handling and Recovery

**Objective**: Verify app handles errors gracefully

**Prerequisites**:

- Various network conditions
- Server can be stopped/started

**Steps**:

1. Stop server while connected
2. Verify error message appears
3. Try to send message (should fail gracefully)
4. Restart server
5. Verify auto-reconnection
6. Test with invalid token
7. Test with network timeout

**Expected Results**:

- Clear error messages appear
- No crashes or data loss
- Reconnection is automatic
- Invalid token shows proper error
- Timeouts are handled gracefully
- User can always recover

**Pass Criteria**: ✅ All errors handled properly

---

## UAT Sign-off Checklist

- [ ] All scenarios tested on iPhone
- [ ] All scenarios tested on iPad
- [ ] Tested on minimum iOS version (15.0)
- [ ] Tested on latest iOS version
- [ ] Tested on WiFi connection
- [ ] Tested on cellular connection
- [ ] Tested with poor network conditions
- [ ] No critical bugs found
- [ ] Performance is acceptable
- [ ] Accessibility requirements met

## Defect Tracking

| Scenario | Issue | Severity | Status |
| -------- | ----- | -------- | ------ |
|          |       |          |        |

## Notes

- Each scenario should be tested by at least 2 different testers
- Any failures should be documented with steps to reproduce
- Screenshots/recordings should be captured for any issues
- Re-test all failed scenarios after fixes
