/**
 * Workspace API Routes
 * Handles workspace mode operations for cross-project functionality
 */

import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import rateLimit from 'express-rate-limit';
import { createLogger } from '../utils/logger.js';
import { workspaceSecurity } from '../services/workspace-security.js';
import { ServerConfig } from '../config/server-config.js';
import { AICLISessionManager } from '../services/aicli-session-manager.js';

const router = express.Router();
const logger = createLogger('WorkspaceAPI');
const config = new ServerConfig();

// Rate limiter for workspace operations (disabled in tests)
const workspaceLimiter =
  process.env.NODE_ENV === 'test'
    ? (req, res, next) => next() // Pass-through middleware for tests
    : rateLimit({
        windowMs: 60 * 1000, // 1 minute
        max: 20, // limit each IP to 20 requests per windowMs
        standardHeaders: true,
        legacyHeaders: false,
        message: { error: 'Too many workspace requests, please try again later.' },
      });

/**
 * Setup workspace routes
 * @param {express.Application} app - Express application
 * @param {AICLIService} aicliService - AICLI service instance
 */
export function setupWorkspaceRoutes(app, _aicliService) {
  const sessionManager = new AICLISessionManager();

  /**
   * GET /api/workspace/status
   * Check workspace mode availability and configuration
   */
  router.get('/workspace/status', workspaceLimiter, async (req, res) => {
    try {
      const workspaceRoot = config.configPath;
      const restrictions = workspaceSecurity.getWorkspaceRestrictions();

      res.json({
        available: true,
        workspaceRoot,
        restrictions,
        message: 'Workspace mode is available',
      });
    } catch (error) {
      logger.error('Failed to get workspace status', { error: error.message });
      res.status(500).json({
        error: 'Failed to get workspace status',
        message: error.message,
      });
    }
  });

  /**
   * POST /api/workspace/enter
   * Enter workspace mode and create a workspace session
   */
  router.post('/workspace/enter', workspaceLimiter, async (req, res) => {
    try {
      const { deviceToken } = req.body;

      if (!deviceToken) {
        return res.status(400).json({
          error: 'Missing device token',
          message: 'Device token is required for workspace mode',
        });
      }

      const workspaceRoot = config.configPath;
      const workspaceContext = workspaceSecurity.createWorkspaceContext(workspaceRoot);

      // Create a special workspace session
      const sessionResult = await sessionManager.createInteractiveSession(
        workspaceContext.sessionId,
        'Entering workspace mode for cross-project operations',
        '__workspace__',
        {
          workspace: true,
          skipPermissions: false,
          deviceToken,
        }
      );

      logger.info('Workspace mode entered', {
        sessionId: sessionResult.sessionId,
        workspaceRoot,
      });

      res.json({
        success: true,
        sessionId: sessionResult.sessionId,
        workspaceContext,
        message: 'Entered workspace mode successfully',
      });
    } catch (error) {
      logger.error('Failed to enter workspace mode', { error: error.message });
      res.status(500).json({
        error: 'Failed to enter workspace mode',
        message: error.message,
      });
    }
  });

  /**
   * GET /api/workspace/projects
   * List all projects in the workspace
   */
  router.get('/workspace/projects', workspaceLimiter, async (req, res) => {
    try {
      const workspaceRoot = config.configPath;

      // Read all directories in the workspace
      const items = await fs.readdir(workspaceRoot, { withFileTypes: true });

      // Filter for directories and gather project info
      const projects = await Promise.all(
        items
          .filter((item) => item.isDirectory() && !item.name.startsWith('.'))
          .map(async (item) => {
            const projectPath = path.join(workspaceRoot, item.name);
            const projectInfo = {
              name: item.name,
              path: projectPath,
              type: 'folder',
            };

            // Try to get additional project info
            try {
              const packageJsonPath = path.join(projectPath, 'package.json');
              const packageJson = await fs.readFile(packageJsonPath, 'utf-8');
              const packageData = JSON.parse(packageJson);
              projectInfo.description = packageData.description;
              projectInfo.projectType = 'node';
              projectInfo.version = packageData.version;
            } catch (err) {
              // Not a Node project or no package.json
            }

            // Check for other project types
            try {
              const pomPath = path.join(projectPath, 'pom.xml');
              await fs.access(pomPath);
              projectInfo.projectType = 'maven';
            } catch (err) {
              // Not a Maven project
            }

            try {
              const gradlePath = path.join(projectPath, 'build.gradle');
              await fs.access(gradlePath);
              projectInfo.projectType = 'gradle';
            } catch (err) {
              // Not a Gradle project
            }

            // Get last modified time
            const stats = await fs.stat(projectPath);
            projectInfo.lastModified = stats.mtime.toISOString();

            return projectInfo;
          })
      );

      res.json({
        workspaceRoot,
        projectCount: projects.length,
        projects: projects.sort((a, b) => a.name.localeCompare(b.name)),
      });
    } catch (error) {
      logger.error('Failed to list workspace projects', { error: error.message });
      res.status(500).json({
        error: 'Failed to list workspace projects',
        message: error.message,
      });
    }
  });

  /**
   * POST /api/workspace/execute
   * Execute a cross-project operation in workspace mode
   */
  router.post('/workspace/execute', workspaceLimiter, async (req, res) => {
    try {
      const { sessionId, operation, params } = req.body;

      if (!sessionId || !operation) {
        return res.status(400).json({
          error: 'Missing required parameters',
          message: 'sessionId and operation are required',
        });
      }

      // Verify session is a workspace session
      const session = await sessionManager.getSession(sessionId);
      if (!session || !session.isWorkspace) {
        return res.status(403).json({
          error: 'Invalid workspace session',
          message: 'This operation requires an active workspace session',
        });
      }

      const workspaceRoot = config.configPath;

      // Validate the command
      const validation = workspaceSecurity.validateWorkspaceCommand(
        {
          operation,
          ...params,
        },
        workspaceRoot
      );

      if (!validation.allowed) {
        return res.status(403).json({
          error: 'Operation not allowed',
          message: validation.message,
        });
      }

      // Execute the operation based on type
      let result;
      switch (operation) {
        case 'search_across_projects':
          result = await searchAcrossProjects(workspaceRoot, params);
          break;
        case 'move_file':
          result = await moveFileBetweenProjects(workspaceRoot, params);
          break;
        case 'create_project':
          result = await createNewProject(workspaceRoot, params);
          break;
        case 'analyze_workspace':
          result = await analyzeWorkspace(workspaceRoot, params);
          break;
        default:
          return res.status(400).json({
            error: 'Unknown operation',
            message: `Operation '${operation}' is not implemented`,
          });
      }

      logger.info('Workspace operation executed', {
        sessionId,
        operation,
        success: result.success,
      });

      res.json(result);
    } catch (error) {
      logger.error('Failed to execute workspace operation', {
        error: error.message,
        operation: req.body.operation,
      });
      res.status(500).json({
        error: 'Failed to execute workspace operation',
        message: error.message,
      });
    }
  });

  /**
   * POST /api/workspace/exit
   * Exit workspace mode and clean up session
   */
  router.post('/workspace/exit', workspaceLimiter, async (req, res) => {
    try {
      const { sessionId } = req.body;

      if (!sessionId) {
        return res.status(400).json({
          error: 'Missing session ID',
          message: 'Session ID is required to exit workspace mode',
        });
      }

      // Clean up the workspace session
      await sessionManager.cleanupSession(sessionId);

      logger.info('Exited workspace mode', { sessionId });

      res.json({
        success: true,
        message: 'Exited workspace mode successfully',
      });
    } catch (error) {
      logger.error('Failed to exit workspace mode', { error: error.message });
      res.status(500).json({
        error: 'Failed to exit workspace mode',
        message: error.message,
      });
    }
  });

  // Mount routes
  app.use('/api', router);
}

// Helper functions for workspace operations

async function searchAcrossProjects(workspaceRoot, params) {
  const { searchTerm, filePattern } = params;
  const results = [];

  try {
    const projects = await fs.readdir(workspaceRoot, { withFileTypes: true });

    for (const project of projects) {
      if (!project.isDirectory() || project.name.startsWith('.')) continue;

      const _projectPath = path.join(workspaceRoot, project.name);
      // Here you would implement actual search logic
      // For now, returning a placeholder
      // TODO: Use _projectPath for actual search implementation
      results.push({
        project: project.name,
        matches: 0,
      });
    }

    return {
      success: true,
      searchTerm,
      filePattern,
      results,
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
}

async function moveFileBetweenProjects(workspaceRoot, params) {
  const { sourcePath, targetPath } = params;

  try {
    // Validate input types first
    if (!sourcePath || typeof sourcePath !== 'string') {
      throw new Error('Invalid source path');
    }
    if (!targetPath || typeof targetPath !== 'string') {
      throw new Error('Invalid target path');
    }

    // Remove null bytes and normalize paths
    const cleanedSource = String(sourcePath).replace(/\0/g, '');
    const cleanedTarget = String(targetPath).replace(/\0/g, '');

    // Remove any parent directory references
    const normalizedSource = path.normalize(cleanedSource).replace(/^(\.\.([/\\]|$))+/, '');
    const normalizedTarget = path.normalize(cleanedTarget).replace(/^(\.\.([/\\]|$))+/, '');

    // Resolve to absolute paths within workspace
    const safeSourcePath = path.resolve(workspaceRoot, normalizedSource);
    const safeTargetPath = path.resolve(workspaceRoot, normalizedTarget);

    // Validate paths are within workspace bounds
    const workspaceResolved = path.resolve(workspaceRoot);
    if (!safeSourcePath.startsWith(workspaceResolved) || !safeTargetPath.startsWith(workspaceResolved)) {
      throw new Error('Path traversal attempt detected');
    }

    // Additional validation using workspace security
    if (
      !workspaceSecurity.isPathWithinWorkspace(safeSourcePath, workspaceRoot) ||
      !workspaceSecurity.isPathWithinWorkspace(safeTargetPath, workspaceRoot)
    ) {
      throw new Error('Invalid path: outside workspace bounds');
    }

    // Move the file with validated paths
    await fs.rename(safeSourcePath, safeTargetPath);

    return {
      success: true,
      message: `File moved successfully`,
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
}

async function createNewProject(workspaceRoot, params) {
  const { projectName, template } = params;

  try {
    // Validate project name to prevent path traversal
    if (!projectName || /[./\\]/.test(projectName)) {
      throw new Error('Invalid project name');
    }

    const projectPath = path.resolve(workspaceRoot, projectName);

    // Extra validation to ensure path is within workspace
    if (!projectPath.startsWith(path.resolve(workspaceRoot))) {
      throw new Error('Invalid project path');
    }

    // Check if project already exists
    try {
      await fs.access(projectPath);
      throw new Error(`Project '${projectName}' already exists`);
    } catch (err) {
      // Project doesn't exist, which is good
    }

    // Create project directory
    await fs.mkdir(projectPath, { recursive: true });

    // Create basic structure based on template
    if (template === 'node') {
      const packageJson = {
        name: projectName,
        version: '0.1.0',
        description: `${projectName} project`,
        main: 'index.js',
        scripts: {
          start: 'node index.js',
          test: 'echo "Error: no test specified" && exit 1',
        },
      };

      await fs.writeFile(
        path.resolve(projectPath, 'package.json'),
        JSON.stringify(packageJson, null, 2)
      );

      await fs.writeFile(
        path.resolve(projectPath, 'index.js'),
        `// Entry point for ${projectName}\n`
      );

      await fs.writeFile(
        path.resolve(projectPath, 'README.md'),
        `# ${projectName}\n\n## Description\n\nProject created in workspace mode.\n`
      );
    }

    return {
      success: true,
      projectPath,
      message: `Project '${projectName}' created successfully`,
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
}

async function analyzeWorkspace(workspaceRoot, _params) {
  try {
    const items = await fs.readdir(workspaceRoot, { withFileTypes: true });
    const projects = items.filter((item) => item.isDirectory() && !item.name.startsWith('.'));

    const stats = {
      totalProjects: projects.length,
      projectTypes: {},
      totalSize: 0,
    };

    for (const project of projects) {
      const projectPath = path.join(workspaceRoot, project.name);

      // Check project type
      try {
        await fs.access(path.join(projectPath, 'package.json'));
        stats.projectTypes.node = (stats.projectTypes.node || 0) + 1;
      } catch (err) {
        stats.projectTypes.other = (stats.projectTypes.other || 0) + 1;
      }
    }

    return {
      success: true,
      workspaceRoot,
      stats,
    };
  } catch (error) {
    return {
      success: false,
      error: error.message,
    };
  }
}
