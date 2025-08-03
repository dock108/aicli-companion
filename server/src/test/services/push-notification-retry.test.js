import test from 'node:test';
import assert from 'node:assert';
import { mock } from 'node:test';
import { PushNotificationService } from '../../services/push-notification.js';

// Mock APN provider
class MockProvider {
  constructor() {
    this.sendCount = 0;
    this.shouldFail = false;
    this.failureReason = null;
  }

  async send(notification, token) {
    this.sendCount++;

    if (this.shouldFail) {
      return {
        sent: [],
        failed: [
          {
            device: token,
            response: { reason: this.failureReason || 'Unknown' },
          },
        ],
      };
    }

    return {
      sent: [{ device: token }],
      failed: [],
    };
  }

  shutdown() {
    // Mock shutdown
  }
}

test('PushNotificationService Retry Logic', async (t) => {
  let service;
  let mockProvider;

  t.beforeEach(() => {
    service = new PushNotificationService();
    mockProvider = new MockProvider();
    service.provider = mockProvider;
    service.isConfigured = true;
  });

  await t.test('should retry on failure', async () => {
    // Fail first 2 attempts, succeed on 3rd
    let attempt = 0;
    mockProvider.send = mock.fn(async () => {
      attempt++;
      if (attempt < 3) {
        return { sent: [], failed: [{ response: { reason: 'TemporaryError' } }] };
      }
      return { sent: [{ device: 'test-token' }], failed: [] };
    });

    const result = await service.sendNotification('test-token', {});

    assert.strictEqual(mockProvider.send.mock.calls.length, 3);
    assert.strictEqual(result.success, true);
  });

  await t.test('should not retry on BadDeviceToken', async () => {
    mockProvider.shouldFail = true;
    mockProvider.failureReason = 'BadDeviceToken';

    const result = await service.sendNotification('test-token', {});

    assert.strictEqual(mockProvider.sendCount, 1); // Only one attempt
    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error, 'BadDeviceToken');
    assert.ok(service.badTokens.has('test-token'));
  });

  await t.test('should skip known bad tokens', async () => {
    service.badTokens.add('bad-token');

    const result = await service.sendNotification('bad-token', {});

    assert.strictEqual(mockProvider.sendCount, 0); // No attempt made
    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error, 'BadDeviceToken');
  });

  await t.test('should respect max retries', async () => {
    mockProvider.shouldFail = true;
    mockProvider.failureReason = 'NetworkError';

    const result = await service.sendNotification('test-token', {}, { retries: 2 });

    assert.strictEqual(mockProvider.sendCount, 2);
    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error, 'MaxRetriesExceeded');
  });

  await t.test('should handle ExpiredProviderToken', async () => {
    mockProvider.shouldFail = true;
    mockProvider.failureReason = 'ExpiredProviderToken';

    const result = await service.sendNotification('test-token', {});

    assert.strictEqual(mockProvider.sendCount, 1);
    assert.strictEqual(result.success, false);
    assert.strictEqual(result.error, 'ExpiredProviderToken');
  });

  await t.test('handleBadToken should remove from deviceTokens', async () => {
    service.deviceTokens.set('client-1', { token: 'bad-token', platform: 'ios' });
    service.deviceTokens.set('client-2', { token: 'good-token', platform: 'ios' });

    await service.handleBadToken('bad-token');

    assert.ok(service.badTokens.has('bad-token'));
    assert.strictEqual(service.deviceTokens.has('client-1'), false);
    assert.strictEqual(service.deviceTokens.has('client-2'), true);
  });

  await t.test('sendToMultipleClients should handle multiple devices', async () => {
    // Register some devices
    service.registerDevice('client-1', 'token-1');
    service.registerDevice('client-2', 'token-2');
    service.registerDevice('client-3', 'token-3');

    // Mock successful sends
    mockProvider.shouldFail = false;

    const data = {
      sessionId: 'test-session',
      projectName: 'Test Project',
      message: 'Test message',
      isLongRunningCompletion: true,
    };

    const results = await service.sendToMultipleClients(['client-1', 'client-2', 'client-3'], data);

    assert.strictEqual(results.sent, 3);
    assert.strictEqual(results.failed, 0);
  });

  await t.test('sendToMultipleClients should handle concurrency limit', async () => {
    // Register many devices
    const clientIds = [];
    for (let i = 0; i < 25; i++) {
      const clientId = `client-${i}`;
      service.registerDevice(clientId, `token-${i}`);
      clientIds.push(clientId);
    }

    let concurrentCalls = 0;
    let maxConcurrent = 0;

    // Track concurrent calls
    mockProvider.send = mock.fn(async () => {
      concurrentCalls++;
      maxConcurrent = Math.max(maxConcurrent, concurrentCalls);
      await new Promise((resolve) => setTimeout(resolve, 10));
      concurrentCalls--;
      return { sent: [{ device: 'token' }], failed: [] };
    });

    const data = {
      sessionId: 'test-session',
      projectName: 'Test Project',
      message: 'Test message',
    };

    await service.sendToMultipleClients(clientIds, data);

    // Should respect concurrency limit of 10
    assert.ok(maxConcurrent <= 10);
    assert.strictEqual(mockProvider.send.mock.calls.length, 25);
  });

  await t.test('getStats should return correct statistics', () => {
    service.registerDevice('client-1', 'token-1');
    service.registerDevice('client-2', 'token-2');
    service.badTokens.add('bad-token-1');
    service.badTokens.add('bad-token-2');
    service.tokenRetryCount.set('token-3', 2);

    const stats = service.getStats();

    assert.strictEqual(stats.configuredDevices, 2);
    assert.strictEqual(stats.badTokens, 2);
    assert.strictEqual(stats.isConfigured, true);
    assert.strictEqual(stats.retryingTokens, 1);
  });
});
