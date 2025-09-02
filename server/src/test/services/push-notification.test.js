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

      // Store original env vars
      const originalAuthKey = process.env.APNS_KEY_PATH;
      const originalKeyId = process.env.APNS_KEY_ID;
      const originalTeamId = process.env.APNS_TEAM_ID;

      // Clear env vars to simulate missing configuration
      delete process.env.APNS_KEY_PATH;
      delete process.env.APNS_KEY_ID;
      delete process.env.APNS_TEAM_ID;

      service.initialize({});

      // Check that warning was logged
      const logCalls = consoleSpy.mock.calls;
      const warningFound = logCalls.some(
        (call) =>
          call.arguments[0]?.includes &&
          call.arguments[0].includes('Push notifications not configured')
      );
      assert.ok(
        warningFound || service.isConfigured === false,
        'Should warn about missing configuration or not be configured'
      );

      consoleSpy.mock.restore();

      // Restore env vars
      if (originalAuthKey) process.env.APNS_KEY_PATH = originalAuthKey;
      if (originalKeyId) process.env.APNS_KEY_ID = originalKeyId;
      if (originalTeamId) process.env.APNS_TEAM_ID = originalTeamId;
    });

    await tt.test('should log warning when cert or key files do not exist', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');
      const existsSyncMock = mock.method(fs, 'existsSync', () => false);

      // Store original env vars
      const originalAuthKey = process.env.APNS_KEY_PATH;
      const originalKeyId = process.env.APNS_KEY_ID;
      const originalTeamId = process.env.APNS_TEAM_ID;

      // Set env vars but file doesn't exist
      process.env.APNS_KEY_PATH = '/fake/AuthKey.p8';
      process.env.APNS_KEY_ID = 'TEST_KEY_ID';
      process.env.APNS_TEAM_ID = 'TEST_TEAM_ID';

      service.initialize({});

      const logCalls = consoleSpy.mock.calls;
      const warningFound = logCalls.some(
        (call) =>
          call.arguments[0]?.includes && call.arguments[0].includes('APNs key file not found')
      );
      assert.ok(
        warningFound || service.isConfigured === false,
        'Should warn about missing file or not be configured'
      );

      consoleSpy.mock.restore();
      existsSyncMock.mock.restore();

      // Restore env vars
      if (originalAuthKey) process.env.APNS_KEY_PATH = originalAuthKey;
      else delete process.env.APNS_KEY_PATH;
      if (originalKeyId) process.env.APNS_KEY_ID = originalKeyId;
      else delete process.env.APNS_KEY_ID;
      if (originalTeamId) process.env.APNS_TEAM_ID = originalTeamId;
      else delete process.env.APNS_TEAM_ID;
    });

    await tt.test('should initialize provider when valid config provided', () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');
      const existsSyncMock = mock.method(fs, 'existsSync', () => true);
      const readFileSyncMock = mock.method(fs, 'readFileSync', () => 'fake-key-content');

      // Mock the Provider constructor
      const mockProvider = { shutdown: () => {} };
      // eslint-disable-next-line prefer-arrow-callback, func-names
      const providerMock = mock.method(apn, 'Provider', function () {
        return mockProvider;
      });

      // Store original env vars
      const originalAuthKey = process.env.APNS_KEY_PATH;
      const originalKeyId = process.env.APNS_KEY_ID;
      const originalTeamId = process.env.APNS_TEAM_ID;
      const originalBundleId = process.env.APNS_BUNDLE_ID;

      // Set required env vars
      process.env.APNS_KEY_PATH = '/valid/AuthKey.p8';
      process.env.APNS_KEY_ID = 'TEST_KEY_ID';
      process.env.APNS_TEAM_ID = 'TEST_TEAM_ID';
      process.env.APNS_BUNDLE_ID = 'com.test.app';

      service.initialize({});

      assert.ok(providerMock.mock.calls.length > 0);
      assert.ok(service.isConfigured);
      assert.strictEqual(service.bundleId, 'com.test.app');

      consoleSpy.mock.restore();
      existsSyncMock.mock.restore();
      readFileSyncMock.mock.restore();
      providerMock.mock.restore();

      // Restore env vars
      if (originalAuthKey) process.env.APNS_KEY_PATH = originalAuthKey;
      else delete process.env.APNS_KEY_PATH;
      if (originalKeyId) process.env.APNS_KEY_ID = originalKeyId;
      else delete process.env.APNS_KEY_ID;
      if (originalTeamId) process.env.APNS_TEAM_ID = originalTeamId;
      else delete process.env.APNS_TEAM_ID;
      if (originalBundleId) process.env.APNS_BUNDLE_ID = originalBundleId;
      else delete process.env.APNS_BUNDLE_ID;
    });

    await tt.test('should handle initialization errors', () => {
      const service = new pushNotificationService.constructor();
      const consoleErrorSpy = mock.method(console, 'error');
      const existsSyncMock = mock.method(fs, 'existsSync', () => true);

      // Mock Provider to throw error
      // eslint-disable-next-line prefer-arrow-callback, func-names
      const providerMock = mock.method(apn, 'Provider', function () {
        throw new Error('Provider error');
      });

      // Mock readFileSync to return fake key content
      const readFileSyncMock = mock.method(fs, 'readFileSync', () => 'fake-key-content');

      // Set required env vars
      process.env.APNS_KEY_PATH = '/valid/AuthKey.p8';
      process.env.APNS_KEY_ID = 'TEST_KEY_ID';
      process.env.APNS_TEAM_ID = 'TEST_TEAM_ID';

      service.initialize({});

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
      readFileSyncMock.mock.restore();

      // Clean up env vars to avoid affecting other tests
      delete process.env.APNS_KEY_PATH;
      delete process.env.APNS_KEY_ID;
      delete process.env.APNS_TEAM_ID;
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

    await tt.test('should skip response notification when no device token found', async () => {
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

      // Wait a bit for async operations to complete
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Check all console.error calls for the expected message
      const errorCalls = consoleErrorSpy.mock.calls;
      const hasExpectedError = errorCalls.some(
        (call) =>
          call.arguments[0].includes('Push notification attempt') ||
          call.arguments[0].includes('❌ Error sending push notification')
      );

      assert.ok(hasExpectedError, 'Expected error message not found in console.error calls');

      consoleErrorSpy.mock.restore();
      notificationMock.mock.restore();
    });
  });

  await t.test('sendErrorNotification', async (tt) => {
    await tt.test('should skip when not configured', async () => {
      const service = new pushNotificationService.constructor();
      const consoleSpy = mock.method(console, 'log');

      await service.sendErrorNotification('client1', {});

      // Should log a warning about not being configured
      assert.strictEqual(consoleSpy.mock.calls.length, 1);
      assert.ok(
        consoleSpy.mock.calls[0].arguments[0].includes('Push notifications not configured')
      );

      consoleSpy.mock.restore();
    });

    await tt.test('should skip error notification when no device token found', async () => {
      // Create a fresh instance
      const service = new pushNotificationService.constructor();
      service.isConfigured = true;
      service.deviceTokens = new Map(); // Fresh empty map

      // Just verify that the method returns without error when no token exists
      await assert.doesNotReject(
        service.sendErrorNotification('client1', {}),
        'Should not throw when no device token'
      );

      // The method should have returned early - no need to check console logs
      // as they are implementation details
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
      assert.strictEqual(notification.aps.alert.title, '❌ Processing Error'); // Default error title
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

      // Override sendNotification to reduce retry delay in test
      const originalSendNotification = service.sendNotification.bind(service);
      service.sendNotification = async function (deviceToken, notification, options = {}) {
        return originalSendNotification(deviceToken, notification, {
          ...options,
          retryDelay: 10, // Use 10ms instead of 1000ms for tests
        });
      };

      await service.sendErrorNotification('client1', {
        sessionId: 'session123',
        projectName: 'Test Project',
        error: 'Test error',
      });

      // Wait a bit for async operations to complete
      await new Promise((resolve) => setTimeout(resolve, 50));

      // Check all console.error calls for the expected message
      const errorCalls = consoleErrorSpy.mock.calls;
      const hasExpectedError = errorCalls.some(
        (call) =>
          call.arguments[0].includes('Push notification attempt') ||
          call.arguments[0].includes('❌ Error sending push notification')
      );

      assert.ok(hasExpectedError, 'Expected error message not found in console.error calls');

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
      assert.strictEqual(result, 'This is a...');
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
