import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { setupProjectRoutes } from '../../routes/projects.js';

const mockConfig = {
  configPath: '/test/base/path'
};

// Mock ServerConfig
const originalConfig = await import('../../config/server-config.js');
const ServerConfigMock = class {
  constructor() {
    this.configPath = mockConfig.configPath;
  }
};

// Override the module
await test.mock.module('../../config/server-config.js', {
  namedExports: {
    ServerConfig: ServerConfigMock
  }
});

// Mock fs module
const mockFs = {
  readdir: async () => [],
  stat: async () => ({ isDirectory: () => true }),
  readFile: async () => '{}'
};

await test.mock.module('fs', {
  namedExports: {
    promises: mockFs
  }
});

test('Project Routes', async (t) => {
  let app;
  let mockReaddir;
  let mockStat;
  let mockReadFile;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    
    // Reset mocks
    mockReaddir = async () => [
      { name: 'project1', isDirectory: () => true },
      { name: 'project2', isDirectory: () => true },
      { name: '.hidden', isDirectory: () => true },
      { name: 'file.txt', isDirectory: () => false }
    ];
    
    mockStat = async () => ({ isDirectory: () => true });
    mockReadFile = async () => '{"name": "test-project", "description": "Test project"}';
    
    mockFs.readdir = mockReaddir;
    mockFs.stat = mockStat;
    mockFs.readFile = mockReadFile;
    
    setupProjectRoutes(app);
  });

  await t.test('GET /api/projects', async (t) => {
    await t.test('should list all non-hidden directories', async () => {
      const res = await makeRequest(app, 'GET', '/api/projects');
      
      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.body.basePath, mockConfig.configPath);
      assert.strictEqual(res.body.projects.length, 2);
      assert.strictEqual(res.body.projects[0].name, 'project1');
      assert.strictEqual(res.body.projects[1].name, 'project2');
    });

    await t.test('should handle readdir errors', async () => {
      mockFs.readdir = async () => {
        throw new Error('Permission denied');
      };
      
      const res = await makeRequest(app, 'GET', '/api/projects');
      
      assert.strictEqual(res.status, 500);
      assert.strictEqual(res.body.error, 'Failed to list projects');
    });

    await t.test('should handle empty directory', async () => {
      mockFs.readdir = async () => [];
      
      const res = await makeRequest(app, 'GET', '/api/projects');
      
      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.body.projects.length, 0);
    });
  });

  await t.test('GET /api/projects/:name', async (t) => {
    await t.test('should get project info', async () => {
      const res = await makeRequest(app, 'GET', '/api/projects/project1');
      
      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.body.name, 'project1');
      assert.strictEqual(res.body.path, path.join(mockConfig.configPath, 'project1'));
      assert.strictEqual(res.body.description, 'Test project');
      assert.strictEqual(res.body.projectType, 'node');
    });

    await t.test('should prevent directory traversal', async () => {
      const res = await makeRequest(app, 'GET', '/api/projects/../../../etc');
      
      assert.strictEqual(res.status, 403);
      assert.strictEqual(res.body.error, 'Access denied');
    });

    await t.test('should handle non-existent project', async () => {
      mockFs.stat = async () => {
        throw new Error('ENOENT');
      };
      
      const res = await makeRequest(app, 'GET', '/api/projects/nonexistent');
      
      assert.strictEqual(res.status, 404);
      assert.strictEqual(res.body.error, 'Project not found');
    });

    await t.test('should handle non-directory', async () => {
      mockFs.stat = async () => ({ isDirectory: () => false });
      
      const res = await makeRequest(app, 'GET', '/api/projects/file');
      
      assert.strictEqual(res.status, 404);
      assert.strictEqual(res.body.error, 'Project not found');
    });

    await t.test('should handle missing package.json gracefully', async () => {
      mockFs.readFile = async () => {
        throw new Error('ENOENT');
      };
      
      const res = await makeRequest(app, 'GET', '/api/projects/project1');
      
      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.body.name, 'project1');
      assert.strictEqual(res.body.description, undefined);
      assert.strictEqual(res.body.projectType, undefined);
    });
  });
});

// Helper function to make requests
async function makeRequest(app, method, path, body = null) {
  return new Promise((resolve) => {
    const req = {
      method,
      url: path,
      headers: { 'content-type': 'application/json' },
      body,
      params: {},
      query: {}
    };
    
    // Extract params from path
    const match = path.match(/\/api\/projects\/([^/]+)$/);
    if (match) {
      req.params.name = match[1];
    }
    
    const res = {
      status: 200,
      body: null,
      headers: {},
      status(code) {
        this.status = code;
        return this;
      },
      json(data) {
        this.body = data;
        resolve(this);
      }
    };
    
    // Find matching route
    const routes = app._router.stack
      .filter(layer => layer.route)
      .map(layer => ({
        path: layer.route.path,
        method: Object.keys(layer.route.methods)[0].toUpperCase(),
        handler: layer.route.stack[0].handle
      }));
    
    const route = routes.find(r => 
      r.method === method && 
      (r.path === path || path.match(new RegExp(r.path.replace(/:[^/]+/g, '[^/]+'))))
    );
    
    if (route) {
      route.handler(req, res, (err) => {
        if (err) {
          res.status(500).json({ error: err.message });
        }
      });
    } else {
      res.status(404).json({ error: 'Not found' });
    }
  });
}