import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import { APNsClient } from '../../../services/push-notification/apns-client.js';

// Create a mock Provider class
class MockProvider {
  constructor(options) {
    this.options = options;
    this.sent = [];
    this.failed = [];
  }

  async send(notification, deviceToken) {
    // Simulate different responses based on test conditions
    if (this.mockResponse) {
      return this.mockResponse;
    }
    return {
      sent: [{ device: deviceToken }],
      failed: [],
    };
  }

  shutdown() {
    this.isShutdown = true;
  }

  setMockResponse(response) {
    this.mockResponse = response;
  }
}

describe('APNsClient', () => {
  let client;
  let originalEnv;
  let consoleLogSpy;
  let consoleErrorSpy;
  let fsExistsSyncSpy;
  let mockProviderInstance;

  beforeEach(() => {
    client = new APNsClient();
    originalEnv = { ...process.env };

    // Mock console methods
    consoleLogSpy = mock.method(console, 'log', () => {});
    consoleErrorSpy = mock.method(console, 'error', () => {});

    // Mock fs.existsSync to return true by default
    fsExistsSyncSpy = mock.method(fs, 'existsSync', () => true);

    // Mock the APNs Provider
    mockProviderInstance = null;
    mock.method(client.constructor.prototype, 'createProvider', (options) => {
      mockProviderInstance = new MockProvider(options);
      return mockProviderInstance;
    });
  });

  afterEach(() => {
    if (client.provider) {
      client.shutdown();
    }
    process.env = originalEnv;
    mock.restoreAll();
  });

  describe('initialize', () => {
    it('should initialize with config object', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
        production: false,
      };

      // Add the createProvider method
      client.createProvider = (options) => new MockProvider(options);

      client.initialize(config);

      assert.strictEqual(client.isConfigured, true);
      assert.strictEqual(client.bundleId, 'com.test.app');
      assert(client.provider);

      // Check console output
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('Push notification service initialized')
        )
      );
    });

    it('should initialize with environment variables', () => {
      process.env.APNS_KEY_PATH = '/env/key.p8';
      process.env.APNS_KEY_ID = 'ENV_KEY';
      process.env.APNS_TEAM_ID = 'ENV_TEAM';
      process.env.APNS_BUNDLE_ID = 'com.env.app';
      process.env.APNS_PRODUCTION = 'true';

      client.createProvider = (options) => new MockProvider(options);

      client.initialize();

      assert.strictEqual(client.isConfigured, true);
      assert.strictEqual(client.bundleId, 'com.env.app');
      assert(client.provider);

      // Verify production mode
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('Environment: production')
        )
      );
    });

    it('should use production mode when NODE_ENV is production', () => {
      process.env.NODE_ENV = 'production';

      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      client.createProvider = (options) => {
        assert.strictEqual(options.production, true);
        return new MockProvider(options);
      };

      client.initialize(config);

      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('Environment: production')
        )
      );
    });

    it('should log warning when missing required config', () => {
      client.initialize({});

      assert.strictEqual(client.isConfigured, false);
      assert.strictEqual(client.provider, null);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('Push notifications not configured')
        )
      );
    });

    it('should log warning when key file does not exist', () => {
      fsExistsSyncSpy.mock.mockImplementation(() => false);

      const config = {
        keyPath: '/nonexistent/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      client.initialize(config);

      assert.strictEqual(client.isConfigured, false);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('APNs key file not found')
        )
      );
    });

    it('should handle initialization errors', () => {
      // Force an error by making fs.existsSync throw
      fsExistsSyncSpy.mock.mockImplementation(() => {
        throw new Error('File system error');
      });

      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      client.initialize(config);

      assert.strictEqual(client.isConfigured, false);
      assert(
        consoleErrorSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('Failed to initialize push notification service')
        )
      );
    });

    it('should handle missing keyPath', () => {
      const config = {
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      client.initialize(config);

      assert.strictEqual(client.isConfigured, false);
      assert(
        consoleLogSpy.mock.calls.some((call) => call.arguments[0]?.includes('Required env vars'))
      );
    });

    it('should handle missing keyId', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        teamId: 'TEAM456',
      };

      client.initialize(config);

      assert.strictEqual(client.isConfigured, false);
    });

    it('should handle missing teamId', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
      };

      client.initialize(config);

      assert.strictEqual(client.isConfigured, false);
    });

    it('should use development mode by default', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      client.createProvider = (options) => {
        assert.strictEqual(options.production, false);
        return new MockProvider(options);
      };

      client.initialize(config);

      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0]?.includes('Environment: development')
        )
      );
    });
  });

  describe('send', () => {
    beforeEach(() => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
      };
      client.createProvider = (options) => new MockProvider(options);
      client.initialize(config);
      mockProviderInstance = client.provider;
    });

    it('should send notification successfully', async () => {
      const notification = { alert: 'Test' };
      const deviceToken = 'test_token';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, true);
      assert(result.result);
      assert.strictEqual(result.result.sent.length, 1);
    });

    it('should throw error when provider not initialized', async () => {
      const uninitializedClient = new APNsClient();

      await assert.rejects(
        async () => uninitializedClient.send({}, 'token'),
        /APNs provider not initialized/
      );
    });

    it('should handle BadDeviceToken error', async () => {
      mockProviderInstance.setMockResponse({
        sent: [],
        failed: [
          {
            device: 'bad_token',
            response: { reason: 'BadDeviceToken' },
          },
        ],
      });

      const result = await client.send({}, 'bad_token');

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'BadDeviceToken');
    });

    it('should handle ExpiredProviderToken error', async () => {
      mockProviderInstance.setMockResponse({
        sent: [],
        failed: [
          {
            device: 'token',
            response: { reason: 'ExpiredProviderToken' },
          },
        ],
      });

      const result = await client.send({}, 'token');

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'ExpiredProviderToken');
    });

    it('should handle unknown errors', async () => {
      mockProviderInstance.setMockResponse({
        sent: [],
        failed: [
          {
            device: 'token',
            response: { reason: 'SomeOtherError' },
          },
        ],
      });

      const result = await client.send({}, 'token');

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'SomeOtherError');
    });

    it('should handle failures without response reason', async () => {
      mockProviderInstance.setMockResponse({
        sent: [],
        failed: [
          {
            device: 'token',
          },
        ],
      });

      const result = await client.send({}, 'token');

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'Unknown error');
    });

    it('should handle empty results', async () => {
      mockProviderInstance.setMockResponse({
        sent: [],
        failed: [],
      });

      const result = await client.send({}, 'token');

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'No sent or failed results');
    });

    it('should handle multiple failures', async () => {
      mockProviderInstance.setMockResponse({
        sent: [],
        failed: [
          { device: 'token1', response: { reason: 'BadDeviceToken' } },
          { device: 'token2', response: { reason: 'Unregistered' } },
        ],
      });

      const result = await client.send({}, 'token');

      // Should return the first failure
      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'BadDeviceToken');
    });

    it('should handle mixed results', async () => {
      mockProviderInstance.setMockResponse({
        sent: [{ device: 'token1' }],
        failed: [{ device: 'token2', response: { reason: 'BadDeviceToken' } }],
      });

      const result = await client.send({}, 'token');

      // Should be successful if at least one sent
      assert.strictEqual(result.success, true);
    });
  });

  describe('getBundleId', () => {
    it('should return configured bundle ID', () => {
      client.bundleId = 'com.configured.app';
      assert.strictEqual(client.getBundleId(), 'com.configured.app');
    });

    it('should fallback to environment variable', () => {
      process.env.APNS_BUNDLE_ID = 'com.env.app';
      assert.strictEqual(client.getBundleId(), 'com.env.app');
    });

    it('should return default bundle ID', () => {
      delete process.env.APNS_BUNDLE_ID;
      assert.strictEqual(client.getBundleId(), 'com.aiclicompanion.ios');
    });

    it('should prioritize instance bundleId over env', () => {
      client.bundleId = 'com.instance.app';
      process.env.APNS_BUNDLE_ID = 'com.env.app';
      assert.strictEqual(client.getBundleId(), 'com.instance.app');
    });
  });

  describe('shutdown', () => {
    it('should shutdown provider when initialized', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };
      client.createProvider = (options) => new MockProvider(options);
      client.initialize(config);

      client.shutdown();

      assert.strictEqual(client.provider.isShutdown, true);
    });

    it('should handle shutdown when provider not initialized', () => {
      // Should not throw
      assert.doesNotThrow(() => client.shutdown());
    });

    it('should be idempotent', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };
      client.createProvider = (options) => new MockProvider(options);
      client.initialize(config);

      client.shutdown();
      client.shutdown();

      // Should not throw on second shutdown
      assert.strictEqual(client.provider.isShutdown, true);
    });
  });
});
