import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';

// Mock Bonjour class before importing the service
const mockPublish = mock.fn();
const mockUnpublishAll = mock.fn();
const mockDestroy = mock.fn();
const mockServiceOn = mock.fn();

class MockBonjour {
  constructor() {
    this.publish = mockPublish;
    this.unpublishAll = mockUnpublishAll;
    this.destroy = mockDestroy;
  }
}

// Mock the bonjour-service module
await import('node:module').then((module) => {
  const require = module.createRequire(import.meta.url);
  require.cache[require.resolve('bonjour-service')] = {
    exports: { Bonjour: MockBonjour },
  };
});

// Now import the service which will use mocked Bonjour
const { setupBonjour } = await import('../../services/discovery.js');

describe('Discovery Service', () => {
  let originalEnv;
  let mockService;
  let eventListeners;

  beforeEach(() => {
    // Save original env
    originalEnv = { ...process.env };

    // Reset mocks
    mockPublish.mock.resetCalls();
    mockUnpublishAll.mock.resetCalls();
    mockDestroy.mock.resetCalls();
    mockServiceOn.mock.resetCalls();

    // Create mock service with event emitter functionality
    eventListeners = {};
    mockService = {
      fqdn: 'claude-companion._claudecode._tcp.local',
      on: mock.fn((event, handler) => {
        eventListeners[event] = handler;
      }),
      emit: (event, ...args) => {
        if (eventListeners[event]) {
          eventListeners[event](...args);
        }
      },
    };

    // Setup mock publish to return mock service
    mockPublish.mock.mockImplementation(() => mockService);

    // Set test environment
    process.env.NODE_ENV = 'test';
  });

  afterEach(() => {
    // Restore original env
    process.env = originalEnv;
  });

  describe('setupBonjour', () => {
    it('should publish service with correct configuration', () => {
      const port = 8080;
      const service = setupBonjour(port, false);

      assert.strictEqual(mockPublish.mock.calls.length, 1);
      const publishArgs = mockPublish.mock.calls[0].arguments[0];

      assert.strictEqual(publishArgs.name, 'AICLI Companion Server');
      assert.strictEqual(publishArgs.type, 'aiclicode');
      assert.strictEqual(publishArgs.port, port);
      assert.strictEqual(publishArgs.txt.version, '1.0.0');
      assert.strictEqual(publishArgs.txt.features, 'chat,streaming,permissions');
      assert.strictEqual(publishArgs.txt.auth, 'none');
      assert.strictEqual(publishArgs.txt.tls, 'disabled');
      assert.strictEqual(publishArgs.txt.protocol, 'ws');

      assert.strictEqual(service, mockService);
    });

    it('should publish with TLS enabled', () => {
      const port = 8443;
      setupBonjour(port, true);

      const publishArgs = mockPublish.mock.calls[0].arguments[0];
      assert.strictEqual(publishArgs.txt.tls, 'enabled');
      assert.strictEqual(publishArgs.txt.protocol, 'wss');
    });

    it('should publish with auth required when AUTH_TOKEN is set', () => {
      process.env.AUTH_TOKEN = 'test-token';

      setupBonjour(8080, false);

      const publishArgs = mockPublish.mock.calls[0].arguments[0];
      assert.strictEqual(publishArgs.txt.auth, 'required');
    });

    it('should handle service up event', () => {
      const originalLog = console.log;
      const logSpy = mock.fn();
      console.log = logSpy;

      setupBonjour(8080, false);

      // Emit the 'up' event
      mockService.emit('up');

      assert.strictEqual(logSpy.mock.calls.length, 1);
      assert.ok(logSpy.mock.calls[0].arguments[0].includes('Bonjour service published'));
      assert.ok(logSpy.mock.calls[0].arguments[0].includes(mockService.fqdn));

      console.log = originalLog;
    });

    it('should handle service error event', () => {
      const originalError = console.error;
      const errorSpy = mock.fn();
      console.error = errorSpy;

      setupBonjour(8080, false);

      const testError = new Error('Test error');
      mockService.emit('error', testError);

      assert.strictEqual(errorSpy.mock.calls.length, 1);
      assert.ok(errorSpy.mock.calls[0].arguments[0].includes('Bonjour service error'));
      assert.strictEqual(errorSpy.mock.calls[0].arguments[1], testError);

      console.error = originalError;
    });

    it('should not setup signal handlers in test environment', () => {
      const originalOn = process.on;
      const onSpy = mock.fn();
      process.on = onSpy;

      setupBonjour(8080, false);

      // Should not register SIGINT or SIGTERM handlers in test env
      const sigintCalls = onSpy.mock.calls.filter((call) => call.arguments[0] === 'SIGINT');
      const sigtermCalls = onSpy.mock.calls.filter((call) => call.arguments[0] === 'SIGTERM');

      assert.strictEqual(sigintCalls.length, 0);
      assert.strictEqual(sigtermCalls.length, 0);

      process.on = originalOn;
    });

    it('should setup signal handlers in non-test environment', () => {
      process.env.NODE_ENV = 'production';

      const originalOn = process.on;
      const handlers = {};
      process.on = mock.fn((event, handler) => {
        handlers[event] = handler;
      });

      setupBonjour(8080, false);

      // Should register both SIGINT and SIGTERM handlers
      assert.ok(handlers.SIGINT);
      assert.ok(handlers.SIGTERM);

      // Test SIGINT handler
      mockUnpublishAll.mock.mockImplementation((callback) => {
        callback();
      });

      handlers.SIGINT();

      assert.strictEqual(mockUnpublishAll.mock.calls.length, 1);
      assert.strictEqual(mockDestroy.mock.calls.length, 1);

      // Reset and test SIGTERM handler
      mockUnpublishAll.mock.resetCalls();
      mockDestroy.mock.resetCalls();

      handlers.SIGTERM();

      assert.strictEqual(mockUnpublishAll.mock.calls.length, 1);
      assert.strictEqual(mockDestroy.mock.calls.length, 1);

      process.on = originalOn;
    });

    it('should throw error if Bonjour setup fails', () => {
      const originalError = console.error;
      const errorSpy = mock.fn();
      console.error = errorSpy;

      const setupError = new Error('Bonjour setup failed');
      mockPublish.mock.mockImplementation(() => {
        throw setupError;
      });

      assert.throws(() => {
        setupBonjour(8080, false);
      }, setupError);

      assert.strictEqual(errorSpy.mock.calls.length, 1);
      assert.ok(errorSpy.mock.calls[0].arguments[0].includes('Failed to setup Bonjour'));
      assert.strictEqual(errorSpy.mock.calls[0].arguments[1], setupError);

      console.error = originalError;
    });

    it('should return the published service', () => {
      const service = setupBonjour(8080, false);
      assert.strictEqual(service, mockService);
      assert.ok(service.on);
      assert.strictEqual(mockService.on.mock.calls.length, 2); // 'up' and 'error' events
    });

    it('should register both up and error event handlers', () => {
      setupBonjour(8080, false);

      const onCalls = mockService.on.mock.calls;
      const eventTypes = onCalls.map((call) => call.arguments[0]);

      assert.ok(eventTypes.includes('up'));
      assert.ok(eventTypes.includes('error'));
      assert.strictEqual(eventTypes.length, 2);
    });
  });
});
