import test from 'node:test';
import assert from 'node:assert';
import { ConnectionStateManager } from '../../services/connection-state-manager.js';

test('ConnectionStateManager', async (t) => {
  let stateManager;

  t.beforeEach(() => {
    stateManager = new ConnectionStateManager();
  });

  t.afterEach(() => {
    stateManager.shutdown();
  });

  await t.test('should save and retrieve connection state', async () => {
    const fingerprint = 'device:test-123';
    const state = {
      sessionIds: new Set(['session-1', 'session-2']),
      firstSeen: Date.now(),
    };

    await stateManager.saveConnectionState(fingerprint, state);

    const retrieved = await stateManager.getConnectionState(fingerprint);
    assert.ok(retrieved);
    assert.ok(retrieved.sessionIds);
    assert.strictEqual(retrieved.sessionIds.size, 2);
    assert.ok(retrieved.sessionIds.has('session-1'));
    assert.ok(retrieved.sessionIds.has('session-2'));
    assert.ok(retrieved.lastUpdated);
    assert.ok(retrieved.expiresAt);
  });

  await t.test('should return null for non-existent state', async () => {
    const state = await stateManager.getConnectionState('non-existent');
    assert.strictEqual(state, null);
  });

  await t.test('should handle expired states', async () => {
    const manager = new ConnectionStateManager({ ttl: 100 }); // 100ms TTL
    const fingerprint = 'device:test-expire';

    await manager.saveConnectionState(fingerprint, {
      sessionIds: new Set(['session-1']),
    });

    // Wait for expiration
    await new Promise((resolve) => setTimeout(resolve, 150));

    const state = await manager.getConnectionState(fingerprint);
    assert.strictEqual(state, null);

    manager.shutdown();
  });

  await t.test('should update connection sessions', async () => {
    const fingerprint = 'device:test-update';

    // First update
    await stateManager.updateConnectionSessions(fingerprint, ['session-1']);

    let state = await stateManager.getConnectionState(fingerprint);
    assert.strictEqual(state.sessionIds.size, 1);
    assert.ok(state.sessionIds.has('session-1'));

    // Second update adds more sessions
    await stateManager.updateConnectionSessions(fingerprint, ['session-2', 'session-3']);

    state = await stateManager.getConnectionState(fingerprint);
    assert.strictEqual(state.sessionIds.size, 3);
    assert.ok(state.sessionIds.has('session-1'));
    assert.ok(state.sessionIds.has('session-2'));
    assert.ok(state.sessionIds.has('session-3'));
  });

  await t.test('should clean up expired states', async () => {
    const manager = new ConnectionStateManager({ ttl: 100 });

    // Add some states
    await manager.saveConnectionState('device:1', { sessionIds: new Set(['s1']) });
    await manager.saveConnectionState('device:2', { sessionIds: new Set(['s2']) });

    // Wait for expiration
    await new Promise((resolve) => setTimeout(resolve, 150));

    // Add a fresh state
    await manager.saveConnectionState('device:3', { sessionIds: new Set(['s3']) });

    // Run cleanup
    manager.cleanupExpiredStates();

    // Check states
    assert.strictEqual(await manager.getConnectionState('device:1'), null);
    assert.strictEqual(await manager.getConnectionState('device:2'), null);
    assert.ok(await manager.getConnectionState('device:3'));

    manager.shutdown();
  });

  await t.test('should provide accurate statistics', async () => {
    const manager = new ConnectionStateManager({ ttl: 100 });

    await manager.saveConnectionState('device:1', { sessionIds: new Set(['s1']) });
    await manager.saveConnectionState('device:2', { sessionIds: new Set(['s2']) });

    let stats = manager.getStats();
    assert.strictEqual(stats.total, 2);
    assert.strictEqual(stats.active, 2);
    assert.strictEqual(stats.expired, 0);
    assert.strictEqual(stats.storageType, 'memory');

    // Wait for expiration
    await new Promise((resolve) => setTimeout(resolve, 150));

    stats = manager.getStats();
    assert.strictEqual(stats.total, 2);
    assert.strictEqual(stats.active, 0);
    assert.strictEqual(stats.expired, 2);

    manager.shutdown();
  });

  await t.test('should handle storage type configuration', () => {
    // Test memory storage (default)
    const memoryManager = new ConnectionStateManager();
    assert.strictEqual(memoryManager.storage, 'memory');
    memoryManager.shutdown();

    // Test configured storage type
    const redisManager = new ConnectionStateManager({ storage: 'redis' });
    assert.strictEqual(redisManager.storage, 'redis');
    redisManager.shutdown();
  });

  await t.test('should not set cleanup interval in test environment', () => {
    const manager = new ConnectionStateManager();
    assert.strictEqual(manager.cleanupInterval, undefined);
    manager.shutdown();
  });
});
