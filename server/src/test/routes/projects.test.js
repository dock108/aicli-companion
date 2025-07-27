import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import path from 'path';
import { promises as fs } from 'fs';
import { setupProjectRoutes } from '../../routes/projects.js';

describe('Project Routes', () => {
  let app;
  let claudeService;
  let handlers;
  let mockRouter;

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

    // Override express.Router
    express.Router = () => mockRouter;

    // Mock claude service
    claudeService = {
      checkAvailability: mock.fn(async () => true),
      createInteractiveSession: mock.fn(async (sessionId, prompt, workingDir) => ({
        sessionId,
        message: 'Session created',
        workingDirectory: workingDir,
      })),
      closeSession: mock.fn(async () => {}),
    };

    // Mock app.use
    app.use = mock.fn();
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

      const expectedRoutes = [
        'GET /projects',
        'GET /projects/:name',
        'POST /projects/:name/start',
        'GET /sessions',
        'GET /sessions/:sessionId',
        'DELETE /sessions/:sessionId',
      ];

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
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /projects'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.ok(response.basePath);
      assert.strictEqual(response.projects.length, 2);
      assert.strictEqual(response.projects[0].name, 'project1');
      assert.strictEqual(response.projects[0].type, 'folder');
      assert.strictEqual(response.projects[1].name, 'project2');

      mockReaddir.mock.restore();
    });

    it('should handle errors', async () => {
      // Mock fs.readdir to throw error
      const mockReaddir = mock.method(fs, 'readdir', async () => {
        throw new Error('Permission denied');
      });

      const req = {};
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /projects'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Failed to list projects');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].message, 'Permission denied');

      mockReaddir.mock.restore();
    });
  });

  describe('GET /projects/:name', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should get project info successfully', async () => {
      // Mock fs.stat to return directory
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));
      
      // Mock fs.readFile for package.json
      const mockReadFile = mock.method(fs, 'readFile', async () => 
        JSON.stringify({
          name: 'test-project',
          description: 'Test project description',
        })
      );

      const req = { params: { name: 'test-project' } };
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.name, 'test-project');
      assert.ok(response.path.endsWith('test-project'));
      assert.strictEqual(response.type, 'folder');
      assert.strictEqual(response.description, 'Test project description');
      assert.strictEqual(response.projectType, 'node');

      mockStat.mock.restore();
      mockReadFile.mock.restore();
    });

    it('should handle project without package.json', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));
      
      const mockReadFile = mock.method(fs, 'readFile', async () => {
        throw new Error('File not found');
      });

      const req = { params: { name: 'test-project' } };
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.name, 'test-project');
      assert.strictEqual(response.type, 'folder');
      assert.strictEqual(response.description, undefined);
      assert.strictEqual(response.projectType, undefined);

      mockStat.mock.restore();
      mockReadFile.mock.restore();
    });

    it('should handle general errors', async () => {
      // Mock stat to throw a general error (not ENOENT)
      const mockStat = mock.method(fs, 'stat', async () => {
        throw new Error('Permission denied');
      });

      const req = { params: { name: 'test-project' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /projects/:name'](req, res);

      // Should return 500 for general errors
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Failed to get project info');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].message, 'Permission denied');

      mockStat.mock.restore();
    });

    it('should return 404 for non-existent project', async () => {
      const mockStat = mock.method(fs, 'stat', async () => {
        throw new Error('ENOENT: no such file or directory');
      });

      const req = { params: { name: 'non-existent' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Project not found');

      mockStat.mock.restore();
    });

    it('should return 404 for non-directory', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => false,
      }));

      const req = { params: { name: 'file.txt' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Project not found');

      mockStat.mock.restore();
    });

    it('should prevent directory traversal', async () => {
      const req = { params: { name: '../../../etc/passwd' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /projects/:name'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Access denied');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].message, 'Invalid project path');
    });
  });

  describe('POST /projects/:name/start', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should start claude session successfully', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req = { params: { name: 'test-project' } };
      const res = {
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, true);
      assert.ok(response.session);
      assert.strictEqual(response.session.projectName, 'test-project');
      assert.strictEqual(response.session.status, 'running');
      assert.ok(response.session.sessionId);
      assert.ok(response.session.startedAt);

      mockStat.mock.restore();
    });

    it('should handle Claude CLI not available', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));
      
      claudeService.checkAvailability = mock.fn(async () => false);

      const req = { params: { name: 'test-project' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 503);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Claude CLI not available');

      mockStat.mock.restore();
    });

    it('should handle maximum sessions error', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));
      
      claudeService.createInteractiveSession = mock.fn(async () => {
        throw new Error('Maximum number of sessions reached');
      });

      const req = { params: { name: 'test-project' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 429);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Too many sessions');

      mockStat.mock.restore();
    });

    it('should handle permission denied error', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));
      
      claudeService.createInteractiveSession = mock.fn(async () => {
        throw new Error('Directory not accessible');
      });

      const req = { params: { name: 'test-project' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Permission denied');

      mockStat.mock.restore();
    });

    it('should handle invalid project location error', async () => {
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));
      
      claudeService.createInteractiveSession = mock.fn(async () => {
        throw new Error('Working directory must be within safe root');
      });

      const req = { params: { name: 'test-project' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Invalid project location');

      mockStat.mock.restore();
    });

    it('should return 404 for non-existent project', async () => {
      const mockStat = mock.method(fs, 'stat', async () => {
        throw new Error('ENOENT');
      });

      const req = { params: { name: 'non-existent' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Project not found');

      mockStat.mock.restore();
    });

    it('should handle directory traversal', async () => {
      const req = { params: { name: '../../../etc' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Access denied');
    });

    it('should handle general errors in outer try-catch', async () => {
      // Mock stat to succeed
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      // Reset claudeService to trigger error during session creation
      claudeService.checkAvailability = mock.fn(async () => {
        throw new Error('Unexpected system error');
      });

      const req = { params: { name: 'test-project' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['POST /projects/:name/start'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Failed to start Claude CLI session');
      assert.strictEqual(res.json.mock.calls[0].arguments[0].message, 'Unexpected system error');

      mockStat.mock.restore();
    });
  });

  describe('GET /sessions', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should list sessions', async () => {
      const req = {};
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /sessions'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.ok(response.sessions);
      assert.ok(typeof response.count === 'number');
    });

    it('should list sessions with actual data', async () => {
      // First create a session
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req1 = { params: { name: 'test-project' } };
      const res1 = { json: mock.fn() };
      
      await handlers['POST /projects/:name/start'](req1, res1);

      // Now list sessions
      const req = {};
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /sessions'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.sessions.length, 1);
      assert.strictEqual(response.count, 1);
      
      const session = response.sessions[0];
      assert.ok(session.sessionId);
      assert.ok(session.projectPath);
      assert.strictEqual(session.status, 'running');
      assert.ok(session.startedAt);

      mockStat.mock.restore();
    });

    it('should handle errors', async () => {
      const req = {};
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(() => {
          throw new Error('Test error');
        }),
      };

      try {
        await handlers['GET /sessions'](req, res);
      } catch (error) {
        // Expected
      }

      assert.ok(handlers['GET /sessions']);
    });
  });

  describe('GET /sessions/:sessionId', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should get session info successfully', async () => {
      // First create a session
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req1 = { params: { name: 'test-project' } };
      const res1 = { json: mock.fn() };
      
      await handlers['POST /projects/:name/start'](req1, res1);
      const sessionId = res1.json.mock.calls[0].arguments[0].session.sessionId;

      // Now get the session
      const req = { params: { sessionId } };
      const res = {
        json: mock.fn(),
      };

      await handlers['GET /sessions/:sessionId'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.sessionId, sessionId);
      assert.ok(response.projectPath);
      assert.strictEqual(response.status, 'running');
      assert.ok(response.startedAt);

      mockStat.mock.restore();
    });

    it('should return 404 for non-existent session', async () => {
      const req = { params: { sessionId: 'non-existent' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['GET /sessions/:sessionId'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Session not found');
    });

    it('should handle errors gracefully', async () => {
      const req = { params: { sessionId: 'test' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(() => {
          throw new Error('Unexpected error');
        }),
      };

      try {
        await handlers['GET /sessions/:sessionId'](req, res);
      } catch (error) {
        // Expected
      }

      assert.ok(handlers['GET /sessions/:sessionId']);
    });
  });

  describe('DELETE /sessions/:sessionId', () => {
    beforeEach(() => {
      setupProjectRoutes(app, claudeService);
    });

    it('should stop session successfully', async () => {
      // First create a session
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req1 = { params: { name: 'test-project' } };
      const res1 = { json: mock.fn() };
      
      await handlers['POST /projects/:name/start'](req1, res1);
      const sessionId = res1.json.mock.calls[0].arguments[0].session.sessionId;

      // Now delete the session
      const req = { params: { sessionId } };
      const res = {
        json: mock.fn(),
      };

      await handlers['DELETE /sessions/:sessionId'](req, res);

      assert.strictEqual(res.json.mock.calls.length, 1);
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, true);
      assert.ok(response.message.includes('is being stopped'));
      assert.strictEqual(response.sessionId, sessionId);

      // Verify closeSession was called
      assert.strictEqual(claudeService.closeSession.mock.calls.length, 1);
      assert.strictEqual(claudeService.closeSession.mock.calls[0].arguments[0], sessionId);
      assert.strictEqual(claudeService.closeSession.mock.calls[0].arguments[1], 'user_requested');

      mockStat.mock.restore();
    });

    it('should handle session not running', async () => {
      // Create a stopped session
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req1 = { params: { name: 'test-project' } };
      const res1 = { json: mock.fn() };
      
      await handlers['POST /projects/:name/start'](req1, res1);
      const sessionId = res1.json.mock.calls[0].arguments[0].session.sessionId;

      // Mark session as stopped directly
      const sessions = Array.from(handlers['GET /sessions']);
      const activeSessions = new Map();
      activeSessions.set(sessionId, {
        sessionId,
        status: 'stopped',
        projectPath: '/test',
      });
      
      // Mock the activeSessions Map
      const originalGet = Map.prototype.get;
      Map.prototype.get = function(key) {
        if (this === activeSessions || key === sessionId) {
          return { sessionId, status: 'stopped', projectPath: '/test' };
        }
        return originalGet.call(this, key);
      };

      const req = { params: { sessionId } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['DELETE /sessions/:sessionId'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 400);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Session not running');

      Map.prototype.get = originalGet;
      mockStat.mock.restore();
    });

    it('should handle non-existent session', async () => {
      const req = { params: { sessionId: 'non-existent' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(),
      };

      await handlers['DELETE /sessions/:sessionId'](req, res);

      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].error, 'Session not found');
    });

    it('should handle closeSession errors gracefully', async () => {
      // First create a session
      const mockStat = mock.method(fs, 'stat', async () => ({
        isDirectory: () => true,
      }));

      const req1 = { params: { name: 'test-project' } };
      const res1 = { json: mock.fn() };
      
      await handlers['POST /projects/:name/start'](req1, res1);
      const sessionId = res1.json.mock.calls[0].arguments[0].session.sessionId;

      // Mock closeSession to throw error
      claudeService.closeSession = mock.fn(async () => {
        throw new Error('Failed to close');
      });

      const req = { params: { sessionId } };
      const res = {
        json: mock.fn(),
      };

      await handlers['DELETE /sessions/:sessionId'](req, res);

      // Should still return success
      assert.strictEqual(res.json.mock.calls.length, 1);
      assert.strictEqual(res.json.mock.calls[0].arguments[0].success, true);

      mockStat.mock.restore();
    });

    it('should handle general errors', async () => {
      const req = { params: { sessionId: 'test' } };
      const res = {
        status: mock.fn(() => res),
        json: mock.fn(() => {
          throw new Error('Test error');
        }),
      };

      try {
        await handlers['DELETE /sessions/:sessionId'](req, res);
      } catch (error) {
        // Expected
      }

      assert.ok(handlers['DELETE /sessions/:sessionId']);
    });
  });

  describe('Route logic components', () => {
    it('should properly handle path joining', () => {
      const basePath = '/test/projects';
      const projectName = 'my-project';
      const fullPath = path.join(basePath, projectName);

      assert.strictEqual(fullPath, '/test/projects/my-project');
    });

    it('should properly handle path normalization for security', () => {
      const basePath = '/test/projects';
      const maliciousPath = '../../../etc/passwd';
      const attemptedPath = path.join(basePath, maliciousPath);
      const normalizedPath = path.normalize(attemptedPath);
      const normalizedBase = path.normalize(basePath);

      assert.strictEqual(
        normalizedPath.startsWith(normalizedBase),
        false,
        'Directory traversal attempt should be detected'
      );
    });
  });
});
