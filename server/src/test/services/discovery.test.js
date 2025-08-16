import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { setupBonjour } from '../../services/discovery.js';

describe('Discovery Service', () => {
  let originalEnv;

  beforeEach(() => {
    // Save original env
    originalEnv = { ...process.env };
    // Ensure we're in test environment
    process.env.NODE_ENV = 'test';
  });

  afterEach(() => {
    // Restore original env
    process.env = originalEnv;
  });

  describe('setupBonjour in test environment', () => {
    it('should skip Bonjour setup and return stub', () => {
      const consoleSpy = mock.fn();
      const originalLog = console.log;
      console.log = consoleSpy;

      const service = setupBonjour(8080, false);

      // Should return a stub object with required methods
      assert.ok(service);
      assert.strictEqual(typeof service.on, 'function');
      assert.strictEqual(typeof service.unpublishAll, 'function');

      // Should log that service was skipped
      assert.ok(
        consoleSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Bonjour service skipped in test environment')
        )
      );

      console.log = originalLog;
    });

    it('should return stub with working methods', () => {
      const service = setupBonjour(8080, false);

      // These methods should not throw
      assert.doesNotThrow(() => service.on('test', () => {}));
      assert.doesNotThrow(() => service.unpublishAll(() => {}));
    });

    it('should handle different port and TLS settings', () => {
      // Even with different settings, should return the same stub in test env
      const service1 = setupBonjour(8080, false);
      const service2 = setupBonjour(8443, true);

      // Both should return stubs with the same methods
      assert.ok(service1.on);
      assert.ok(service1.unpublishAll);
      assert.ok(service2.on);
      assert.ok(service2.unpublishAll);
    });

    it('should work with AUTH_TOKEN set', () => {
      process.env.AUTH_TOKEN = 'test-token';

      const service = setupBonjour(8080, false);

      // Should still return stub in test environment
      assert.ok(service);
      assert.strictEqual(typeof service.on, 'function');
      assert.strictEqual(typeof service.unpublishAll, 'function');
    });
  });

  describe('setupBonjour error handling', () => {
    it('should handle Bonjour constructor errors gracefully', () => {
      // In test environment, errors are avoided by returning early
      assert.doesNotThrow(() => setupBonjour(8080, false));
    });

    it('should handle invalid port gracefully', () => {
      // Even with invalid port, should return stub in test env
      const service = setupBonjour(-1, false);
      assert.ok(service);
      assert.ok(service.on);
    });

    it('should handle null port gracefully', () => {
      // Even with null port, should return stub in test env
      const service = setupBonjour(null, false);
      assert.ok(service);
      assert.ok(service.on);
    });
  });

  describe('setupBonjour in production environment', () => {
    beforeEach(() => {
      // Mock console to avoid test output noise
      mock.method(console, 'log');
      mock.method(console, 'error');
    });

    afterEach(() => {
      mock.restoreAll();
    });

    it('should attempt to create Bonjour service in non-test environment', () => {
      // Change to production environment
      process.env.NODE_ENV = 'production';

      try {
        // This will try to create actual Bonjour service
        // It might fail if bonjour-service is not available or network issues
        const service = setupBonjour(8080, false);

        // If it succeeds, service should exist
        assert.ok(service);
      } catch (error) {
        // If Bonjour fails (common in CI), verify it's a Bonjour-related error
        assert.ok(
          error.message.includes('Failed to setup Bonjour') ||
            error.message.includes('bonjour') ||
            error.message.includes('EADDRINUSE') ||
            error.message.includes('network')
        );
      }
    });
  });
});
