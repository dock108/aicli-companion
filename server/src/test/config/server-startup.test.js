import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';

// Disable Bonjour for all tests to prevent network conflicts
process.env.ENABLE_BONJOUR = 'false';

import { ServerStartup } from '../../config/server-startup.js';

describe('ServerStartup', () => {
  beforeEach(() => {
    // Mock console to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('generateAuthToken', () => {
    it('should return existing token when provided', () => {
      const existingToken = 'existing-test-token';
      const result = ServerStartup.generateAuthToken(existingToken, true);

      assert.strictEqual(result, existingToken);
    });

    it('should generate new token when not provided', () => {
      const result = ServerStartup.generateAuthToken(null, true);

      assert.ok(result, 'Should generate a token');
      assert.ok(typeof result === 'string', 'Token should be a string');
      assert.ok(result.length > 0, 'Token should not be empty');

      // Verify console.log was called to announce the token
      assert.ok(console.log.mock.calls.length > 0);
    });

    it('should generate new token when empty string provided', () => {
      const result = ServerStartup.generateAuthToken('', true);

      assert.ok(result, 'Should generate a token');
      assert.ok(typeof result === 'string', 'Token should be a string');
      assert.ok(result.length > 0, 'Token should not be empty');
    });

    it('should generate different tokens on multiple calls', () => {
      const token1 = ServerStartup.generateAuthToken(null, true);
      const token2 = ServerStartup.generateAuthToken(null, true);

      assert.notStrictEqual(token1, token2, 'Should generate unique tokens');
    });
  });

  describe('setupServiceDiscovery', () => {
    it('should not call setupBonjour when disabled', () => {
      const port = 3001;
      const enableTLS = false;
      const enableBonjour = false;

      // This should not throw and should complete without error
      assert.doesNotThrow(() => {
        ServerStartup.setupServiceDiscovery(port, enableTLS, enableBonjour);
      });
    });

    it('should handle setupBonjour call when enabled', () => {
      // Temporarily enable Bonjour for this test
      const originalEnv = process.env.ENABLE_BONJOUR;
      process.env.ENABLE_BONJOUR = 'true';

      const port = 3001;
      const enableTLS = false;
      const enableBonjour = true;

      // Should handle the setupBonjour call (may succeed or fail gracefully)
      assert.doesNotThrow(() => {
        ServerStartup.setupServiceDiscovery(port, enableTLS, enableBonjour);
      });

      // Restore original setting
      process.env.ENABLE_BONJOUR = originalEnv;
    });
  });

  describe('displayStartupInfo', () => {
    let mockConfig;

    beforeEach(() => {
      mockConfig = {
        getProtocol: mock.fn(() => 'http'),
        getDisplayHostname: mock.fn(() => 'localhost'),
        port: 3001,
        enableTLS: false,
      };
    });

    it('should display basic server info', () => {
      const authToken = 'test-token';
      const claudeAvailable = true;
      const fingerprint = null;

      ServerStartup.displayStartupInfo(mockConfig, authToken, claudeAvailable, fingerprint);

      // Verify config methods were called
      assert.strictEqual(mockConfig.getProtocol.mock.calls.length, 1);
      assert.strictEqual(mockConfig.getDisplayHostname.mock.calls.length, 1);

      // Verify console.log was called multiple times
      assert.ok(console.log.mock.calls.length >= 3);
    });

    it('should display auth info when token provided', () => {
      const authToken = 'test-token';
      const claudeAvailable = true;
      const fingerprint = null;

      ServerStartup.displayStartupInfo(mockConfig, authToken, claudeAvailable, fingerprint);

      // Should log auth-related messages
      const logCalls = console.log.mock.calls.map((call) => call.arguments[0]);
      const authMessages = logCalls.filter(
        (msg) => msg.includes('Authentication') || msg.includes('Mobile app')
      );
      assert.ok(authMessages.length > 0, 'Should display auth information');
    });

    it('should display auth disabled when no token', () => {
      const authToken = null;
      const claudeAvailable = true;
      const fingerprint = null;

      ServerStartup.displayStartupInfo(mockConfig, authToken, claudeAvailable, fingerprint);

      // Should log that auth is disabled and show mobile app connection without token
      const logCalls = console.log.mock.calls.map((call) => call.arguments[0]);
      const authDisabledMessages = logCalls.filter((msg) =>
        msg.includes('Authentication disabled')
      );
      const mobileAppMessages = logCalls.filter(
        (msg) => msg.includes('Mobile app connection') && !msg.includes('token=')
      );

      assert.strictEqual(authDisabledMessages.length, 1, 'Should display auth disabled message');
      assert.strictEqual(
        mobileAppMessages.length,
        1,
        'Should display mobile app connection without token'
      );
    });

    it('should display TLS info when enabled', () => {
      mockConfig.enableTLS = true;
      const authToken = 'test-token';
      const claudeAvailable = true;
      const fingerprint = 'test-fingerprint';

      ServerStartup.displayStartupInfo(mockConfig, authToken, claudeAvailable, fingerprint);

      // Should log TLS-related messages
      const logCalls = console.log.mock.calls.map((call) => call.arguments[0]);
      const tlsMessages = logCalls.filter(
        (msg) => msg.includes('TLS') || msg.includes('Certificate')
      );
      assert.ok(tlsMessages.length > 0, 'Should display TLS information');
    });

    it('should display AICLI availability', () => {
      const authToken = 'test-token';
      const aicliAvailable = true;
      const fingerprint = null;

      ServerStartup.displayStartupInfo(mockConfig, authToken, aicliAvailable, fingerprint);

      // Should log AICLI status
      const logCalls = console.log.mock.calls.map((call) => call.arguments[0]);
      const aicliMessages = logCalls.filter((msg) => msg.includes('AICLI Code CLI detected'));
      assert.ok(aicliMessages.length > 0, 'Should display AICLI status');
    });
  });

  describe('checkAICLIAvailability', () => {
    let mockAICLIService;

    beforeEach(() => {
      mockAICLIService = {
        checkAvailability: mock.fn(),
      };
    });

    it('should return true when AICLI is available', async () => {
      mockAICLIService.checkAvailability.mock.mockImplementation(() => Promise.resolve(true));

      const result = await ServerStartup.checkAICLIAvailability(mockAICLIService);

      assert.strictEqual(result, true);
      assert.strictEqual(mockAICLIService.checkAvailability.mock.calls.length, 1);
    });

    it('should return false and log warning when AICLI not available', async () => {
      mockAICLIService.checkAvailability.mock.mockImplementation(() => Promise.resolve(false));

      const result = await ServerStartup.checkAICLIAvailability(mockAICLIService);

      assert.strictEqual(result, false);
      assert.strictEqual(mockAICLIService.checkAvailability.mock.calls.length, 1);

      // Should log warning messages
      assert.ok(console.warn.mock.calls.length >= 2);
    });

    it('should handle checkAvailability errors', async () => {
      mockAICLIService.checkAvailability.mock.mockImplementation(() =>
        Promise.reject(new Error('Test error'))
      );

      // This should throw because the actual implementation doesn't catch errors
      await assert.rejects(
        () => ServerStartup.checkAICLIAvailability(mockAICLIService),
        /Test error/
      );

      assert.strictEqual(mockAICLIService.checkAvailability.mock.calls.length, 1);
    });
  });
});
