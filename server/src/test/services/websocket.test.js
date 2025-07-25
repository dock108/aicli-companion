import { describe, it } from 'node:test';
import assert from 'node:assert';
import { setupWebSocket } from '../../services/websocket.js';

// Ultra-minimal WebSocket test to avoid serialization issues
describe('WebSocket Service', () => {
  it('should setup without errors', () => {
    // Mock timers
    const originalSetInterval = global.setInterval;
    const originalClearInterval = global.clearInterval;
    global.setInterval = () => 1;
    global.clearInterval = () => {};

    try {
      // Create minimal mocks
      const wss = { on: () => {}, clients: new Set() };
      const claudeService = {
        sendPrompt: () => Promise.resolve({ response: 'test' }),
        sendStreamingPrompt: () => Promise.resolve({ sessionId: 'test' }),
        sendToExistingSession: () => Promise.resolve({ success: true }),
        closeSession: () => Promise.resolve({ success: true }),
        handlePermissionPrompt: () => Promise.resolve({ accepted: true }),
        getActiveSessions: () => [],
        healthCheck: () => Promise.resolve({ status: 'healthy' }),
        defaultWorkingDirectory: '/test',
        on: () => {},
      };
      const authToken = 'test-token';

      // Test setup
      assert.doesNotThrow(() => {
        setupWebSocket(wss, claudeService, authToken);
      });
    } finally {
      // Restore timers
      global.setInterval = originalSetInterval;
      global.clearInterval = originalClearInterval;
    }
  });

  it('should handle basic functionality', () => {
    // This test just ensures the module loads and basic setup works
    // More detailed testing is done in integration tests
    assert.ok(typeof setupWebSocket === 'function');
  });
});
