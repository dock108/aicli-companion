import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { MiddlewareConfig } from '../../config/middleware-config.js';
import { ServerConfig } from '../../config/server-config.js';

describe('MiddlewareConfig', () => {
  let mockApp;
  let mockConfig;

  beforeEach(() => {
    // Mock Express app
    mockApp = {
      use: mock.fn(),
      set: mock.fn(), // Add set method for trust proxy setting
    };

    // Mock server config
    mockConfig = {
      getHelmetConfig: mock.fn(() => ({ contentSecurityPolicy: false })),
      getCorsConfig: mock.fn(() => ({ origin: ['*'], credentials: true })),
      isTest: mock.fn(() => false),
      authToken: 'test-token',
      isInternetExposed: false, // Add missing property for configureSecurity
    };
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('configure', () => {
    it('should configure all middleware in correct order', () => {
      MiddlewareConfig.configure(mockApp, mockConfig);

      // Verify app.use was called multiple times
      assert.ok(mockApp.use.mock.calls.length >= 4, 'Should call app.use multiple times');

      // Verify config methods were called
      assert.strictEqual(mockConfig.getHelmetConfig.mock.calls.length, 1);
      assert.strictEqual(mockConfig.getCorsConfig.mock.calls.length, 1);
      assert.strictEqual(mockConfig.isTest.mock.calls.length, 1);
    });

    it('should skip morgan logging in test environment', () => {
      mockConfig.isTest = mock.fn(() => true);

      MiddlewareConfig.configure(mockApp, mockConfig);

      assert.strictEqual(mockConfig.isTest.mock.calls.length, 1);
      // In test mode, morgan should not be added
      const morganCalls = mockApp.use.mock.calls.filter(
        (call) => call.arguments[0] && call.arguments[0].name === 'logger'
      );
      assert.strictEqual(morganCalls.length, 0, 'Morgan should not be used in test mode');
    });

    it('should include morgan logging in non-test environment', () => {
      mockConfig.isTest = mock.fn(() => false);

      MiddlewareConfig.configure(mockApp, mockConfig);

      assert.strictEqual(mockConfig.isTest.mock.calls.length, 1);
      // Should have at least helmet, cors, morgan, and body parsers
      assert.ok(mockApp.use.mock.calls.length >= 4);
    });
  });

  describe('configureAuth', () => {
    it('should configure auth middleware when token provided', () => {
      const authToken = 'test-auth-token';

      MiddlewareConfig.configureAuth(mockApp, authToken);

      // Should call app.use for auth middleware
      assert.strictEqual(mockApp.use.mock.calls.length, 1);

      const call = mockApp.use.mock.calls[0];
      assert.strictEqual(call.arguments[0], '/api', 'Should mount auth on /api path');
      assert.ok(typeof call.arguments[1] === 'function', 'Should provide middleware function');
    });

    it('should not configure auth middleware when no token', () => {
      MiddlewareConfig.configureAuth(mockApp, null);

      assert.strictEqual(
        mockApp.use.mock.calls.length,
        0,
        'Should not add middleware without token'
      );
    });

    it('should not configure auth middleware when empty token', () => {
      MiddlewareConfig.configureAuth(mockApp, '');

      assert.strictEqual(
        mockApp.use.mock.calls.length,
        0,
        'Should not add middleware with empty token'
      );
    });
  });

  describe('integration with real ServerConfig', () => {
    it('should work with actual ServerConfig instance', () => {
      const realConfig = new ServerConfig();

      // Should not throw
      assert.doesNotThrow(() => {
        MiddlewareConfig.configure(mockApp, realConfig);
      });

      // Verify some middleware was configured
      assert.ok(mockApp.use.mock.calls.length > 0);
    });
  });
});
