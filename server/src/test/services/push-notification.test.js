import test from 'node:test';
import assert from 'node:assert';
import { mock } from 'node:test';
import fs from 'fs';
import apn from '@parse/node-apn';

// Import the service
import { pushNotificationService } from '../../services/push-notification.js';

// Mock notification class
class MockNotification {
  constructor() {
    this.aps = {}; // Required by APN library
    this.expiry = null;
    this.badge = null;
    this.topic = null;
    this.payload = {};
    this.pushType = null;
    this.threadId = null;
  }

  // APN library expects these setters to work with this.aps
  set alert(value) {
    this.aps.alert = value;
  }

  get alert() {
    return this.aps.alert;
  }

  set sound(value) {
    this.aps.sound = value;
  }

  get sound() {
    return this.aps.sound;
  }

  set badge(value) {
    this.aps.badge = value;
  }

  get badge() {
    return this.aps.badge;
  }
}

test('PushNotificationService', async (t) => {
  await t.test('constructor', async (tt) => {
    await tt.test('should initialize with default values', () => {
      const service = new pushNotificationService.constructor();
      assert.strictEqual(service.provider, null);
      assert.strictEqual(service.isConfigured, false);
      assert.ok(service.deviceTokens instanceof Map);
      assert.strictEqual(service.deviceTokens.size, 0);
    });
  });

  await t.test('initialize', async (tt) => {
    await tt.test('should log warning when missing cert or key path', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      service.initialize({});

      assert.strictEqual(consoleSpy.mock.calls.length, 1);
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notifications not configured')
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should log warning when cert or key files do not exist', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');
      const existsSyncMock = mock.method(fs, 'existsSync', () => false);

      service.initialize({ cert: '/fake/cert.pem', key: '/fake/key.pem' });

      assert.strictEqual(consoleSpy.mock.calls.length, 1);
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('certificate or key file not found')
      );

      consoleSpy.mock.restore();
      existsSyncMock.mock.restore();
    });

    await tt.test('should initialize provider when valid config provided', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');
      const existsSyncMock = mock.method(fs, 'existsSync', () => true);

      // Mock the Provider constructor
      const mockProvider = { shutdown: () => {} };
      const providerMock = mock.method(apn, 'Provider', function() {
        return mockProvider;
      });

      service.initialize({
        cert: '/valid/cert.pem',
        key: '/valid/key.pem',
        passphrase: 'test',
        production: true,
      });

      assert.strictEqual(service.isConfigured, true);
      assert.strictEqual(service.provider, mockProvider);
      assert.strictEqual(consoleSpy.mock.calls.length, 1);
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notification service initialized')
      );
      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('production mode'));

      consoleSpy.mock.restore();
      existsSyncMock.mock.restore();
      providerMock.mock.restore();
    });

    await tt.test('should handle initialization errors', () => {
      const service = new pushNotificationService.constructor();
      const consoleErrorSpy = mock.method(console, 'error');
      const existsSyncMock = mock.method(fs, 'existsSync', () => true);

      // Mock Provider to throw error
      const providerMock = mock.method(apn, 'Provider', function() {
        throw new Error('Provider error');
      });

      service.initialize({ cert: '/valid/cert.pem', key: '/valid/key.pem' });

      assert.strictEqual(service.isConfigured, false);
      assert.strictEqual(consoleErrorSpy.mock.calls.length, 1);
      assert.ok(
        consoleErrorSpy.mock.calls[0].arguments[0].includes(
          'Failed to initialize push notification service'
        )
      );

      consoleErrorSpy.mock.restore();
      existsSyncMock.mock.restore();
      providerMock.mock.restore();
    });
  });

  await t.test('registerDevice', async (tt) => {
    await tt.test('should register valid device token', () => {
      const service = new pushNotificationService.constructor();
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

    await tt.test('should warn when missing token or clientId', () => {
      const service = new pushNotificationService.constructor();
      const consoleWarnSpy = mock.method(console, 'warn');

      service.registerDevice('', 'token123');
      service.registerDevice('client1', '');

      assert.strictEqual(service.deviceTokens.size, 0);
      assert.strictEqual(consoleWarnSpy.mock.calls.length, 2);
      assert.ok(consoleWarnSpy.mock.calls[0].arguments[0].includes('Cannot register device'));

      consoleWarnSpy.mock.restore();
    });

    await tt.test('should default to ios platform', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'token123');

      assert.deepStrictEqual(service.deviceTokens.get('client1'), {
        token: 'token123',
        platform: 'ios',
      });

      consoleSpy.mock.restore();
    });
  });

  await t.test('unregisterDevice', async (tt) => {
    await tt.test('should unregister existing device', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      service.registerDevice('client1', 'token123');
      consoleSpy.mock.resetCalls();

      service.unregisterDevice('client1');

      assert.strictEqual(service.deviceTokens.size, 0);
      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('Unregistered device token'));

      consoleSpy.mock.restore();
    });

    await tt.test('should do nothing for non-existent client', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      service.unregisterDevice('nonexistent');

      assert.strictEqual(consoleSpy.mock.calls.length, 0);

      consoleSpy.mock.restore();
    });
  });

  await t.test('sendClaudeResponseNotification', async (tt) => {
    await tt.test('should skip when not configured', async () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      await service.sendClaudeResponseNotification('client1', {});

      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notifications not configured')
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should skip when no device token found', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      const consoleSpy = mock.method(console, 'log');

      await service.sendClaudeResponseNotification('client1', {});

      assert.ok(consoleSpy.mock.calls[0].arguments[0].includes('No device token found'));

      consoleSpy.mock.restore();
    });

    await tt.test('should send notification successfully', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      service.registerDevice('client1', 'token123');

      // Mock the Notification constructor
      const notificationMock = mock.method(apn, 'Notification', MockNotification);

      const mockProvider = {
        send: mock.fn(async () => ({
          sent: ['token123'],
          failed: [],
        })),
      };
      service.provider = mockProvider;

      const consoleSpy = mock.method(console, 'log');

      await service.sendClaudeResponseNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        message: 'Test message',
        totalChunks: 5,
      });

      assert.strictEqual(mockProvider.send.mock.calls.length, 1);
      const notification = mockProvider.send.mock.calls[0].arguments[0];
      assert.strictEqual(notification.aps.alert.title, 'Claude Response Ready');
      assert.strictEqual(notification.aps.alert.subtitle, 'Test Project');
      assert.strictEqual(notification.aps.alert.body, 'Test message');
      // Find the log call that contains 'Push notification sent'
      const sentLogCall = consoleSpy.mock.calls.find(
        (call) => call.arguments[0] && call.arguments[0].includes('Push notification sent')
      );
      assert.ok(sentLogCall, 'Should log push notification sent');

      consoleSpy.mock.restore();
      notificationMock.mock.restore();
    });

    await tt.test('should handle failed notifications', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      service.registerDevice('client1', 'token123');

      const notificationMock = mock.method(apn, 'Notification', MockNotification);

      const mockProvider = {
        send: mock.fn(async () => ({
          sent: [],
          failed: [{ error: 'Failed to send' }],
        })),
      };
      service.provider = mockProvider;

      const consoleErrorSpy = mock.method(console, 'error');

      await service.sendClaudeResponseNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        message: 'Test message',
        totalChunks: 5,
      });

      assert.ok(consoleErrorSpy.mock.calls[0].arguments[0].includes('Push notification failed'));

      consoleErrorSpy.mock.restore();
      notificationMock.mock.restore();
    });

    await tt.test('should handle provider errors', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      service.registerDevice('client1', 'token123');

      const notificationMock = mock.method(apn, 'Notification', MockNotification);

      const mockProvider = {
        send: mock.fn(async () => {
          throw new Error('Provider error');
        }),
      };
      service.provider = mockProvider;

      const consoleErrorSpy = mock.method(console, 'error');

      await service.sendClaudeResponseNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        message: 'Test message',
        totalChunks: 5,
      });

      assert.ok(
        consoleErrorSpy.mock.calls[0].arguments[0].includes('Error sending push notification')
      );

      consoleErrorSpy.mock.restore();
      notificationMock.mock.restore();
    });
  });

  await t.test('sendErrorNotification', async (tt) => {
    await tt.test('should skip when not configured', async () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      await service.sendErrorNotification('client1', {});

      // Should return silently
      assert.strictEqual(consoleSpy.mock.calls.length, 0);

      consoleSpy.mock.restore();
    });

    await tt.test('should skip when no device token found', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      const consoleSpy = mock.method(console, 'log');

      await service.sendErrorNotification('client1', {});

      // Should return silently
      assert.strictEqual(consoleSpy.mock.calls.length, 0);

      consoleSpy.mock.restore();
    });

    await tt.test('should send error notification successfully', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      service.registerDevice('client1', 'token123');

      const notificationMock = mock.method(apn, 'Notification', MockNotification);

      const mockProvider = {
        send: mock.fn(async () => ({
          sent: ['token123'],
          failed: [],
        })),
      };
      service.provider = mockProvider;

      await service.sendErrorNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        error: 'Test error message',
      });

      assert.strictEqual(mockProvider.send.mock.calls.length, 1);
      const notification = mockProvider.send.mock.calls[0].arguments[0];
      assert.strictEqual(notification.aps.alert.title, 'Claude Error');
      assert.strictEqual(notification.aps.alert.subtitle, 'Test Project');
      assert.strictEqual(notification.aps.alert.body, 'Test error message');
      assert.strictEqual(notification.payload.error, true);

      notificationMock.mock.restore();
    });

    await tt.test('should handle provider errors', async () => {
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      service.registerDevice('client1', 'token123');

      const notificationMock = mock.method(apn, 'Notification', MockNotification);

      const mockProvider = {
        send: mock.fn(async () => {
          throw new Error('Provider error');
        }),
      };
      service.provider = mockProvider;

      const consoleErrorSpy = mock.method(console, 'error');

      await service.sendErrorNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        error: 'Test error',
      });

      assert.ok(
        consoleErrorSpy.mock.calls[0].arguments[0].includes('Error sending error notification')
      );

      consoleErrorSpy.mock.restore();
      notificationMock.mock.restore();
    });
  });

  await t.test('truncateMessage', async (tt) => {
    await tt.test('should return original message if shorter than maxLength', () => {
      const service = new pushNotificationService.constructor();

      assert.strictEqual(service.truncateMessage('Short message', 150), 'Short message');
    });

    await tt.test('should truncate long messages', () => {
      const service = new pushNotificationService.constructor();
      const longMessage = 'a'.repeat(200);

      const result = service.truncateMessage(longMessage, 150);
      assert.strictEqual(result.length, 153); // 150 + '...'
      assert.ok(result.endsWith('...'));
    });

    await tt.test('should handle custom maxLength', () => {
      const service = new pushNotificationService.constructor();

      const result = service.truncateMessage('This is a test message', 10);
      assert.strictEqual(result, 'This is a ...');
    });

    await tt.test('should handle null or undefined messages', () => {
      const service = new pushNotificationService.constructor();

      assert.strictEqual(service.truncateMessage(null), '');
      assert.strictEqual(service.truncateMessage(undefined), '');
    });

    await tt.test('should handle empty messages', () => {
      const service = new pushNotificationService.constructor();

      assert.strictEqual(service.truncateMessage(''), '');
    });
  });

  await t.test('shutdown', async (tt) => {
    await tt.test('should shutdown provider if exists', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      const mockProvider = {
        shutdown: mock.fn(),
      };
      service.provider = mockProvider;

      service.shutdown();

      assert.strictEqual(mockProvider.shutdown.mock.calls.length, 1);
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notification service shut down')
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should do nothing if no provider', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      service.shutdown();

      assert.strictEqual(consoleSpy.mock.calls.length, 0);

      consoleSpy.mock.restore();
    });
  });
});
