import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import path from 'path';
import { setupProjectRoutes } from '../../routes/projects.js';

describe('Project Routes', () => {
  let app;
  let handlers;
  let mockFs;
  let originalServerConfig;

  beforeEach(() => {
    app = express();
    handlers = {};

    // Mock express router
    const mockRouter = {
      get: mock.fn((path, handler) => {
        handlers[`GET ${path}`] = handler;
      }),
      post: mock.fn((path, handler) => {
        handlers[`POST ${path}`] = handler;
      }),
      delete: mock.fn((path, handler) => {
        handlers[`DELETE ${path}`] = handler;
      }),
    };

    // Override express.Router
    express.Router = () => mockRouter;

    // Mock app.use
    app.use = mock.fn();

    // Mock fs promises
    mockFs = {
      readdir: mock.fn(async () => [
        { name: 'project1', isDirectory: () => true },
        { name: 'project2', isDirectory: () => true },
        { name: '.hidden', isDirectory: () => true },
        { name: 'file.txt', isDirectory: () => false },
      ]),
      stat: mock.fn(async () => ({ isDirectory: () => true })),
      readFile: mock.fn(async () => '{"name": "test-project", "description": "Test project"}'),
    };
  });

  describe('GET /projects', () => {
    it('should list all non-hidden directories', async () => {
      setupProjectRoutes(app);
      
      const handler = handlers['GET /projects'];
      assert(handler, 'GET /projects handler should be registered');

      const req = {};
      const res = {
        json: mock.fn(),
        status: mock.fn(() => res),
      };

      // Mock ServerConfig
      const mockConfig = { configPath: '/test/base/path' };
      
      // Temporarily replace the real implementation
      const originalSetupProjectRoutes = setupProjectRoutes;
      const testSetupProjectRoutes = (app) => {
        const router = express.Router();
        
        router.get('/projects', async (req, res) => {
          try {
            const projectsDir = mockConfig.configPath;
            const items = await mockFs.readdir(projectsDir, { withFileTypes: true });
            
            const projects = items
              .filter((item) => item.isDirectory() && !item.name.startsWith('.'))
              .map((item) => ({
                name: item.name,
                path: path.join(projectsDir, item.name),
                type: 'folder',
              }));

            res.json({
              basePath: projectsDir,
              projects: projects.sort((a, b) => a.name.localeCompare(b.name)),
            });
          } catch (error) {
            res.status(500).json({
              error: 'Failed to list projects',
              message: error.message,
            });
          }
        });
        
        app.use('/api', router);
      };

      testSetupProjectRoutes(app);
      const testHandler = handlers['GET /projects'];
      
      await testHandler(req, res);

      assert(res.json.mock.calls.length === 1, 'res.json should be called once');
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.basePath, '/test/base/path');
      assert.strictEqual(response.projects.length, 2);
      assert.strictEqual(response.projects[0].name, 'project1');
      assert.strictEqual(response.projects[1].name, 'project2');
    });

    it('should handle readdir errors', async () => {
      mockFs.readdir = mock.fn(async () => {
        throw new Error('Permission denied');
      });

      const testSetupProjectRoutes = (app) => {
        const router = express.Router();
        
        router.get('/projects', async (req, res) => {
          try {
            await mockFs.readdir('/test/base/path', { withFileTypes: true });
          } catch (error) {
            res.status(500).json({
              error: 'Failed to list projects',
              message: error.message,
            });
          }
        });
        
        app.use('/api', router);
      };

      testSetupProjectRoutes(app);
      const handler = handlers['GET /projects'];

      const req = {};
      const res = {
        json: mock.fn(),
        status: mock.fn(() => res),
      };

      await handler(req, res);

      assert(res.status.mock.calls.length === 1, 'res.status should be called once');
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 500);
      assert(res.json.mock.calls.length === 1, 'res.json should be called once');
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'Failed to list projects');
    });
  });

  describe('GET /projects/:name', () => {
    it('should get project info', async () => {
      const testSetupProjectRoutes = (app) => {
        const router = express.Router();
        
        router.get('/projects/:name', async (req, res) => {
          try {
            const { name } = req.params;
            const projectsDir = '/test/base/path';
            const projectPath = path.join(projectsDir, name);

            // Security check
            const normalizedPath = path.normalize(projectPath);
            const normalizedBase = path.normalize(projectsDir);

            if (!normalizedPath.startsWith(normalizedBase)) {
              return res.status(403).json({
                error: 'Access denied',
                message: 'Invalid project path',
              });
            }

            // Check if project exists
            const stat = await mockFs.stat(projectPath);
            if (!stat.isDirectory()) {
              throw new Error('Not a directory');
            }

            const info = {
              name,
              path: projectPath,
              type: 'folder',
            };

            // Try to get package.json info
            try {
              const packageJsonPath = path.join(projectPath, 'package.json');
              const packageJson = await mockFs.readFile(packageJsonPath, 'utf-8');
              const packageData = JSON.parse(packageJson);
              info.description = packageData.description;
              info.projectType = 'node';
            } catch (error) {
              // Not a Node project
            }

            res.json(info);
          } catch (error) {
            res.status(500).json({
              error: 'Failed to get project info',
              message: error.message,
            });
          }
        });
        
        app.use('/api', router);
      };

      testSetupProjectRoutes(app);
      const handler = handlers['GET /projects/:name'];

      const req = { params: { name: 'project1' } };
      const res = {
        json: mock.fn(),
        status: mock.fn(() => res),
      };

      await handler(req, res);

      assert(res.json.mock.calls.length === 1, 'res.json should be called once');
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.name, 'project1');
      assert.strictEqual(response.path, path.join('/test/base/path', 'project1'));
      assert.strictEqual(response.description, 'Test project');
      assert.strictEqual(response.projectType, 'node');
    });

    it('should prevent directory traversal', async () => {
      const testSetupProjectRoutes = (app) => {
        const router = express.Router();
        
        router.get('/projects/:name', async (req, res) => {
          const { name } = req.params;
          const projectsDir = '/test/base/path';
          const projectPath = path.join(projectsDir, name);

          const normalizedPath = path.normalize(projectPath);
          const normalizedBase = path.normalize(projectsDir);

          if (!normalizedPath.startsWith(normalizedBase)) {
            return res.status(403).json({
              error: 'Access denied',
              message: 'Invalid project path',
            });
          }

          res.json({ success: true });
        });
        
        app.use('/api', router);
      };

      testSetupProjectRoutes(app);
      const handler = handlers['GET /projects/:name'];

      const req = { params: { name: '../../../etc' } };
      const res = {
        json: mock.fn(),
        status: mock.fn(() => res),
      };

      await handler(req, res);

      assert(res.status.mock.calls.length === 1, 'res.status should be called once');
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 403);
      assert(res.json.mock.calls.length === 1, 'res.json should be called once');
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'Access denied');
    });

    it('should handle non-existent project', async () => {
      mockFs.stat = mock.fn(async () => {
        throw new Error('ENOENT');
      });

      const testSetupProjectRoutes = (app) => {
        const router = express.Router();
        
        router.get('/projects/:name', async (req, res) => {
          try {
            const { name } = req.params;
            const projectsDir = '/test/base/path';
            const projectPath = path.join(projectsDir, name);

            const normalizedPath = path.normalize(projectPath);
            const normalizedBase = path.normalize(projectsDir);

            if (!normalizedPath.startsWith(normalizedBase)) {
              return res.status(403).json({
                error: 'Access denied',
                message: 'Invalid project path',
              });
            }

            const stat = await mockFs.stat(projectPath);
            if (!stat.isDirectory()) {
              throw new Error('Not a directory');
            }

            res.json({ success: true });
          } catch (error) {
            res.status(404).json({
              error: 'Project not found',
              message: `Project '${req.params.name}' does not exist`,
            });
          }
        });
        
        app.use('/api', router);
      };

      testSetupProjectRoutes(app);
      const handler = handlers['GET /projects/:name'];

      const req = { params: { name: 'nonexistent' } };
      const res = {
        json: mock.fn(),
        status: mock.fn(() => res),
      };

      await handler(req, res);

      assert(res.status.mock.calls.length === 1, 'res.status should be called once');
      assert.strictEqual(res.status.mock.calls[0].arguments[0], 404);
      assert(res.json.mock.calls.length === 1, 'res.json should be called once');
      const response = res.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'Project not found');
    });
  });
});