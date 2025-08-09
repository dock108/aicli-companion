import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import { setupAICLIStatusRoutes } from '../../routes/aicli-status.js';

describe('AICLI Status Routes', () => {
  let app;
  let aicliService;
  let handlers;
  let mockRouter;
  let originalRouter;

  beforeEach(() => {
    app = express();
    handlers = {};

    // Mock express router
    mockRouter = {
      get: mock.fn((path, ...middlewares) => {
        const handler = middlewares[middlewares.length - 1];
        handlers[`GET ${path}`] = handler;
      }),
      post: mock.fn((path, ...middlewares) => {
        const handler = middlewares[middlewares.length - 1];
        handlers[`POST ${path}`] = handler;
      }),
    };

    // Store original Router
    originalRouter = express.Router;

    // Override express.Router
    express.Router = () => mockRouter;

    // Mock claude service
    aicliService = {
      aicliCommand: '/usr/local/bin/claude',
      isAvailable: mock.fn(() => true),
      checkAvailability: mock.fn(async () => true),
      getActiveSessions: mock.fn(() => ['session-1', 'session-2']),
      maxSessions: 5,
      activeSessions: new Map([
        [
          'session-1',
          {
            workingDirectory: '/home/user/project1',
            isActive: true,
            createdAt: Date.now(),
            lastActivity: Date.now(),
            process: { pid: 1234, connected: true },
          },
        ],
      ]),
      sendOneTimePrompt: mock.fn(async () => ({ result: 'Test response' })),
      testAICLICommand: mock.fn(async (type) => {
        switch (type) {
          case 'version':
            return 'claude version 0.1.0';
          case 'help':
            return 'AICLI CLI help text';
          case 'simple':
            return 'Simple test result';
          case 'json':
            return { type: 'json', data: 'test' };
          default:
            throw new Error('Unknown test type');
        }
      }),
    };

    // Mock app.use
    app.use = mock.fn();
  });

  afterEach(() => {
    // Restore original Router
    if (originalRouter) {
      express.Router = originalRouter;
    }
  });

  describe('setupAICLIStatusRoutes', () => {
    it('should be a function', () => {
      assert.strictEqual(typeof setupAICLIStatusRoutes, 'function');
    });

    it('should setup routes on the app', () => {
      setupAICLIStatusRoutes(app, aicliService);

      assert.strictEqual(app.use.mock.calls.length, 1);
      assert.strictEqual(app.use.mock.calls[0].arguments[0], '/api');
    });

    it('should register all expected routes', () => {
      setupAICLIStatusRoutes(app, aicliService);

      const expectedRoutes = [
        'GET /aicli/status',
        'GET /aicli/sessions/:sessionId',
        'POST /aicli/test',
        'POST /aicli/debug/:testType',
        'GET /aicli/sessions/:sessionId/logs',
      ];

      expectedRoutes.forEach((route) => {
        assert.ok(handlers[route], `Route ${route} should be registered`);
      });
    });
  });

  describe('GET /aicli/status', () => {
    beforeEach(() => {
      setupAICLIStatusRoutes(app, aicliService);
    });

    it('should return claude status', async () => {
      const req = {};
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /aicli/status'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.ok(response.aicli);
      assert.ok(response.sessions);
      assert.ok(response.system);
      assert.ok(response.service);
    });

    it('should handle errors', async () => {
      aicliService.getActiveSessions.mock.mockImplementation(() => {
        throw new Error('Test error');
      });

      const req = {};
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /aicli/status'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Failed to get AICLI status');
    });
  });

  describe('GET /aicli/sessions/:sessionId', () => {
    beforeEach(() => {
      setupAICLIStatusRoutes(app, aicliService);
    });

    it('should return session info', async () => {
      const req = { params: { sessionId: 'session-1' } };
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /aicli/sessions/:sessionId'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.sessionId, 'session-1');
    });

    it('should return 404 for non-existent session', async () => {
      const req = { params: { sessionId: 'non-existent' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /aicli/sessions/:sessionId'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
    });
  });

  describe('POST /aicli/test', () => {
    beforeEach(() => {
      setupAICLIStatusRoutes(app, aicliService);
    });

    it('should test claude with default prompt', async () => {
      const req = { body: {} };
      const res = {
        json: mock.fn(),
      };

      await handlers['POST /aicli/test'](req, res);

      assert.strictEqual(aicliService.sendOneTimePrompt.mock.calls.length, 1);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].success, true);
    });

    it('should handle errors', async () => {
      aicliService.sendOneTimePrompt.mock.mockImplementation(async () => {
        throw new Error('Test error');
      });

      const req = { body: {} };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /aicli/test'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].success, false);
    });
  });

  describe('POST /aicli/debug/:testType', () => {
    beforeEach(() => {
      setupAICLIStatusRoutes(app, aicliService);
    });

    it('should run debug test', async () => {
      const req = { params: { testType: 'version' } };
      const res = {
        json: mock.fn(),
      };

      await handlers['POST /aicli/debug/:testType'](req, res);

      assert.strictEqual(res.json.mock.calls[0].arguments[0].success, true);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].testType, 'version');
    });

    it('should return 400 for invalid test type', async () => {
      const req = { params: { testType: 'invalid' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /aicli/debug/:testType'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 400);
    });
  });

  describe('GET /aicli/sessions/:sessionId/logs', () => {
    beforeEach(() => {
      setupAICLIStatusRoutes(app, aicliService);
    });

    it('should return logs placeholder', async () => {
      const req = { params: { sessionId: 'session-1' }, query: {} };
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /aicli/sessions/:sessionId/logs'](req, res);

      assert.strictEqual(
        res.json.mock.calls[0].arguments[0].message,
        'Log capture not yet implemented'
      );
    });
  });
});
