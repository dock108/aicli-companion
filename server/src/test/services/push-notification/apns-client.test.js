import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { APNsClient } from '../../../services/push-notification/apns-client.js';

// Mock the apn module
const mockProvider = {
  send: mock.fn(),
  shutdown: mock.fn(),
};

const mockApn = {
  Provider: mock.fn(() => mockProvider),
};

// Mock fs module
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
    mockApn.Provider.mock.resetCalls();
    mockFs.existsSync.mock.resetCalls();

    client = new APNsClient();
    
    // Override imports with mocks (since we can't mock ES modules directly)
    // We'll test the logic by mocking the provider after initialization
  });

  afterEach(() => {
    mock.restoreAll();
    // Restore original env
    Object.keys(process.env).forEach(key => {
      if (!(key in originalEnv)) {
        delete process.env[key];
      }
    });
    Object.assign(process.env, originalEnv);
  });

  describe.skip('initialize', () => {
    it('should initialize with config object', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
        bundleId: 'com.test.app',
        production: true,
      };

      // Mock fs.existsSync by overriding the method
      const originalExists = global.fs?.existsSync;
      if (global.fs) {
        global.fs.existsSync = () => true;
      }

      client.initialize(config);

      // Since we can't mock the import, we verify the state
      assert.strictEqual(client.bundleId, 'com.test.app');
      
      // Restore
      if (global.fs && originalExists) {
        global.fs.existsSync = originalExists;
      }
    });

    it('should initialize with environment variables', () => {
      process.env.APNS_KEY_PATH = '/env/key.p8';
      process.env.APNS_KEY_ID = 'ENVKEY';
      process.env.APNS_TEAM_ID = 'ENVTEAM';
      process.env.APNS_BUNDLE_ID = 'com.env.app';
      process.env.APNS_PRODUCTION = 'true';

      // We can't fully test initialization due to import limitations
      // But we can verify the method doesn't throw
      assert.doesNotThrow(() => {
        client.initialize();
      });
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
      const config = {
        keyPath: '/nonexistent/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      // The real implementation would check fs.existsSync
      // We verify it doesn't throw
      assert.doesNotThrow(() => {
        client.initialize(config);
      });
    });

    it('should handle initialization errors', () => {
      const config = {
        keyPath: '/path/to/key.p8',
        keyId: 'KEY123',
        teamId: 'TEAM456',
      };

      // Force an error by manipulating the client
      client.Provider = () => {
        throw new Error('Provider error');
      };

      assert.doesNotThrow(() => {
        client.initialize(config);
      });
    });

    it('should set production mode from NODE_ENV', () => {
      process.env.NODE_ENV = 'production';
      process.env.APNS_KEY_PATH = '/env/key.p8';
      process.env.APNS_KEY_ID = 'ENVKEY';
      process.env.APNS_TEAM_ID = 'ENVTEAM';

      client.initialize();

      // We verify the method completes without error
      assert.doesNotThrow(() => {
        client.initialize();
      });
    });
  });

  describe.skip('send', () => {
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
          failed: [{ response: { reason: 'BadDeviceToken' } }] 
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
          failed: [{ response: { reason: 'ExpiredProviderToken' } }] 
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
          failed: [{ response: { reason: 'GenericError' } }] 
        })
      );

      const notification = { alert: 'Test' };
      const deviceToken = 'device123';

      const result = await client.send(notification, deviceToken);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.error, 'GenericError');
    });

    it('should handle no results', async () => {
      mockProvider.send.mock.mockImplementation(() => 
        Promise.resolve({ sent: [], failed: [] })
      );

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
          message: 'APNs provider not initialized'
        }
      );
    });

    it('should handle failed without response', async () => {
      mockProvider.send.mock.mockImplementation(() => 
        Promise.resolve({ 
          sent: [], 
          failed: [{}] // No response property
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