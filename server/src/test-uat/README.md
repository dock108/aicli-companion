# UAT Test Suite

This directory contains User Acceptance Testing (UAT) tests that validate the complete end-to-end functionality of the Claude Companion system.

## Test Categories

### 1. Message Flow Tests (`message-flow.test.js`)
- WebSocket connection establishment
- Message type handling (ping/pong, subscribe, etc.)
- Session management via WebSocket
- Error handling for invalid messages
- Connection stability under various conditions

### 2. Multi-Component Integration Tests (`integration.test.js`)  
- HTTP API endpoints (used by macOS app)
- WebSocket + HTTP integration
- Cross-component state synchronization
- Project management workflows
- Error recovery and resilience

### 3. Performance & Load Tests (`performance.test.js`)
- Response time benchmarks (< 100ms for health checks)
- Concurrent connection handling (20+ HTTP, 10+ WebSocket)
- Large message processing efficiency
- Memory usage monitoring
- Resource cleanup verification

### 4. Edge Cases & Error Recovery (`edge-cases.test.js`)
- Invalid input handling (malformed JSON, oversized messages)
- Resource exhaustion scenarios
- Filesystem permission issues
- Connection interruption recovery
- Data consistency under concurrent operations

## Running UAT Tests

```bash
# Run all UAT tests
npm run test:uat

# Run specific test category
npm run test:uat:message-flow
npm run test:uat:integration  
npm run test:uat:performance
npm run test:uat:edge-cases

# Run with verbose output
npm run test:uat -- --verbose
```

## Performance Benchmarks

The UAT tests establish performance baselines:

- **Health Check Response**: < 100ms
- **WebSocket Connection**: < 200ms  
- **Ping-Pong Round Trip**: < 50ms
- **Concurrent HTTP Requests**: 20+ requests in < 5s
- **Concurrent WebSocket**: 10+ connections in < 3s
- **Memory Usage**: < 10MB increase after connection cycles

## Test Environment

UAT tests create isolated test environments:
- Random ports to avoid conflicts
- Temporary directories for filesystem tests
- Disabled authentication and TLS for reliability
- Mock AICLI CLI interactions where needed

## Integration with CI/CD

These tests are designed to run in CI/CD pipelines:
- No external dependencies beyond Node.js and npm
- Self-contained with proper setup/teardown
- Clear success/failure criteria
- Performance regression detection

## Troubleshooting

**Connection Timeouts**: Check if ports are available, increase timeout values if needed.

**Permission Errors**: Ensure test runner has write access to create temporary directories.

**Memory Leaks**: Run with `--expose-gc` flag to enable garbage collection in memory tests.

**Port Conflicts**: Tests use random ports, but conflicts can occur - retry usually resolves.

## Extending Tests

When adding new UAT tests:

1. Follow the existing test structure with proper setup/teardown
2. Use descriptive test names that explain the scenario
3. Include performance assertions where relevant
4. Clean up resources (connections, files, timers) in afterEach
5. Handle both success and expected failure cases
6. Add console.log for key metrics and timing information