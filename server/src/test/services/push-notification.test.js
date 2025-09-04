import test from 'node:test';
import assert from 'node:assert';
import { mock } from 'node:test';
import { EventEmitter } from 'events';

// Import the service and its components
import {
  PushNotificationService,
  pushNotificationService,
} from '../../services/push-notification/index.js';

// Mock the dependencies
const mockAPNsClient = class extends EventEmitter {
  constructor() {
    super();
    this.isConfigured = false;
    this.provider = null;
  }

  initialize(config) {
    this.isConfigured = config.configured || false;
  }

  async send(notification, token) {
    if (!this.isConfigured) {
      return { success: false, error: 'Not configured' };
    }
    if (token === 'bad-token') {
      return { success: false, error: 'BadDeviceToken' };
    }
    if (token === 'expired-token') {
      return { success: false, error: 'ExpiredProviderToken' };
    }
    if (token === 'fail-token') {
      return { success: false, error: 'SendError' };
    }
    return { success: true };
  }

  shutdown() {
    this.provider = null;
  }
};

const mockMessageFormatter = class {
  requiresFetch(message) {
    return message && message.length > 1000;
  }

  formatMessage(message, options = {}) {
    if (options.truncate) {
      return `${message.substring(0, 100)}...`;
    }
    return message;
  }
};

const mockNotificationTypes = class {
  createGenericNotification(data) {
    return {
      aps: { alert: { title: data.title, body: data.body } },
      payload: data.payload || {},
    };
  }

  createClaudeResponseNotification(data, options = {}) {
    return {
      aps: {
        alert: {
          title: 'Claude Response Ready',
          subtitle: data.projectName,
          body: data.message,
        },
      },
      payload: {
        sessionId: data.sessionId,
        requestId: data.requestId,
        requiresFetch: options.requiresFetch,
        messageId: options.messageId,
      },
    };
  }

  createProgressNotification(data) {
    return {
      aps: {
        alert: {
          title: 'Progress Update',
          body: `${data.activity} (${data.duration}s)`,
        },
      },
      payload: { type: 'progress', activity: data.activity },
    };
  }

  createAutoResponseControlNotification(data) {
    return {
      aps: {
        alert: {
          title: 'Auto-Response Control',
          body: data.action,
        },
      },
      payload: { type: 'auto-response', action: data.action },
    };
  }

  createStallAlert(data) {
    return {
      aps: {
        alert: {
          title: 'Claude Stalled',
          body: `Session ${data.sessionId} has been silent for ${data.silentMinutes} minutes`,
        },
      },
      payload: {
        type: 'stall',
        sessionId: data.sessionId,
        silentMinutes: data.silentMinutes,
      },
    };
  }

  createMessageNotification(data) {
    return {
      aps: {
        alert: {
          title: data.title || 'New Message',
          body: data.message,
        },
      },
      payload: {
        type: 'message',
        sessionId: data.sessionId,
        messageId: data.messageId,
      },
    };
  }

  createErrorNotification(data) {
    return {
      aps: {
        alert: {
          title: data.title || '❌ Processing Error',
          subtitle: data.projectName,
          body: data.error,
        },
      },
      payload: {
        type: 'error',
        error: true,
        errorType: data.errorType,
      },
    };
  }
};

// Mock the storeMessage function
mock.fn(); // mockStoreMessage

test('PushNotificationService', async (t) => {
  // Set up mocks before each test group
  // Store originals for cleanup
  const _originalAPNsClient = PushNotificationService.prototype.apnsClient;
  const _originalMessageFormatter = PushNotificationService.prototype.messageFormatter;
  const _originalNotificationTypes = PushNotificationService.prototype.notificationTypes;

  await t.test('constructor', async (tt) => {
    await tt.test('should initialize with default values', () => {
      const service = new PushNotificationService();
      assert.ok(service.apnsClient);
      assert.ok(service.messageFormatter);
      assert.ok(service.notificationTypes);
      assert.strictEqual(service.isConfigured, false);
      assert.ok(service.deviceTokens instanceof Map);
      assert.ok(service.badTokens instanceof Set);
      assert.ok(service.tokenRetryCount instanceof Map);
      assert.strictEqual(service.deviceTokens.size, 0);
      assert.strictEqual(service.badTokens.size, 0);
      assert.strictEqual(service.tokenRetryCount.size, 0);
    });
  });

  await t.test('initialize', async (tt) => {
    await tt.test('should initialize APNs client with config', () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();

      service.initialize({ configured: true });

      assert.strictEqual(service.isConfigured, true);
      assert.strictEqual(service.apnsClient.isConfigured, true);
    });

    await tt.test('should handle unconfigured state', () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();

      service.initialize({ configured: false });

      assert.strictEqual(service.isConfigured, false);
      assert.strictEqual(service.apnsClient.isConfigured, false);
    });
  });

  await t.test('registerDevice', async (tt) => {
    await tt.test('should register device with token string (old API)', () => {
      const service = new PushNotificationService();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'token123', 'ios');

      assert.strictEqual(service.deviceTokens.size, 1);
      assert.deepStrictEqual(service.deviceTokens.get('client1'), {
        token: 'token123',
        platform: 'ios',
      });
      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('Registered device token'));

      consoleSpy.mock.restore();
    });

    await tt.test('should register device with object (new API)', () => {
      const service = new PushNotificationService();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', { token: 'token456', platform: 'android' });

      assert.strictEqual(service.deviceTokens.size, 1);
      assert.deepStrictEqual(service.deviceTokens.get('client1'), {
        token: 'token456',
        platform: 'android',
      });

      consoleSpy.mock.restore();
    });

    await tt.test('should default to ios platform', () => {
      const service = new PushNotificationService();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'token789');

      assert.deepStrictEqual(service.deviceTokens.get('client1'), {
        token: 'token789',
        platform: 'ios',
      });

      consoleSpy.mock.restore();
    });

    await tt.test('should warn when missing token or clientId', () => {
      const service = new PushNotificationService();
      const consoleWarnSpy = mock.method(console, 'warn');

      service.registerDevice('', 'token123');
      service.registerDevice('client1', '');
      service.registerDevice('client2', null);
      service.registerDevice(null, 'token456');

      assert.strictEqual(service.deviceTokens.size, 0);
      assert.strictEqual(consoleWarnSpy.mock.calls.length, 4);
      assert.ok(consoleWarnSpy.mock.calls[0].arguments[0].includes('Cannot register device'));

      consoleWarnSpy.mock.restore();
    });
  });

  await t.test('unregisterDevice', async (tt) => {
    await tt.test('should unregister existing device', () => {
      const service = new PushNotificationService();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'token123');
      consoleSpy.mock.resetCalls();

      service.unregisterDevice('client1');

      assert.strictEqual(service.deviceTokens.size, 0);
      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('Unregistered device token'));

      consoleSpy.mock.restore();
    });

    await tt.test('should do nothing for non-existent client', () => {
      const service = new PushNotificationService();
      const consoleSpy = mock.method(console, 'log');

      service.unregisterDevice('nonexistent');

      assert.strictEqual(consoleSpy.mock.calls.length, 0);

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendNotification', async (tt) => {
    await tt.test('should send notification successfully', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;

      const notification = { aps: { alert: 'Test' } };
      const result = await service.sendNotification('good-token', notification);

      assert.strictEqual(result.success, true);
    });

    await tt.test('should handle bad device token', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;

      // Register a device with bad token
      service.registerDevice('client1', 'bad-token');

      const notification = { aps: { alert: 'Test' } };
      const result = await service.sendNotification('bad-token', notification);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'BadDeviceToken');
      assert.ok(service.badTokens.has('bad-token'));
      // Device should be removed
      assert.strictEqual(service.deviceTokens.size, 0);
    });

    await tt.test('should skip known bad tokens', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.badTokens.add('known-bad-token');

      const consoleSpy = mock.method(console, 'log');

      const notification = { aps: { alert: 'Test' } };
      const result = await service.sendNotification('known-bad-token', notification);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'BadDeviceToken');
      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('Skipping known bad token'));

      consoleSpy.mock.restore();
    });

    await tt.test('should handle expired provider token', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;

      const consoleErrorSpy = mock.method(console, 'error');

      const notification = { aps: { alert: 'Test' } };
      const result = await service.sendNotification('expired-token', notification);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'ExpiredProviderToken');
      assert.ok(consoleErrorSpy.mock.calls[0].arguments[0].includes('Provider token expired'));

      consoleErrorSpy.mock.restore();
    });

    await tt.test('should retry on failure', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;

      const consoleWarnSpy = mock.method(console, 'warn');

      const notification = { aps: { alert: 'Test' } };
      const result = await service.sendNotification('fail-token', notification, {
        retries: 2,
        retryDelay: 10,
      });

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'MaxRetriesExceeded');
      // Should have warned for each retry attempt
      assert.strictEqual(consoleWarnSpy.mock.calls.length, 2);

      consoleWarnSpy.mock.restore();
    });

    await tt.test('should handle exceptions during send', async () => {
      const service = new PushNotificationService();
      service.apnsClient = {
        send: mock.fn(async () => {
          throw new Error('Network error');
        }),
      };
      service.isConfigured = true;

      const consoleErrorSpy = mock.method(console, 'error');

      const notification = { aps: { alert: 'Test' } };

      await assert.rejects(
        service.sendNotification('any-token', notification, { retries: 1 }),
        /Network error/
      );

      consoleErrorSpy.mock.restore();
    });
  });

  await t.test('handleBadToken', async (tt) => {
    await tt.test('should add token to bad tokens set and remove from device tokens', async () => {
      const service = new PushNotificationService();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'bad-token-123');
      service.registerDevice('client2', 'good-token-456');
      consoleSpy.mock.resetCalls();

      await service.handleBadToken('bad-token-123');

      assert.ok(service.badTokens.has('bad-token-123'));
      assert.strictEqual(service.deviceTokens.size, 1);
      assert.ok(!service.deviceTokens.has('client1'));
      assert.ok(service.deviceTokens.has('client2'));
      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('Removed bad token'));

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendPushNotification', async (tt) => {
    await tt.test('should send generic push notification', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      const consoleSpy = mock.method(console, 'log');

      const result = await service.sendPushNotification('device-token', {
        title: 'Test Title',
        body: 'Test Body',
        payload: { custom: 'data' },
      });

      assert.strictEqual(result.success, true);
      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Generic push notification sent')
        )
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should handle not configured state', async () => {
      const service = new PushNotificationService();
      service.isConfigured = false;

      const consoleSpy = mock.method(console, 'log');

      const result = await service.sendPushNotification('device-token', {});

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'Not configured');
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notifications not configured')
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should handle missing device token', async () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      const result = await service.sendPushNotification(null, {});

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'No device token provided');
    });
  });

  await t.test('sendClaudeResponseNotification', async (tt) => {
    await tt.test('should send Claude response notification', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();
      service.messageFormatter = new mockMessageFormatter();

      service.registerDevice('client1', 'token123');

      const consoleSpy = mock.method(console, 'log');

      await service.sendClaudeResponseNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        message: 'Short message',
        requestId: 'req123',
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Push notification sent to client')
        )
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should handle large messages requiring fetch', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();
      service.messageFormatter = new mockMessageFormatter();

      // Mock console.log to verify the notification was sent
      const consoleLogSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'token123');

      const longMessage = 'x'.repeat(1001); // Over 1000 chars

      await service.sendClaudeResponseNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        message: longMessage,
        requestId: 'req123',
        projectPath: '/test/path',
      });

      // Verify that the notification was sent successfully
      const logCalls = consoleLogSpy.mock.calls.filter((call) =>
        call.arguments[0].includes('✅ Push notification sent to client')
      );
      assert.strictEqual(logCalls.length, 1);
      assert.ok(logCalls[0].arguments[0].includes('client1'));

      consoleLogSpy.mock.restore();
    });

    await tt.test('should skip when not configured', async () => {
      const service = new PushNotificationService();
      service.isConfigured = false;

      const consoleSpy = mock.method(console, 'log');

      await service.sendClaudeResponseNotification('client1', {});

      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notifications not configured')
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should skip when no device token found', async () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      const consoleSpy = mock.method(console, 'log');

      await service.sendClaudeResponseNotification('unknown-client', {});

      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('No device token found'));

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendProgressNotification', async (tt) => {
    await tt.test('should send progress notification', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      service.registerDevice('client1', 'token123');

      const consoleSpy = mock.method(console, 'log');

      await service.sendProgressNotification('client1', {
        activity: 'Processing',
        duration: 15,
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Progress notification sent')
        )
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should use token directly if not in device map', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      const consoleSpy = mock.method(console, 'log');

      await service.sendProgressNotification('direct-token', {
        activity: 'Processing',
        duration: 10,
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Progress notification sent')
        )
      );

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendAutoResponseControlNotification', async (tt) => {
    await tt.test('should send auto-response control notification', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      service.registerDevice('client1', 'token123');

      const consoleSpy = mock.method(console, 'log');

      await service.sendAutoResponseControlNotification('client1', {
        action: 'pause',
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Auto-response control notification sent')
        )
      );

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendStallAlert', async (tt) => {
    await tt.test('should send stall alert', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      const consoleSpy = mock.method(console, 'log');

      const result = await service.sendStallAlert('device-token', {
        sessionId: 'session123',
        silentMinutes: 5,
      });

      assert.strictEqual(result.success, true);
      assert.ok(
        consoleSpy.mock.calls.some((call) => call.arguments[0].includes('Stall alert sent'))
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should handle missing device token', async () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      const result = await service.sendStallAlert(null, {
        sessionId: 'session123',
        silentMinutes: 5,
      });

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'No device token provided');
    });
  });

  await t.test('sendMessageNotification', async (tt) => {
    await tt.test('should send message notification', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      const consoleSpy = mock.method(console, 'log');

      const result = await service.sendMessageNotification('device-token', {
        sessionId: 'session123',
        message: 'Test message',
        title: 'Custom Title',
      });

      assert.strictEqual(result.success, true);
      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Message notification sent')
        )
      );

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendErrorNotification', async (tt) => {
    await tt.test('should send error notification', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      service.registerDevice('client1', 'token123');

      const consoleSpy = mock.method(console, 'log');

      await service.sendErrorNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        error: 'Test error',
        errorType: 'ValidationError',
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) => call.arguments[0].includes('Error notification sent'))
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should use token directly if available', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();

      const consoleSpy = mock.method(console, 'log');

      await service.sendErrorNotification('direct-token', {
        sessionId: 'session123',
        error: 'Test error',
        errorType: 'RuntimeError',
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) => call.arguments[0].includes('Error notification sent'))
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should skip when token not found', async () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      const consoleSpy = mock.method(console, 'log');

      // Create a client entry without a token
      service.deviceTokens.set('client1', {});

      await service.sendErrorNotification('client1', {
        error: 'Test error',
      });

      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('No device token found'));

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendToMultipleClients', async (tt) => {
    await tt.test('should send to multiple clients in batches', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();
      service.messageFormatter = new mockMessageFormatter();

      // Register multiple clients
      for (let i = 1; i <= 15; i++) {
        service.registerDevice(`client${i}`, `token${i}`);
      }

      const consoleSpy = mock.method(console, 'log');

      const clientIds = Array.from({ length: 15 }, (_, i) => `client${i + 1}`);
      const results = await service.sendToMultipleClients(clientIds, {
        sessionId: 'session123',
        projectName: 'Test Project',
        message: 'Broadcast message',
      });

      assert.strictEqual(results.sent, 15);
      assert.strictEqual(results.failed, 0);
      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Sent push notifications to 15 devices')
        )
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should handle failures gracefully', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();
      service.messageFormatter = new mockMessageFormatter();

      // Register one good and one bad token
      service.registerDevice('client1', 'token1');
      service.registerDevice('client2', 'bad-token');

      const consoleErrorSpy = mock.method(console, 'error');

      const results = await service.sendToMultipleClients(['client1', 'client2', 'client3'], {
        sessionId: 'session123',
        message: 'Test',
      });

      // client1 should succeed, client2 should fail (bad token), client3 has no token
      assert.strictEqual(results.sent, 1); // Only client1 succeeds
      assert.strictEqual(results.failed, 2); // client2 fails (bad token), client3 has no token

      consoleErrorSpy.mock.restore();
    });

    await tt.test('should return zeros when not configured', async () => {
      const service = new PushNotificationService();
      service.isConfigured = false;

      const results = await service.sendToMultipleClients(['client1'], {});

      assert.strictEqual(results.sent, 0);
      assert.strictEqual(results.failed, 0);
    });

    await tt.test('should handle empty client list', async () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      const results = await service.sendToMultipleClients([], {});

      assert.strictEqual(results.sent, 0);
      assert.strictEqual(results.failed, 0);
    });

    await tt.test('should handle null client list', async () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      const results = await service.sendToMultipleClients(null, {});

      assert.strictEqual(results.sent, 0);
      assert.strictEqual(results.failed, 0);
    });

    await tt.test('should identify long-running completion', async () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();
      service.apnsClient.isConfigured = true;
      service.isConfigured = true;
      service.notificationTypes = new mockNotificationTypes();
      service.messageFormatter = new mockMessageFormatter();

      service.registerDevice('client1', 'token1');

      const consoleSpy = mock.method(console, 'log');

      await service.sendToMultipleClients(['client1'], {
        sessionId: 'session123',
        message: 'Test',
        isLongRunningCompletion: true,
      });

      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('long-running task completion')
        )
      );

      consoleSpy.mock.restore();
    });
  });

  await t.test('getStats', async (tt) => {
    await tt.test('should return current statistics', () => {
      const service = new PushNotificationService();
      service.isConfigured = true;

      service.registerDevice('client1', 'token1');
      service.registerDevice('client2', 'token2');
      service.badTokens.add('bad-token');
      service.tokenRetryCount.set('retry-token', 2);

      const stats = service.getStats();

      assert.deepStrictEqual(stats, {
        configuredDevices: 2,
        badTokens: 1,
        isConfigured: true,
        retryingTokens: 1,
      });
    });
  });

  await t.test('shutdown', async (tt) => {
    await tt.test('should call APNs client shutdown', () => {
      const service = new PushNotificationService();
      service.apnsClient = new mockAPNsClient();

      const consoleSpy = mock.method(console, 'log');
      const shutdownSpy = mock.method(service.apnsClient, 'shutdown');

      service.shutdown();

      assert.strictEqual(shutdownSpy.mock.calls.length, 1);
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notification service shut down')
      );

      consoleSpy.mock.restore();
      shutdownSpy.mock.restore();
    });

    await tt.test('should handle missing APNs client', () => {
      const service = new PushNotificationService();
      service.apnsClient = null;

      const consoleSpy = mock.method(console, 'log');

      // Should not throw
      assert.doesNotThrow(() => service.shutdown());

      // Should not log anything
      assert.strictEqual(consoleSpy.mock.calls.length, 0);

      consoleSpy.mock.restore();
    });
  });

  await t.test('singleton instance', async (tt) => {
    await tt.test('should export singleton instance', () => {
      assert.ok(pushNotificationService instanceof PushNotificationService);
    });
  });
});
