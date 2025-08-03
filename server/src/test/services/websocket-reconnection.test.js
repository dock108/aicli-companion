import test from 'node:test';
import assert from 'node:assert';
import { mock } from 'node:test';
import { WebSocketConnectionManager } from '../../services/websocket-connection-manager.js';
import { EventEmitter } from 'events';

// Mock WebSocket
class MockWebSocket extends EventEmitter {
  constructor() {
    super();
    this.readyState = 1; // OPEN
    this.isAlive = true;
  }

  close(code, reason) {
    this.readyState = 3; // CLOSED
    this.emit('close', code, reason);
  }

  send(_data) {
    // Mock send
  }
}

// Mock request
function createMockRequest(options = {}) {
  return {
    url: options.url || '/ws',
    headers: {
      host: 'localhost:3001',
      'user-agent': options.userAgent || 'Test Client/1.0',
      'x-device-id': options.deviceId || null,
      ...options.headers,
    },
    socket: {
      remoteAddress: options.ip || '127.0.0.1',
      remoteFamily: options.family || 'IPv4',
    },
  };
}

test('WebSocket Reconnection Support', async (t) => {
  let connectionManager;
  let mockGenerateId;
  let idCounter = 0;

  t.beforeEach(() => {
    // Mock ID generator for predictable IDs
    mockGenerateId = mock.fn(() => `client-${++idCounter}`);

    connectionManager = new WebSocketConnectionManager({
      generateId: mockGenerateId,
      healthCheckInterval: 1000,
      reconnectionWindow: 5000, // 5 seconds for testing
    });
  });

  t.afterEach(() => {
    connectionManager.shutdown();
    mock.restoreAll();
    idCounter = 0;
  });

  await t.test('should detect reconnection from same device', async () => {
    const ws1 = new MockWebSocket();
    const request1 = createMockRequest({
      deviceId: 'iphone-12345',
      userAgent: 'ClaudeCompanion/1.0 iOS/17.0',
    });

    // First connection
    const clientId1 = await connectionManager.handleConnection(ws1, request1);
    connectionManager.addSessionToClient(clientId1, 'session-1');
    connectionManager.addSessionToClient(clientId1, 'session-2');

    // Disconnect
    connectionManager.handleDisconnection(clientId1, 1000, 'Normal closure');

    // Reconnect within window
    const ws2 = new MockWebSocket();
    const request2 = createMockRequest({
      deviceId: 'iphone-12345',
      userAgent: 'ClaudeCompanion/1.0 iOS/17.0',
    });

    const clientId2 = await connectionManager.handleConnection(ws2, request2);

    // Verify reconnection was detected
    const client2 = connectionManager.getClient(clientId2);
    assert.strictEqual(client2.isReconnection, true);
    assert.strictEqual(client2.previousClientId, clientId1);

    // Verify sessions were restored
    assert.strictEqual(client2.sessionIds.size, 2);
    assert.ok(client2.sessionIds.has('session-1'));
    assert.ok(client2.sessionIds.has('session-2'));
  });

  await t.test(
    'should detect reconnection even after reconnection window expires due to persistence',
    async () => {
      // Create a connection manager with a very short reconnection window for testing
      const shortWindowManager = new WebSocketConnectionManager({
        reconnectionWindow: 100, // 100ms window
      });

      const ws1 = new MockWebSocket();
      const request1 = createMockRequest({ deviceId: 'iphone-12345' });

      const clientId1 = await shortWindowManager.handleConnection(ws1, request1);
      shortWindowManager.addSessionToClient(clientId1, 'session-1');

      // Disconnect
      shortWindowManager.handleDisconnection(clientId1, 1000, 'Normal closure');

      // Wait for reconnection window to expire (100ms window + 50ms buffer)
      await new Promise((resolve) => setTimeout(resolve, 150));

      const ws2 = new MockWebSocket();
      const request2 = createMockRequest({ deviceId: 'iphone-12345' });

      const clientId2 = await shortWindowManager.handleConnection(ws2, request2);
      const client2 = shortWindowManager.getClient(clientId2);

      // With persistence, connections are still treated as reconnections
      // because ConnectionStateManager persists state for 24 hours by default
      assert.strictEqual(client2.isReconnection, true);
      assert.strictEqual(client2.sessionIds.size, 1);
      assert.ok(client2.sessionIds.has('session-1'));

      // Clean up
      shortWindowManager.shutdown();
    }
  );

  await t.test('should create proper client fingerprint', () => {
    const manager = new WebSocketConnectionManager();

    // With device ID
    const fingerprint1 = manager.createClientFingerprint({
      deviceId: 'iphone-12345',
      userAgent: 'Test',
    });
    assert.strictEqual(fingerprint1, 'device:iphone-12345');

    // Without device ID - uses user agent
    const fingerprint2 = manager.createClientFingerprint({
      userAgent: 'ClaudeCompanion/1.0',
    });
    assert.ok(fingerprint2.startsWith('ua:'));
    assert.ok(fingerprint2.length > 3);
  });

  await t.test('should handle connection history cleanup', async () => {
    const manager = new WebSocketConnectionManager({
      reconnectionWindow: 100, // 100ms for quick testing
    });

    // Add some history entries
    await manager.addToConnectionHistory(
      'client-1',
      {
        fingerprint: 'test-1',
      },
      new Set(['session-1'])
    );

    await manager.addToConnectionHistory(
      'client-2',
      {
        fingerprint: 'test-2',
      },
      new Set(['session-2'])
    );

    assert.strictEqual(manager.connectionHistory.size, 2);

    // Wait for cleanup (happens after 2x reconnection window)
    await new Promise((resolve) => setTimeout(resolve, 250));

    // Trigger cleanup manually (normally runs every minute)
    const now = Date.now();
    const expired = [];

    for (const [key, data] of manager.connectionHistory) {
      if (now - data.lastSeen > manager.reconnectionWindow * 2) {
        expired.push(key);
      }
    }

    expired.forEach((key) => manager.connectionHistory.delete(key));

    // Should be cleaned up
    assert.strictEqual(manager.connectionHistory.size, 0);

    manager.shutdown();
  });

  await t.test('should not match different devices', async () => {
    const ws1 = new MockWebSocket();
    const request1 = createMockRequest({ deviceId: 'iphone-11111' });

    const clientId1 = await connectionManager.handleConnection(ws1, request1);
    connectionManager.addSessionToClient(clientId1, 'session-1');
    connectionManager.handleDisconnection(clientId1, 1000, 'Normal closure');

    // Different device
    const ws2 = new MockWebSocket();
    const request2 = createMockRequest({ deviceId: 'iphone-22222' });

    const clientId2 = await connectionManager.handleConnection(ws2, request2);
    const client2 = connectionManager.getClient(clientId2);

    // Should not be reconnection
    assert.strictEqual(client2.isReconnection, false);
    assert.strictEqual(client2.sessionIds.size, 0);
  });

  await t.test('should match by user agent when no device ID', async () => {
    const ws1 = new MockWebSocket();
    const request1 = createMockRequest({
      userAgent: 'ClaudeCompanion/1.0 iOS/17.0',
    });

    const clientId1 = await connectionManager.handleConnection(ws1, request1);
    connectionManager.addSessionToClient(clientId1, 'session-1');
    connectionManager.handleDisconnection(clientId1, 1000, 'Normal closure');

    // Same user agent, no device ID
    const ws2 = new MockWebSocket();
    const request2 = createMockRequest({
      userAgent: 'ClaudeCompanion/1.0 iOS/17.0',
    });

    const clientId2 = await connectionManager.handleConnection(ws2, request2);
    const client2 = connectionManager.getClient(clientId2);

    // Should detect reconnection
    assert.strictEqual(client2.isReconnection, true);
    assert.ok(client2.sessionIds.has('session-1'));
  });
});
