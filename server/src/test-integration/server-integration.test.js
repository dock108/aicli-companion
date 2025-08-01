import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';

// Mock all external dependencies before importing
const mockExpress = () => {
  const app = {
    use: mock.fn(),
    get: mock.fn(),
    post: mock.fn(),
    _router: {
      stack: [
        {
          route: { path: '/health', methods: { get: true } },
        },
        {
          route: { path: '/', methods: { get: true } },
        },
      ],
    },
  };
  return app;
};

// Mock modules
mock.method(await import('express'), 'default', mockExpress);
mock.method(await import('http'), 'createServer', () => ({
  listen: mock.fn(),
  close: mock.fn(),
}));
mock.method(await import('ws'), 'WebSocketServer', function () {
  this.on = mock.fn();
  this.close = mock.fn();
});

import { ClaudeCompanionServer } from '../index.js';

// Mock process methods to prevent actual exit
const originalExit = process.exit;
const originalProcessOn = process.on;

describe('Server Unit Tests', () => {
  let server;
  let exitSpy;
  let processOnSpy;

  beforeEach(() => {
    // Mock process.exit to prevent actual exit
    exitSpy = mock.fn();
    process.exit = exitSpy;

    // Mock process.on to prevent adding actual listeners
    processOnSpy = mock.fn();
    process.on = processOnSpy;

    // Mock console methods to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');
  });

  afterEach(() => {
    // Restore original functions
    process.exit = originalExit;
    process.on = originalProcessOn;

    // Clean up server reference (no need to close mocked server)
    server = null;

    // Restore mocks
    mock.restoreAll();
  });

  describe('Server Construction', () => {
    it('should create server instance with default configuration', () => {
      server = new ClaudeCompanionServer();

      assert.ok(server.app, 'Server should have Express app');
      assert.ok(server.config, 'Server should have configuration');
      assert.ok(server.claudeService, 'Server should have Claude service');
      assert.ok(server.tlsConfig, 'Server should have TLS config');
      assert.strictEqual(server.server, null, 'HTTP server should not be created yet');
      assert.strictEqual(server.wss, null, 'WebSocket server should not be created yet');
    });

    it('should set up process event listeners', () => {
      server = new ClaudeCompanionServer();

      // Verify that process.on was called for error handling
      const calls = processOnSpy.mock.calls;
      const eventTypes = calls.map((call) => call.arguments[0]);

      assert.ok(eventTypes.includes('uncaughtException'), 'Should listen for uncaughtException');
      assert.ok(eventTypes.includes('unhandledRejection'), 'Should listen for unhandledRejection');
      assert.ok(eventTypes.includes('SIGTERM'), 'Should listen for SIGTERM');
      assert.ok(eventTypes.includes('SIGINT'), 'Should listen for SIGINT');
    });
  });

  describe('Route Setup', () => {
    beforeEach(() => {
      server = new ClaudeCompanionServer();
    });

    it('should have health check endpoint', () => {
      // Access the Express app's router stack
      const routes = server.app._router.stack;
      const healthRoute = routes.find((layer) => layer.route && layer.route.path === '/health');

      assert.ok(healthRoute, 'Health check route should exist');
      assert.strictEqual(healthRoute.route.methods.get, true, 'Health check should accept GET');
    });

    it('should have root endpoint', () => {
      const routes = server.app._router.stack;
      const rootRoute = routes.find((layer) => layer.route && layer.route.path === '/');

      assert.ok(rootRoute, 'Root route should exist');
      assert.strictEqual(rootRoute.route.methods.get, true, 'Root should accept GET');
    });
  });

  describe('Configuration Integration', () => {
    it('should use configuration values in health endpoint', async () => {
      server = new ClaudeCompanionServer();

      // Mock request and response
      const req = {};
      const res = {
        json: mock.fn(),
      };

      // Find and call the health route handler
      const routes = server.app._router.stack;
      const healthRoute = routes.find((layer) => layer.route && layer.route.path === '/health');

      const handler = healthRoute.route.stack[0].handle;
      handler(req, res);

      // Verify response structure
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.status, 'healthy');
      assert.strictEqual(response.version, server.config.version);
      assert.ok(response.timestamp);
      assert.ok(typeof response.claudeCodeAvailable === 'boolean');
    });

    it('should use configuration values in root endpoint', async () => {
      server = new ClaudeCompanionServer();

      const req = {};
      const res = {
        json: mock.fn(),
      };

      // Find and call the root route handler
      const routes = server.app._router.stack;
      const rootRoute = routes.find((layer) => layer.route && layer.route.path === '/');

      const handler = rootRoute.route.stack[0].handle;
      handler(req, res);

      // Verify response structure
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.name, 'Claude Companion Server');
      assert.strictEqual(response.version, server.config.version);
      assert.strictEqual(response.status, 'running');
      assert.ok(response.endpoints);
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      server = new ClaudeCompanionServer();
    });

    it('should handle uncaught exceptions', () => {
      // Mock server.shutdown
      server.shutdown = mock.fn();

      // Find the uncaughtException handler
      const calls = processOnSpy.mock.calls;
      const uncaughtCall = calls.find((call) => call.arguments[0] === 'uncaughtException');
      assert.ok(uncaughtCall, 'Should have uncaughtException handler');

      const handler = uncaughtCall.arguments[1];
      const testError = new Error('Test uncaught exception');

      // Call the handler
      handler(testError);

      // Verify shutdown was called
      assert.strictEqual(server.shutdown.mock.calls.length, 1);
    });

    it('should handle unhandled rejections', () => {
      // Find the unhandledRejection handler
      const calls = processOnSpy.mock.calls;
      const rejectionCall = calls.find((call) => call.arguments[0] === 'unhandledRejection');
      assert.ok(rejectionCall, 'Should have unhandledRejection handler');

      const handler = rejectionCall.arguments[1];

      // Call the handler (should not throw)
      assert.doesNotThrow(() => {
        handler('Test rejection', Promise.resolve());
      });
    });

    it('should handle SIGTERM', () => {
      server.shutdown = mock.fn();

      const calls = processOnSpy.mock.calls;
      const sigtermCall = calls.find((call) => call.arguments[0] === 'SIGTERM');
      assert.ok(sigtermCall, 'Should have SIGTERM handler');

      const handler = sigtermCall.arguments[1];
      handler();

      assert.strictEqual(server.shutdown.mock.calls.length, 1);
    });

    it('should handle SIGINT', () => {
      server.shutdown = mock.fn();

      const calls = processOnSpy.mock.calls;
      const sigintCall = calls.find((call) => call.arguments[0] === 'SIGINT');
      assert.ok(sigintCall, 'Should have SIGINT handler');

      const handler = sigintCall.arguments[1];
      handler();

      assert.strictEqual(server.shutdown.mock.calls.length, 1);
    });
  });

  describe('Shutdown Process', () => {
    beforeEach(() => {
      server = new ClaudeCompanionServer();
    });

    it('should shutdown gracefully when server exists', () => {
      // Mock server
      const mockServer = {
        close: mock.fn((callback) => callback()),
      };
      server.server = mockServer;

      // Mock setTimeout to prevent actual delay
      const originalSetTimeout = global.setTimeout;
      global.setTimeout = mock.fn();

      try {
        server.shutdown();

        // Verify server.close was called
        assert.strictEqual(mockServer.close.mock.calls.length, 1);

        // Verify process.exit was called
        assert.strictEqual(exitSpy.mock.calls.length, 1);
        assert.strictEqual(exitSpy.mock.calls[0].arguments[0], 0);
      } finally {
        // Always restore setTimeout
        global.setTimeout = originalSetTimeout;
      }
    });

    it('should set force shutdown timeout', () => {
      const mockServer = {
        close: mock.fn(() => {}), // Don't call callback to test timeout
      };
      server.server = mockServer;

      const originalSetTimeout = global.setTimeout;
      const timeoutSpy = mock.fn();
      global.setTimeout = timeoutSpy;

      try {
        server.shutdown();

        // Verify timeout was set
        assert.strictEqual(timeoutSpy.mock.calls.length, 1);
        assert.strictEqual(timeoutSpy.mock.calls[0].arguments[1], 10000); // 10 seconds
      } finally {
        // Always restore setTimeout
        global.setTimeout = originalSetTimeout;
      }
    });
  });

  describe('WebSocket Setup', () => {
    beforeEach(() => {
      server = new ClaudeCompanionServer();
    });

    it('should set up WebSocket when server exists', () => {
      // Mock HTTP server
      const mockServer = {
        listen: mock.fn(),
        close: mock.fn(),
      };
      server.server = mockServer;

      server.setupWebSocket();

      assert.ok(server.wss, 'WebSocket server should be created');
    });
  });
});
