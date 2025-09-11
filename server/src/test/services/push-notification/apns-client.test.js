import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { APNsClient } from '../../../services/push-notification/apns-client.js';

// Mock the apn module
const mockProvider = {
  send: mock.fn(),
  shutdown: mock.fn(),
};

// Create a proper constructor function for Provider
function MockProvider() {
  return mockProvider;
}

const mockApn = {
  Provider: MockProvider,
};

// Mock the fs module
const mockFs = {
  existsSync: mock.fn(() => true),
};

describe('APNsClient', () => {
  let client;
  let originalEnv;

  beforeEach(() => {
    // Save original env
    originalEnv = { ...process.env };

    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'error', () => {});

    // Reset mocks
    mockProvider.send.mock.resetCalls();
    mockProvider.shutdown.mock.resetCalls();
    mockFs.existsSync.mock.resetCalls();

    // Reset mockFs.existsSync to return true by default
    mockFs.existsSync.mock.mockImplementation(() => true);

    // Track Provider calls
    mockApn.providerCalls = [];
    mockApn.Provider = function (options) {
      mockApn.providerCalls.push(options);
      return mockProvider;
    };

    // Create a new client with mocked apn and fs modules
    client = new APNsClient(mockApn, mockFs);
  });

  afterEach(() => {
    mock.restoreAll();
    // Restore original env
    Object.keys(process.env).forEach((key) => {
      if (!(key in originalEnv)) {
        delete process.env[key];
      }
    });
    Object.assign(process.env, originalEnv);
  });

  describe('initialize', () => {
    it('should initialize with config object', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
        production: true,
      };

      client.initialize(config);

      // Verify initialization was successful
      assert.strictEqual(client.bundleId, 'com.test.app');
      assert.strictEqual(client.isConfigured, true);
      assert.strictEqual(client.provider, mockProvider);
      assert.strictEqual(mockApn.providerCalls.length, 1);

      // Verify Provider was called with correct options
      assert.deepStrictEqual(mockApn.providerCalls[0], {
        token: {
          key: '/path/to/key.p8',
          keyId: 'KEY123',
          teamId: 'TEAM456',
        },
        production: true,
      });
    });

    it('should initialize with environment variables', () => {
      process.env.APNS_KEY_PATH = '/env/key.p8';
      process.env.APNS_KEY_ID = 'ENVKEY';
      process.env.APNS_TEAM_ID = 'ENVTEAM';
      process.env.APNS_BUNDLE_ID = 'com.env.app';
      process.env.APNS_PRODUCTION = 'true';

      client.initialize();

      // Verify initialization was successful
      assert.strictEqual(client.bundleId, 'com.env.app');
      assert.strictEqual(client.isConfigured, true);
      assert.strictEqual(client.provider, mockProvider);
    });

    it('should handle missing configuration', () => {
      // Clear environment variables
      delete process.env.APNS_KEY_PATH;
      delete process.env.APNS_KEY_ID;
      delete process.env.APNS_TEAM_ID;

      client.initialize();

      assert.strictEqual(client.isConfigured, false);
      assert.strictEqual(client.provider, null);
    });

    it('should handle missing key file', () => {
      // Override the fs mock for this test
      mockFs.existsSync.mock.mockImplementation(() => false);

      const config = {
        keyPath: '/nonexistent/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
      };

      client.initialize(config);

      // Should not initialize provider when file doesn't exist
      assert.strictEqual(client.isConfigured, false);
      assert.strictEqual(client.provider, null);
      // But bundleId should not be set since we return early
      assert.strictEqual(client.bundleId, null);
    });

    it('should handle initialization errors gracefully', () => {
      // Make Provider throw an error
      mockApn.Provider = function () {
        throw new Error('Provider creation failed');
      };

      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
      };

      // The initialize method catches errors
      assert.doesNotThrow(() => {
        client.initialize(config);
      });

      // Verify it didn't configure when error occurred
      assert.strictEqual(client.isConfigured, false);
      assert.strictEqual(client.provider, null);
      assert.strictEqual(client.bundleId, null);
    });

    it('should set production mode from NODE_ENV', () => {
      process.env.NODE_ENV = 'production';
      process.env.APNS_KEY_PATH = '/env/key.p8';
      process.env.APNS_KEY_ID = 'ENVKEY';
      process.env.APNS_TEAM_ID = 'ENVTEAM';
      process.env.APNS_BUNDLE_ID = 'com.prod.app';

      client.initialize();

      assert.strictEqual(client.bundleId, 'com.prod.app');
      assert.strictEqual(client.isConfigured, true);

      // Verify production mode was set
      assert.strictEqual(mockApn.providerCalls[0].production, true);
    });

    it('should prefer config.production over NODE_ENV', () => {
      process.env.NODE_ENV = 'production';

      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
        production: false, // Explicitly set to false
      };

      client.initialize(config);

      // Verify initialization was successful
      assert.strictEqual(client.bundleId, 'com.test.app');
      assert.strictEqual(client.isConfigured, true);

      // Verify production was set to false despite NODE_ENV
      assert.strictEqual(mockApn.providerCalls[0].production, false);
    });
  });

  describe('send', () => {
    beforeEach(() => {
      // Set up a mock provider
      client.provider = mockProvider;
      client.isConfigured = true;
    });

    it('should send notification successfully', async () => {
      mockProvider.send.mock.mockImplementation(() =>
        Promise.resolve({ sent: ['device1'], failed: [] })
      );

      const notification = { alert: 'Test' };
      const deviceToken = 'device123';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, true);
      assert(result.result);
      assert.strictEqual(mockProvider.send.mock.callCount(), 1);
    });

    it('should handle BadDeviceToken error', async () => {
      mockProvider.send.mock.mockImplementation(() =>
        Promise.resolve({
          sent: [],
          failed: [{ response: { reason: 'BadDeviceToken' } }],
        })
      );

      const notification = { alert: 'Test' };
      const deviceToken = 'badtoken';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'BadDeviceToken');
    });

    it('should handle ExpiredProviderToken error', async () => {
      mockProvider.send.mock.mockImplementation(() =>
        Promise.resolve({
          sent: [],
          failed: [{ response: { reason: 'ExpiredProviderToken' } }],
        })
      );

      const notification = { alert: 'Test' };
      const deviceToken = 'device123';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'ExpiredProviderToken');
    });

    it('should handle generic error', async () => {
      mockProvider.send.mock.mockImplementation(() =>
        Promise.resolve({
          sent: [],
          failed: [{ response: { reason: 'GenericError' } }],
        })
      );

      const notification = { alert: 'Test' };
      const deviceToken = 'device123';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'GenericError');
    });

    it('should handle no results', async () => {
      mockProvider.send.mock.mockImplementation(() => Promise.resolve({ sent: [], failed: [] }));

      const notification = { alert: 'Test' };
      const deviceToken = 'device123';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'No sent or failed results');
    });

    it('should throw error if provider not initialized', async () => {
      client.provider = null;

      await assert.rejects(
        async () => {
          await client.send({}, 'token');
        },
        {
          message: 'APNs provider not initialized',
        }
      );
    });

    it('should handle failed without response', async () => {
      mockProvider.send.mock.mockImplementation(() =>
        Promise.resolve({
          sent: [],
          failed: [{}], // No response property
        })
      );

      const notification = { alert: 'Test' };
      const deviceToken = 'device123';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'Unknown error');
    });
  });

  describe('getBundleId', () => {
    it('should return configured bundle ID', () => {
      client.bundleId = 'com.configured.app';

      const bundleId = client.getBundleId();

      assert.strictEqual(bundleId, 'com.configured.app');
    });

    it('should return environment bundle ID', () => {
      process.env.APNS_BUNDLE_ID = 'com.env.app';
      client.bundleId = null;

      const bundleId = client.getBundleId();

      assert.strictEqual(bundleId, 'com.env.app');
    });

    it('should return default bundle ID', () => {
      delete process.env.APNS_BUNDLE_ID;
      client.bundleId = null;

      const bundleId = client.getBundleId();

      assert.strictEqual(bundleId, 'com.aiclicompanion.ios');
    });
  });

  describe('shutdown', () => {
    it('should shutdown provider', () => {
      client.provider = mockProvider;

      client.shutdown();

      assert.strictEqual(mockProvider.shutdown.mock.callCount(), 1);
    });

    it('should handle shutdown without provider', () => {
      client.provider = null;

      assert.doesNotThrow(() => {
        client.shutdown();
      });
    });
  });
});
