import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
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
      const port = 3001;
      const enableTLS = false;
      const enableBonjour = true;

      // Should handle the setupBonjour call (may succeed or fail gracefully)
      assert.doesNotThrow(() => {
        ServerStartup.setupServiceDiscovery(port, enableTLS, enableBonjour);
      });
    });
  });

  describe('displayStartupInfo', () => {
    let mockConfig;

    beforeEach(() => {
      mockConfig = {
        getProtocol: mock.fn(() => 'http'),
        getWSProtocol: mock.fn(() => 'ws'),
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
      assert.strictEqual(mockConfig.getWSProtocol.mock.calls.length, 1);
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
      const authDisabledMessages = logCalls.filter(
        (msg) => msg.includes('Authentication disabled')
      );
      const mobileAppMessages = logCalls.filter(
        (msg) => msg.includes('Mobile app connection') && !msg.includes('token=')
      );
      
      assert.strictEqual(authDisabledMessages.length, 1, 'Should display auth disabled message');
      assert.strictEqual(mobileAppMessages.length, 1, 'Should display mobile app connection without token');
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

    it('should display Claude availability', () => {
      const authToken = 'test-token';
      const claudeAvailable = true;
      const fingerprint = null;

      ServerStartup.displayStartupInfo(mockConfig, authToken, claudeAvailable, fingerprint);

      // Should log Claude status
      const logCalls = console.log.mock.calls.map((call) => call.arguments[0]);
      const claudeMessages = logCalls.filter((msg) => msg.includes('Claude Code'));
      assert.ok(claudeMessages.length > 0, 'Should display Claude status');
    });
  });

  describe('checkClaudeAvailability', () => {
    let mockClaudeService;

    beforeEach(() => {
      mockClaudeService = {
        checkAvailability: mock.fn(),
      };
    });

    it('should return true when Claude is available', async () => {
      mockClaudeService.checkAvailability.mock.mockImplementation(() => Promise.resolve(true));

      const result = await ServerStartup.checkClaudeAvailability(mockClaudeService);

      assert.strictEqual(result, true);
      assert.strictEqual(mockClaudeService.checkAvailability.mock.calls.length, 1);
    });

    it('should return false and log warning when Claude not available', async () => {
      mockClaudeService.checkAvailability.mock.mockImplementation(() => Promise.resolve(false));

      const result = await ServerStartup.checkClaudeAvailability(mockClaudeService);

      assert.strictEqual(result, false);
      assert.strictEqual(mockClaudeService.checkAvailability.mock.calls.length, 1);

      // Should log warning messages
      assert.ok(console.warn.mock.calls.length >= 2);
    });

    it('should handle checkAvailability errors', async () => {
      mockClaudeService.checkAvailability.mock.mockImplementation(() =>
        Promise.reject(new Error('Test error'))
      );

      // This should throw because the actual implementation doesn't catch errors
      await assert.rejects(
        () => ServerStartup.checkClaudeAvailability(mockClaudeService),
        /Test error/
      );

      assert.strictEqual(mockClaudeService.checkAvailability.mock.calls.length, 1);
    });
  });
});
