# Desktop App Button Fixes

## Issues Fixed

### 1. Parameter Naming Inconsistency ✅
**Problem**: JavaScript was using `forceExternal` but Rust expected `force_external`

**Files Changed**:
- `/src/app.js` lines 163, 181

**Changes**:
```javascript
// Before:
await invoke('stop_server', { forceExternal: false });
await invoke('stop_server', { forceExternal: true });

// After:
await invoke('stop_server', { force_external: false });
await invoke('stop_server', { force_external: true });
```

### 2. Server Directory Path Calculation ✅
**Problem**: Path resolution failed in development mode when trying to find the server directory

**Files Changed**:
- `/src-tauri/src/main.rs` lines 118-152

**Changes**:
- Replaced brittle relative path navigation with robust server directory search
- Development mode now searches upward from current directory to find `server/src/index.js`
- Production mode uses executable directory structure
- Added proper error handling and path canonicalization

## Issues Still To Test

### 3. Browse Button Functionality ⏳
**Status**: Needs testing with Rust/Cargo installed

**Expected Behavior**:
- Should open native file dialog
- Should allow directory selection
- Should update config path input

**Potential Issues**:
- Tauri permissions might need adjustment
- Dialog plugin might need additional setup

### 4. Start Server Functionality ⏳
**Status**: Should work with path fixes, needs testing

**Expected Behavior**:
- Should find server directory correctly
- Should start Node.js server process
- Should not crash with "directory not found" error

## Testing Requirements

To fully test these fixes, you need:

1. **Install Rust**: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
2. **Run desktop app**: `npm run tauri dev`
3. **Test all buttons**:
   - Browse: Should open file dialog
   - Start Server: Should start server without crashing
   - Stop Server: Should work for both managed and external servers

## Status Summary

- ✅ Parameter naming fixed
- ✅ Server path resolution improved
- ⏳ Browse button needs testing (likely works now)
- ⏳ Full integration testing pending Rust installation# AICLI Companion Host App - Testing Guide

## Overview

The AICLI Companion Host App has comprehensive test coverage for both JavaScript/TypeScript frontend code and Rust backend code.

## JavaScript Testing

### Test Framework
- **Vitest** - Fast, ESM-first test runner
- **Happy-DOM** - Lightweight DOM implementation for testing
- **Coverage**: v8 provider with 80%+ threshold

### Running JavaScript Tests

```bash
# Run tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm run test:coverage

# Run tests with UI
npm run test:ui
```

### Test Structure

```
test/
├── app-core.test.js    # Core application logic tests
├── setup.js            # Test environment setup
└── mocks/              # Module mocks
    ├── tauri-api-core.js
    ├── tauri-plugin-dialog.js
    ├── tauri-api-path.js
    └── qrcode.js
```

### Coverage Requirements
- **Overall**: 80%+ (currently 83.33%)
- **Statements**: 80%+
- **Branches**: 80%+
- **Functions**: 80%+
- **Lines**: 80%+

### Key Test Areas
1. **Config Management** - Loading/saving user preferences
2. **Server Management** - Starting/stopping server processes
3. **UI Updates** - DOM manipulation and state management
4. **Path Selection** - File dialog interactions
5. **QR Code Generation** - Connection string generation
6. **Health Monitoring** - Server health check polling

## Rust Testing

### Test Framework
- Built-in Rust testing framework
- **mockall** - Mocking framework
- **tokio-test** - Async test utilities
- **wiremock** - HTTP mocking

### Running Rust Tests

```bash
cd src-tauri
cargo test
```

### Test Structure

All tests are included in `src/lib.rs` using the `#[cfg(test)]` module pattern.

### Key Test Areas
1. **Network Operations** - IP address detection
2. **Server Status** - State management and serialization
3. **Process Management** - Finding and managing processes
4. **Health Checks** - Server health monitoring
5. **API Commands** - Tauri command handlers

## Pre-commit Hooks

Both JavaScript and Rust tests are run automatically before commits:

```bash
# JavaScript tests with coverage enforcement
cd server/hostapp && npm run test:coverage

# Rust tests (requires cargo)
cd src-tauri && cargo test
```

## Mocking Strategy

### JavaScript Mocks
- Tauri APIs are mocked to simulate desktop environment
- DOM elements are mocked for UI testing
- External libraries (QRCode) are mocked

### Rust Mocks
- External commands (lsof, kill, etc.) are tested with real commands
- HTTP requests use wiremock for deterministic testing
- Process management uses test utilities

## CI/CD Integration

Tests are run in GitHub Actions:
- JavaScript tests run on every push/PR
- Rust tests run when Rust toolchain is available
- Coverage reports are generated and can be uploaded to coverage services

## Debugging Tests

### JavaScript
```bash
# Run specific test file
npm test test/app-core.test.js

# Run tests matching pattern
npm test -- -t "Config Management"
```

### Rust
```bash
# Run specific test
cargo test test_get_local_ip

# Run with output
cargo test -- --nocapture
```

## Writing New Tests

### JavaScript Test Template
```javascript
describe('Feature Name', () => {
  beforeEach(() => {
    // Setup
  });

  it('should do something', async () => {
    // Arrange
    const expected = 'value';
    
    // Act
    const result = await myFunction();
    
    // Assert
    expect(result).toBe(expected);
  });
});
```

### Rust Test Template
```rust
#[test]
fn test_feature() {
    // Arrange
    let input = "test";
    
    // Act
    let result = my_function(input);
    
    // Assert
    assert_eq!(result, expected);
}

#[tokio::test]
async fn test_async_feature() {
    // Async test implementation
}
```