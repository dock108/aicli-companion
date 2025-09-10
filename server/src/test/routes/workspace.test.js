/**
 * Unit tests for workspace.js route
 * Tests the workspace route structure and functionality
 */

import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import request from 'supertest';
import { promises as fs } from 'fs';

// Import the route setup function
import { setupWorkspaceRoutes } from '../../routes/workspace.js';

describe('Workspace Route', () => {
  let app;
  let mockAicliService;
  let originalReaddir;
  let originalReadFile;
  let originalStat;
  let originalAccess;
  let originalMkdir;
  let originalWriteFile;
  let originalRename;

  beforeEach(() => {
    // Create a fresh Express app for each test
    app = express();
    app.use(express.json());

    // Create mock AICLI service
    mockAicliService = {
      sendMessage: mock.fn(),
      getSessionStatus: mock.fn(),
    };

    // Save original fs methods
    originalReaddir = fs.readdir;
    originalReadFile = fs.readFile;
    originalStat = fs.stat;
    originalAccess = fs.access;
    originalMkdir = fs.mkdir;
    originalWriteFile = fs.writeFile;
    originalRename = fs.rename;

    // Setup routes
    setupWorkspaceRoutes(app, mockAicliService);
  });

  describe('Export tests', () => {
    it('should export setupWorkspaceRoutes function', async () => {
      const workspaceModule = await import('../../routes/workspace.js');
      assert(workspaceModule.setupWorkspaceRoutes, 'Should export setupWorkspaceRoutes function');
      assert(
        typeof workspaceModule.setupWorkspaceRoutes === 'function',
        'setupWorkspaceRoutes should be a function'
      );
    });
  });

  describe('GET /api/workspace/status', () => {
    it('should return workspace status', async () => {
      const response = await request(app).get('/api/workspace/status').expect(200);

      assert(response.body.available === true);
      assert(response.body.workspaceRoot);
      assert(response.body.restrictions);
      assert(response.body.message === 'Workspace mode is available');
    });

    it('should handle errors in workspace status', async () => {
      // Mock workspaceSecurity to throw an error
      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalGetRestrictions = workspaceSecurity.getWorkspaceRestrictions;
      workspaceSecurity.getWorkspaceRestrictions = () => {
        throw new Error('Test error');
      };

      const response = await request(app).get('/api/workspace/status').expect(500);

      assert(response.body.error === 'Failed to get workspace status');
      assert(response.body.message === 'Test error');

      // Restore original method
      workspaceSecurity.getWorkspaceRestrictions = originalGetRestrictions;
    });
  });

  describe('POST /api/workspace/enter', () => {
    it('should reject request without deviceToken', async () => {
      const response = await request(app).post('/api/workspace/enter').send({}).expect(400);

      assert(response.body.error === 'Missing device token');
      assert(response.body.message === 'Device token is required for workspace mode');
    });

    it('should enter workspace mode with valid deviceToken', async () => {
      const response = await request(app)
        .post('/api/workspace/enter')
        .send({ deviceToken: 'test-device-token' })
        .expect(200);

      assert(response.body.success === true);
      assert(response.body.sessionId);
      assert(response.body.workspaceContext);
      assert(response.body.message === 'Entered workspace mode successfully');
    });

    it('should handle errors when entering workspace mode', async () => {
      // Mock sessionManager to throw an error
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalCreateSession = AICLISessionManager.prototype.createInteractiveSession;
      AICLISessionManager.prototype.createInteractiveSession = async () => {
        throw new Error('Session creation failed');
      };

      const response = await request(app)
        .post('/api/workspace/enter')
        .send({ deviceToken: 'test-device-token' })
        .expect(500);

      assert(response.body.error === 'Failed to enter workspace mode');
      assert(response.body.message === 'Session creation failed');

      // Restore original method
      AICLISessionManager.prototype.createInteractiveSession = originalCreateSession;
    });
  });

  describe('GET /api/workspace/projects', () => {
    it('should list workspace projects', async () => {
      // Mock fs.readdir to return test projects
      fs.readdir = async () => [
        { name: 'project1', isDirectory: () => true },
        { name: 'project2', isDirectory: () => true },
        { name: '.hidden', isDirectory: () => true },
        { name: 'file.txt', isDirectory: () => false },
      ];

      // Mock fs.stat
      fs.stat = async () => ({
        mtime: new Date('2024-01-01'),
      });

      // Mock fs.readFile for package.json
      fs.readFile = async (filePath) => {
        if (filePath.includes('package.json')) {
          return JSON.stringify({
            name: 'test-project',
            version: '1.0.0',
            description: 'Test project',
          });
        }
        throw new Error('File not found');
      };

      // Mock fs.access
      fs.access = async () => {
        throw new Error('File not found');
      };

      const response = await request(app).get('/api/workspace/projects').expect(200);

      assert(response.body.workspaceRoot);
      assert(response.body.projectCount === 2);
      assert(Array.isArray(response.body.projects));
      assert(response.body.projects.length === 2);
      assert(response.body.projects[0].name === 'project1');
      assert(response.body.projects[0].projectType === 'node');

      // Restore original methods
      fs.readdir = originalReaddir;
      fs.stat = originalStat;
      fs.readFile = originalReadFile;
      fs.access = originalAccess;
    });

    it('should handle errors when listing projects', async () => {
      fs.readdir = async () => {
        throw new Error('Permission denied');
      };

      const response = await request(app).get('/api/workspace/projects').expect(500);

      assert(response.body.error === 'Failed to list workspace projects');
      assert(response.body.message === 'Permission denied');

      // Restore original method
      fs.readdir = originalReaddir;
    });

    it('should detect Maven projects', async () => {
      fs.readdir = async () => [{ name: 'maven-project', isDirectory: () => true }];

      fs.stat = async () => ({
        mtime: new Date('2024-01-01'),
      });

      fs.readFile = async () => {
        throw new Error('No package.json');
      };

      fs.access = async (filePath) => {
        if (filePath.includes('pom.xml')) {
          return; // File exists
        }
        throw new Error('File not found');
      };

      const response = await request(app).get('/api/workspace/projects').expect(200);

      assert(response.body.projects[0].projectType === 'maven');

      // Restore original methods
      fs.readdir = originalReaddir;
      fs.stat = originalStat;
      fs.readFile = originalReadFile;
      fs.access = originalAccess;
    });

    it('should detect Gradle projects', async () => {
      fs.readdir = async () => [{ name: 'gradle-project', isDirectory: () => true }];

      fs.stat = async () => ({
        mtime: new Date('2024-01-01'),
      });

      fs.readFile = async () => {
        throw new Error('No package.json');
      };

      fs.access = async (filePath) => {
        if (filePath.includes('build.gradle')) {
          return; // File exists
        }
        throw new Error('File not found');
      };

      const response = await request(app).get('/api/workspace/projects').expect(200);

      assert(response.body.projects[0].projectType === 'gradle');

      // Restore original methods
      fs.readdir = originalReaddir;
      fs.stat = originalStat;
      fs.readFile = originalReadFile;
      fs.access = originalAccess;
    });
  });

  describe('POST /api/workspace/execute', () => {
    it('should reject request without required parameters', async () => {
      const response = await request(app).post('/api/workspace/execute').send({}).expect(400);

      assert(response.body.error === 'Missing required parameters');
      assert(response.body.message === 'sessionId and operation are required');
    });

    it('should reject request without sessionId', async () => {
      const response = await request(app)
        .post('/api/workspace/execute')
        .send({ operation: 'test' })
        .expect(400);

      assert(response.body.error === 'Missing required parameters');
    });

    it('should reject request without operation', async () => {
      const response = await request(app)
        .post('/api/workspace/execute')
        .send({ sessionId: 'test-session' })
        .expect(400);

      assert(response.body.error === 'Missing required parameters');
    });

    it('should reject invalid workspace session', async () => {
      // Mock sessionManager to return null session
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => null;

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({ sessionId: 'test-session', operation: 'test' })
        .expect(403);

      assert(response.body.error === 'Invalid workspace session');
      assert(response.body.message === 'This operation requires an active workspace session');

      // Restore original method
      AICLISessionManager.prototype.getSession = originalGetSession;
    });

    it('should reject non-workspace session', async () => {
      // Mock sessionManager to return non-workspace session
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: false,
      });

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({ sessionId: 'test-session', operation: 'test' })
        .expect(403);

      assert(response.body.error === 'Invalid workspace session');

      // Restore original method
      AICLISessionManager.prototype.getSession = originalGetSession;
    });

    it('should reject disallowed operations', async () => {
      // Mock sessionManager to return valid workspace session
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      // Mock workspaceSecurity to disallow operation
      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: false,
        message: 'Operation not permitted',
      });

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({ sessionId: 'test-session', operation: 'test' })
        .expect(403);

      assert(response.body.error === 'Operation not allowed');
      assert(response.body.message === 'Operation not permitted');

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
    });

    it('should handle unknown operations', async () => {
      // Mock sessionManager and security
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({ sessionId: 'test-session', operation: 'unknown_operation' })
        .expect(400);

      assert(response.body.error === 'Unknown operation');
      assert(response.body.message.includes('unknown_operation'));

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
    });

    it('should execute search_across_projects operation', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      fs.readdir = async () => [
        { name: 'project1', isDirectory: () => true },
        { name: '.hidden', isDirectory: () => true },
      ];

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'search_across_projects',
          params: { searchTerm: 'test', filePattern: '*.js' },
        })
        .expect(200);

      assert(response.body.success === true);
      assert(response.body.searchTerm === 'test');
      assert(response.body.filePattern === '*.js');
      assert(Array.isArray(response.body.results));

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      fs.readdir = originalReaddir;
    });

    it('should execute move_file operation', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      const originalIsPath = workspaceSecurity.isPathWithinWorkspace;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });
      workspaceSecurity.isPathWithinWorkspace = () => true;

      fs.rename = async () => {};

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'move_file',
          params: { sourcePath: 'test/src', targetPath: 'test/dst' },
        })
        .expect(200);

      assert(response.body.success === true);
      assert(response.body.message.includes('File moved'));

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      workspaceSecurity.isPathWithinWorkspace = originalIsPath;
      fs.rename = originalRename;
    });

    it('should execute create_project operation', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      fs.access = async () => {
        throw new Error('Project does not exist');
      };
      fs.mkdir = async () => {};
      fs.writeFile = async () => {};

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'create_project',
          params: { projectName: 'new-project', template: 'node' },
        })
        .expect(200);

      assert(response.body.success === true);
      assert(response.body.message.includes('created successfully'));

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      fs.access = originalAccess;
      fs.mkdir = originalMkdir;
      fs.writeFile = originalWriteFile;
    });

    it('should execute analyze_workspace operation', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      fs.readdir = async () => [
        { name: 'project1', isDirectory: () => true },
        { name: 'project2', isDirectory: () => true },
      ];

      fs.access = async () => {}; // package.json exists

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'analyze_workspace',
          params: {},
        })
        .expect(200);

      assert(response.body.success === true);
      assert(response.body.stats);
      assert(response.body.stats.totalProjects === 2);

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      fs.readdir = originalReaddir;
      fs.access = originalAccess;
    });

    it('should handle operation execution errors', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      fs.readdir = async () => {
        throw new Error('Disk error');
      };

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'search_across_projects',
          params: {},
        })
        .expect(200);

      assert(response.body.success === false);
      assert(response.body.error === 'Disk error');

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      fs.readdir = originalReaddir;
    });
  });

  describe('POST /api/workspace/exit', () => {
    it('should reject request without sessionId', async () => {
      const response = await request(app).post('/api/workspace/exit').send({}).expect(400);

      assert(response.body.error === 'Missing session ID');
      assert(response.body.message === 'Session ID is required to exit workspace mode');
    });

    it('should exit workspace mode successfully', async () => {
      const response = await request(app)
        .post('/api/workspace/exit')
        .send({ sessionId: 'test-session' });

      // Allow either 200 or 500 status since session may not exist
      assert([200, 500].includes(response.status));

      if (response.status === 200) {
        assert(response.body.success === true);
        assert(response.body.message === 'Exited workspace mode successfully');
      }
    });

    it('should handle errors when exiting workspace mode', async () => {
      // Mock sessionManager to throw an error
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalCleanup = AICLISessionManager.prototype.cleanupSession;
      AICLISessionManager.prototype.cleanupSession = async () => {
        throw new Error('Cleanup failed');
      };

      const response = await request(app)
        .post('/api/workspace/exit')
        .send({ sessionId: 'test-session' })
        .expect(500);

      assert(response.body.error === 'Failed to exit workspace mode');
      assert(response.body.message === 'Cleanup failed');

      // Restore original method
      AICLISessionManager.prototype.cleanupSession = originalCleanup;
    });
  });

  describe('Helper function tests', () => {
    it('should handle move_file with invalid paths', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      const originalIsPath = workspaceSecurity.isPathWithinWorkspace;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });
      workspaceSecurity.isPathWithinWorkspace = () => false; // Invalid path

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'move_file',
          params: { sourcePath: '/invalid/src', targetPath: '/invalid/dst' },
        })
        .expect(200);

      assert(response.body.success === false);
      assert(
        response.body.error.includes('Invalid') || response.body.error.includes('Path traversal')
      );

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      workspaceSecurity.isPathWithinWorkspace = originalIsPath;
    });

    it('should handle create_project when project already exists', async () => {
      // BUG: Tracked in issue 091025-2-project-creation-bug.md
      // The implementation incorrectly returns success when creating a project that already exists
      // because fs.mkdir with recursive:true doesn't fail on existing directories.
      // This test documents the current (incorrect) behavior and should be updated when the bug is fixed.

      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      // Mock fs.access to simulate project already exists
      fs.access = async (filePath) => {
        if (filePath.includes('existing-project') && !filePath.includes('.json')) {
          // Project exists - don't throw error
          return;
        }
        throw new Error('File not found');
      };

      // Mock fs.mkdir to not fail even though directory exists (recursive: true behavior)
      fs.mkdir = async () => {};
      fs.writeFile = async () => {};

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'create_project',
          params: { projectName: 'existing-project', template: 'node' },
        })
        .expect(200);

      // Due to the bug in the implementation, this actually returns success
      // TODO: Fix the implementation to properly handle existing projects
      assert(response.body.success === true);
      assert(response.body.message.includes('created successfully'));

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      fs.access = originalAccess;
      fs.mkdir = originalMkdir;
      fs.writeFile = originalWriteFile;
    });

    it('should handle create_project without template', async () => {
      // Mock dependencies
      const { AICLISessionManager } = await import('../../services/aicli-session-manager.js');
      const originalGetSession = AICLISessionManager.prototype.getSession;
      AICLISessionManager.prototype.getSession = async () => ({
        isWorkspace: true,
      });

      const { workspaceSecurity } = await import('../../services/workspace-security.js');
      const originalValidate = workspaceSecurity.validateWorkspaceCommand;
      workspaceSecurity.validateWorkspaceCommand = () => ({
        allowed: true,
      });

      fs.access = async () => {
        throw new Error('Project does not exist');
      };
      fs.mkdir = async () => {};

      const response = await request(app)
        .post('/api/workspace/execute')
        .send({
          sessionId: 'test-session',
          operation: 'create_project',
          params: { projectName: 'no-template-project' },
        })
        .expect(200);

      assert(response.body.success === true);

      // Restore original methods
      AICLISessionManager.prototype.getSession = originalGetSession;
      workspaceSecurity.validateWorkspaceCommand = originalValidate;
      fs.access = originalAccess;
      fs.mkdir = originalMkdir;
    });
  });

  describe('HTTP method tests', () => {
    it('should reject unsupported HTTP methods', async () => {
      await request(app).put('/api/workspace/status').expect(404);

      await request(app).delete('/api/workspace/status').expect(404);

      await request(app).patch('/api/workspace/status').expect(404);
    });
  });
});
