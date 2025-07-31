import { describe, it } from 'node:test';
import assert from 'node:assert';
import { setupWebSocket } from '../../services/websocket.js';

// Ultra-minimal WebSocket test to avoid serialization issues
describe('WebSocket Service', () => {
  it('should setup without errors', async () => {
    // Mock timers
    const originalSetInterval = global.setInterval;
    const originalClearInterval = global.clearInterval;
    global.setInterval = () => 1;
    global.clearInterval = () => {};

    let service;
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
        createInteractiveSession: () => Promise.resolve({ success: true, sessionId: 'test' }),
        testAICLICommand: () => Promise.resolve({ version: 'test' }),
        defaultWorkingDirectory: '/test',
        on: () => {},
        removeListener: () => {},
      };
      const authToken = 'test-token';

      // Test setup
      assert.doesNotThrow(() => {
        service = setupWebSocket(wss, claudeService, authToken);
      });
    } finally {
      // Clean up the service
      if (service && service.shutdown) {
        await service.shutdown();
      }

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
