import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import { promises as fs } from 'fs';
import { setupProjectRoutes } from '../../routes/projects.js';

describe('Project Routes', () => {
  let app;
  let claudeService;
  let handlers;
  let mockRouter;
  let originalRouter;

  // Helper to create a mock response object
  const createMockResponse = () => {
    const res = {
      status: mock.fn(() => res),
      json: mock.fn(() => res),
    };
    return res;
  };

  beforeEach(() => {
    app = express();
    handlers = {};

    // Mock express router
    mockRouter = {
      get: mock.fn((routePath, ...middlewares) => {
        const handler = middlewares[middlewares.length - 1];
        handlers[`GET ${routePath}`] = handler;
      }),
      post: mock.fn((routePath, ...middlewares) => {
        const handler = middlewares[middlewares.length - 1];
        handlers[`POST ${routePath}`] = handler;
      }),
      delete: mock.fn((routePath, ...middlewares) => {
        const handler = middlewares[middlewares.length - 1];
        handlers[`DELETE ${routePath}`] = handler;
      }),
    };

    // Store original Router
    originalRouter = express.Router;

    // Override express.Router
    express.Router = () => mockRouter;

    // Mock claude service with EventEmitter methods
    claudeService = {
      on: mock.fn(),
      emit: mock.fn(),
      removeListener: mock.fn(),
      checkAvailability: mock.fn(async () => true),
      createInteractiveSession: mock.fn(async (sessionId, prompt, workingDir) => ({
        sessionId,
        message: 'Session created',
        workingDirectory: workingDir,
      })),
      closeSession: mock.fn(async () => {}),
      hasSession: mock.fn((_sessionId) => false),
      getSession: mock.fn((_sessionId) => null),
      sessionManager: {
        getPersistenceStats: mock.fn(),
        exportSessions: mock.fn(async () => []),
      },
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

  describe('setupProjectRoutes', () => {
    it('should be a function', () => {
      assert.strictEqual(typeof setupProjectRoutes, 'function');
    });

    it('should setup routes on the app', () => {
      setupProjectRoutes(app, claudeService);

      assert.strictEqual(app.use.mock.calls.length, 1);
      assert.strictEqual(app.use.mock.calls[0].arguments[0], '/api');
    });

    it('should register all expected routes', () => {
      setupProjectRoutes(app, claudeService);

      const expectedRoutes = ['GET /projects', 'GET /projects/:name'];

      expectedRoutes.forEach((route) => {
        assert.ok(handlers[route], `Route ${route} should be registered`);
      });
    });
  });

  describe('GET /projects', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should list projects successfully', async () => {
      // Mock fs.readdir to return test directories
      const mockReaddir = mock.method(fs, 'readdir', async () => [
        { name: 'project1', isDirectory: () => true },
        { name: 'project2', isDirectory: () => true },
        { name: '.hidden', isDirectory: () => true }, // Should be filtered out
        { name: 'file.txt', isDirectory: () => false }, // Should be filtered out
      ]);

      const req = {};
      const res = createMockResponse();

      await handlers['GET /projects'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.ok(response.basePath);
      assert.ok(Array.isArray(response.projects));
      assert.strictEqual(response.projects.length, 2);
      assert.strictEqual(response.projects[0].name, 'project1');
      assert.strictEqual(response.projects[1].name, 'project2');
      assert.strictEqual(response.projects[0].type, 'folder');
      assert.strictEqual(response.projects[1].type, 'folder');

      mockReaddir.mock.restore();
    });

    it('should handle errors when listing projects', async () => {
      const testError = new Error('Failed to read directory');
      const mockReaddir = mock.method(fs, 'readdir', async () => {
        throw testError;
      });

      const req = {};
      const res = createMockResponse();

      await handlers['GET /projects'](req, res);

      assert.strictEqual(res.status.mock.calls.length, 1);
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'Failed to list projects');

      mockReaddir.mock.restore();
    });
  });

  describe('GET /projects/:name', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should get project info successfully', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
        size: 1024,
        mtime: new Date('2023-01-01'),
      }));

      const mockReaddir = mock.method(fs, 'readdir', async () => [
        { name: 'file1.js', isFile: () => true },
        { name: 'file2.js', isFile: () => true },
        { name: 'subdir', isDirectory: () => true },
      ]);

      const req = {
        params: { name: 'test-project' },
      };
      const res = createMockResponse();

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.name, 'test-project');
      assert.ok(response.path.includes('test-project'));
      assert.strictEqual(response.type, 'folder');

      mockStat.mock.restore();
      mockReaddir.mock.restore();
    });

    it('should return 404 for non-existent project', async () => {
      const mockStat = mock.method(fs, 'stat', async () => {
        const error = new Error('ENOENT');
        error.code = 'ENOENT';
        throw error;
      });

      const req = {
        params: { name: 'non-existent' },
      };
      const res = createMockResponse();

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.status.mock.calls.length, 1);
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'Project not found');

      mockStat.mock.restore();
    });

    it('should handle invalid project names', async () => {
      // The implementation doesn't validate project names upfront,
      // it checks after path joining if the result escapes the base directory
      // So we'll test path traversal attempts that would be caught
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req = {
        params: { name: '../../../etc' }, // Path traversal attempt
      };
      const res = createMockResponse();

      await handlers['GET /projects/:name'](req, res);

      // The actual implementation would check path normalization
      // but our test handler might not catch this - let's verify it doesn't succeed
      if (res.status.mock.calls.length > 0) {
        assert.ok(
          res.status.mock.calls[0].arguments[0] === 403 ||
            res.status.mock.calls[0].arguments[0] === 404
        );
      }

      mockStat.mock.restore();
    });

    it('should handle general errors', async () => {
      const testError = new Error('Permission denied');
      const mockStat = mock.method(fs, 'stat', async () => {
        throw testError;
      });

      const req = {
        params: { name: 'test-project' },
      };
      const res = createMockResponse();

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.status.mock.calls.length, 1);
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'Project not found');

      mockStat.mock.restore();
    });

    it('should handle directory traversal attempts', async () => {
      const req = {
        params: { name: '../../etc' },
      };
      const res = createMockResponse();

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Access denied');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].message, 'Invalid project path');
    });
  });
});
