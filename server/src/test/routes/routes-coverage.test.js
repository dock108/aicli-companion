import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import { setupRoutes } from '../../routes/index.js';

// Create a test app with route capturing
function createTestApp() {
  const app = express();
  app.use(express.json());

  const routes = [];
  const routers = [];
  const originalUse = app.use.bind(app);

  // Capture routers when they're registered
  app.use = (path, router) => {
    const result = originalUse(path, router);

    if (typeof path === 'string' && router) {
      routers.push({ path, router });
    }
    return result;
  };

  // Function to extract routes after setup is complete
  const extractRoutes = () => {
    routes.length = 0; // Clear existing routes
    routers.forEach(({ path, router }) => {
      if (router.stack) {
        router.stack.forEach((layer) => {
          if (layer.route) {
            const methods = Object.keys(layer.route.methods);
            methods.forEach((method) => {
              routes.push({
                method: method.toUpperCase(),
                path: path + layer.route.path,
                handler: layer.route.stack[0].handle,
              });
            });
          }
        });
      }
    });
  };

  return { app, routes, extractRoutes };
}

describe('Routes Coverage Tests', () => {
  let app;
  let routes;
  let extractRoutes;
  let claudeService;

  beforeEach(() => {
    const testApp = createTestApp();
    app = testApp.app;
    routes = testApp.routes;
    extractRoutes = testApp.extractRoutes;

    claudeService = {
      healthCheck: mock.fn(async () => ({
        status: 'healthy',
        claudeCodeAvailable: true,
        activeSessions: 2,
        timestamp: new Date().toISOString(),
      })),
      sendPrompt: mock.fn(async () => ({
        sessionId: 'test-session',
        response: 'Claude response',
        usage: { tokens: 100 },
      })),
      sendStreamingPrompt: mock.fn(async () => ({
        sessionId: 'stream-session',
        streamUrl: '/stream/stream-session',
      })),
      askClaude: mock.fn(),
      sendToExistingSession: mock.fn(async () => ({ success: true })),
      resumeSession: mock.fn(async () => ({ resumed: true })),
      closeSession: mock.fn(async () => ({ closed: true })),
      getSessionInfo: mock.fn(() => ({
        id: 'test-session',
        status: 'active',
        model: 'claude-3',
      })),
      getActiveSessions: mock.fn(() => [
        { id: 'session-1', status: 'active' },
        { id: 'session-2', status: 'active' },
      ]),
      handlePermissionPrompt: mock.fn(async () => ({ accepted: true })),
      isAvailable: mock.fn(() => true),
    };

    setupRoutes(app, claudeService);
    // Extract routes after setup is complete
    extractRoutes();

    // Debug: log captured routes
    // console.log('Captured routes:', routes.map(r => `${r.method} ${r.path}`));
  });

  async function callRoute(method, path, options = {}) {
    const route = routes.find((r) => r.method === method && r.path === path);
    if (!route) {
      throw new Error(`Route ${method} ${path} not found`);
    }

    const req = {
      body: options.body || {},
      params: options.params || {},
      query: options.query || {},
      headers: options.headers || {},
    };

    const res = {
      statusCode: 200,
      status: mock.fn(function (code) {
        this.statusCode = code;
        return this;
      }),
      json: mock.fn(),
      write: mock.fn(),
      end: mock.fn(),
      setHeader: mock.fn(),
    };

    await route.handler(req, res);
    return res;
  }

  describe('GET /api/health', () => {
    it('should return health status', async () => {
      const res = await callRoute('GET', '/api/health');

      assert.strictEqual(claudeService.healthCheck.mock.calls.length, 1);
      assert.strictEqual(res.json.mock.calls.length, 1);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].status, 'healthy');
    });

    it('should handle errors', async () => {
      claudeService.healthCheck = mock.fn(async () => {
        throw new Error('Service unavailable');
      });

      const res = await callRoute('GET', '/api/health');

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].status, 'error');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].message, 'Service unavailable');
    });
  });

  describe('POST /api/ask', () => {
    it('should send prompt to Claude', async () => {
      const res = await callRoute('POST', '/api/ask', {
        body: {
          prompt: 'Hello Claude',
          sessionId: 'test-session',
          format: 'json',
        },
      });

      assert.strictEqual(claudeService.sendPrompt.mock.calls.length, 1);
      assert.strictEqual(claudeService.sendPrompt.mock.calls[0].arguments[0], 'Hello Claude');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].response, 'Claude response');
    });

    it('should return 400 if prompt is missing', async () => {
      const res = await callRoute('POST', '/api/ask', {
        body: {},
      });

      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Prompt is required');
    });

    it('should handle errors', async () => {
      claudeService.sendPrompt = mock.fn(async () => {
        throw new Error('Claude error');
      });

      // Mock console.error
      const originalConsoleError = console.error;
      console.error = mock.fn();

      const res = await callRoute('POST', '/api/ask', {
        body: { prompt: 'Hello' },
      });

      console.error = originalConsoleError;

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Claude error');
    });
  });

  describe('POST /api/stream/start', () => {
    it('should start streaming session', async () => {
      const res = await callRoute('POST', '/api/stream/start', {
        body: {
          prompt: 'Stream this',
        },
      });

      assert.strictEqual(claudeService.sendStreamingPrompt.mock.calls.length, 1);
      assert.strictEqual(
        claudeService.sendStreamingPrompt.mock.calls[0].arguments[0],
        'Stream this'
      );
      assert.strictEqual(res.json.mock.calls[0].arguments[0].sessionId, 'stream-session');
    });

    it('should return 400 if prompt is missing', async () => {
      const res = await callRoute('POST', '/api/stream/start', {
        body: {},
      });

      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Prompt is required');
    });

    it('should handle errors', async () => {
      claudeService.sendStreamingPrompt = mock.fn(async () => {
        throw new Error('Stream error');
      });

      const originalConsoleError = console.error;
      console.error = mock.fn();

      const res = await callRoute('POST', '/api/stream/start', {
        body: { prompt: 'Stream' },
      });

      console.error = originalConsoleError;

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Stream error');
    });
  });

  describe('POST /api/stream/:sessionId', () => {
    it('should send to existing session', async () => {
      const res = await callRoute('POST', '/api/stream/:sessionId', {
        params: { sessionId: 'stream-123' },
        body: { prompt: 'Continue' },
      });

      assert.strictEqual(claudeService.sendToExistingSession.mock.calls.length, 1);
      assert.strictEqual(
        claudeService.sendToExistingSession.mock.calls[0].arguments[0],
        'stream-123'
      );
      assert.strictEqual(
        claudeService.sendToExistingSession.mock.calls[0].arguments[1],
        'Continue'
      );
      assert.deepStrictEqual(res.json.mock.calls[0].arguments[0], { success: true });
    });

    it('should return 400 if prompt is missing', async () => {
      const res = await callRoute('POST', '/api/stream/:sessionId', {
        params: { sessionId: 'stream-123' },
        body: {},
      });

      assert.strictEqual(res.statusCode, 400);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Prompt is required');
    });

    it('should handle errors', async () => {
      claudeService.sendToExistingSession = mock.fn(async () => {
        throw new Error('Session not found');
      });

      const originalConsoleError = console.error;
      console.error = mock.fn();

      const res = await callRoute('POST', '/api/stream/:sessionId', {
        params: { sessionId: 'invalid' },
        body: { prompt: 'Test' },
      });

      console.error = originalConsoleError;

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Session not found');
    });
  });

  describe('DELETE /api/stream/:sessionId', () => {
    it('should close session', async () => {
      const res = await callRoute('DELETE', '/api/stream/:sessionId', {
        params: { sessionId: 'stream-123' },
      });

      assert.strictEqual(claudeService.closeSession.mock.calls.length, 1);
      assert.strictEqual(claudeService.closeSession.mock.calls[0].arguments[0], 'stream-123');
      assert.deepStrictEqual(res.json.mock.calls[0].arguments[0], { closed: true });
    });

    it('should handle errors', async () => {
      claudeService.closeSession = mock.fn(async () => {
        throw new Error('Failed to close');
      });

      const originalConsoleError = console.error;
      console.error = mock.fn();

      const res = await callRoute('DELETE', '/api/stream/:sessionId', {
        params: { sessionId: 'stream-123' },
      });

      console.error = originalConsoleError;

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Failed to close');
    });
  });

  describe('GET /api/sessions', () => {
    it('should list active sessions', async () => {
      const res = await callRoute('GET', '/api/sessions');

      assert.strictEqual(claudeService.getActiveSessions.mock.calls.length, 1);
      assert.ok(res.json.mock.calls[0].arguments[0].sessions);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].sessions.length, 2);
    });

    it('should handle errors', async () => {
      claudeService.getActiveSessions = mock.fn(() => {
        throw new Error('Failed to get sessions');
      });

      const res = await callRoute('GET', '/api/sessions');

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Failed to get sessions');
    });
  });

  describe('POST /api/permission/:sessionId', () => {
    it('should handle permission response', async () => {
      const res = await callRoute('POST', '/api/permission/:sessionId', {
        params: { sessionId: 'session-123' },
        body: { response: 'y' },
      });

      assert.strictEqual(claudeService.handlePermissionPrompt.mock.calls.length, 1);
      assert.strictEqual(
        claudeService.handlePermissionPrompt.mock.calls[0].arguments[0],
        'session-123'
      );
      assert.strictEqual(claudeService.handlePermissionPrompt.mock.calls[0].arguments[1], 'y');
      assert.deepStrictEqual(res.json.mock.calls[0].arguments[0], { accepted: true });
    });

    it('should return 400 if response is undefined', async () => {
      const res = await callRoute('POST', '/api/permission/:sessionId', {
        params: { sessionId: 'session-123' },
        body: {},
      });

      assert.strictEqual(res.statusCode, 400);
      assert.ok(res.json.mock.calls[0].arguments[0].error.includes('Response is required'));
    });

    it('should handle errors', async () => {
      claudeService.handlePermissionPrompt = mock.fn(async () => {
        throw new Error('Invalid session');
      });

      const originalConsoleError = console.error;
      console.error = mock.fn();

      const res = await callRoute('POST', '/api/permission/:sessionId', {
        params: { sessionId: 'invalid' },
        body: { response: 'y' },
      });

      console.error = originalConsoleError;

      assert.strictEqual(res.statusCode, 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Invalid session');
    });
  });

  describe('GET /api/info', () => {
    it('should return server info', async () => {
      const res = await callRoute('GET', '/api/info');

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.name, 'Claude Companion Server');
      assert.strictEqual(response.version, '1.0.0');
      assert.strictEqual(response.claudeCodeAvailable, true);
      assert.ok(response.endpoints);
      assert.strictEqual(response.websocket, '/ws');
    });
  });
});
