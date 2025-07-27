# Testing Guide

Comprehensive testing guide for Claude Companion, covering unit tests, integration tests, and user acceptance testing.

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

**Last Updated**: 2025-07-27