import express from 'express';
import crypto from 'crypto';
import { promises as fs } from 'fs';
import path from 'path';
import { ServerConfig } from '../config/server-config.js';
import rateLimit from 'express-rate-limit';

export function setupProjectRoutes(app, claudeService) {
  const router = express.Router();
  const config = new ServerConfig();

  // Session management for active Claude CLI processes
  const activeSessions = new Map();

  // Get the configured project directory from config
  const getProjectsDir = () => {
    return config.configPath;
  };

  // Define rate limiter for projects list route
  const projectsListLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: {
      error: 'Too many requests',
      message: 'Please try again later.',
    },
  });

  // List all projects (folders) in the configured directory
  router.get('/projects', projectsListLimiter, async (req, res) => {
    try {
      const projectsDir = getProjectsDir();
      console.log('Listing projects from directory:', path.basename(projectsDir));

      // Read directory contents
      const items = await fs.readdir(projectsDir, { withFileTypes: true });

      // Filter for directories only and exclude hidden folders
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
      console.error('Error listing projects:', error);
      res.status(500).json({
        error: 'Failed to list projects',
        message: error.message,
      });
    }
  });

  // Define rate limiter for project info route
  const projectInfoLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: {
      error: 'Too many requests',
      message: 'Please try again later.',
    },
  });

  // Get specific project info
  router.get('/projects/:name', projectInfoLimiter, async (req, res) => {
    try {
      const { name } = req.params;
      const projectsDir = getProjectsDir();
      const projectPath = path.join(projectsDir, name);

      // Security check - prevent directory traversal
      const normalizedPath = path.normalize(projectPath);
      const normalizedBase = path.normalize(projectsDir);

      if (!normalizedPath.startsWith(normalizedBase)) {
        return res.status(403).json({
          error: 'Access denied',
          message: 'Invalid project path',
        });
      }

      // Check if project exists
      try {
        const stat = await fs.stat(projectPath);
        if (!stat.isDirectory()) {
          throw new Error('Not a directory');
        }
      } catch (error) {
        return res.status(404).json({
          error: 'Project not found',
          message: `Project '${name}' does not exist`,
        });
      }

      // Get project info
      const info = {
        name,
        path: projectPath,
        type: 'folder',
      };

      // Try to get additional info if available
      try {
        // Check for package.json
        const packageJsonPath = path.join(projectPath, 'package.json');
        const packageJson = await fs.readFile(packageJsonPath, 'utf-8');
        const packageData = JSON.parse(packageJson);
        info.description = packageData.description;
        info.projectType = 'node';
      } catch (error) {
        // Not a Node project or no package.json
      }

      res.json(info);
    } catch (error) {
      console.error('Error getting project info:', error);
      res.status(500).json({
        error: 'Failed to get project info',
        message: error.message,
      });
    }
  });

  // Start Claude CLI in a specific project directory
  router.post('/projects/:name/start', async (req, res) => {
    try {
      const { name } = req.params;
      const projectsDir = getProjectsDir();
      const projectPath = path.join(projectsDir, name);

      // Security check - prevent directory traversal
      const normalizedPath = path.normalize(projectPath);
      const normalizedBase = path.normalize(projectsDir);

      if (!normalizedPath.startsWith(normalizedBase)) {
        return res.status(403).json({
          error: 'Access denied',
          message: 'Invalid project path',
        });
      }

      // Check if project exists
      try {
        const stat = await fs.stat(projectPath);
        if (!stat.isDirectory()) {
          throw new Error('Not a directory');
        }
      } catch (error) {
        return res.status(404).json({
          error: 'Project not found',
          message: `Project '${name}' does not exist`,
        });
      }

      // Generate a session ID for this project session
      const randomBytes = crypto.randomBytes(12).toString('hex'); // 24-character hex string
      const sessionId = `project_${name}_${Date.now()}_${randomBytes}`;

      console.log(`Starting Claude CLI session for project: ${name}`);
      console.log(`Project path: ${projectPath}`);
      console.log(`Session ID: ${sessionId}`);

      // Check if Claude CLI is available first
      const isAvailable = await claudeService.checkAvailability();
      if (!isAvailable) {
        console.error('Claude CLI is not available on this system');
        return res.status(503).json({
          success: false,
          error: 'Claude CLI not available',
          message:
            'Claude CLI is not installed or not in PATH. Please install Claude CLI to use this feature.',
        });
      }

      try {
        // Start Claude CLI session using the ClaudeCodeService
        console.log(`📋 Creating Claude CLI session...`);
        const session = await claudeService.createInteractiveSession(
          sessionId,
          `Starting work in project: ${name}`,
          projectPath
        );

        console.log(`✅ Claude CLI session created successfully!`);
        console.log(`   Session ID: ${session.sessionId}`);
        console.log(`   Message: ${session.message}`);

        // Store session info for tracking
        const sessionInfo = {
          sessionId: session.sessionId,
          projectName: name,
          projectPath,
          status: 'running',
          startedAt: new Date().toISOString(),
          claudeSession: session,
        };
        activeSessions.set(session.sessionId, sessionInfo);

        console.log(`📊 Active sessions: ${activeSessions.size}`);
        console.log(`   Sessions: ${Array.from(activeSessions.keys()).join(', ')}`);

        // Return session info
        const responseSession = {
          sessionId: session.sessionId,
          projectName: name,
          projectPath,
          status: 'running',
          startedAt: sessionInfo.startedAt,
        };

        res.json({
          success: true,
          session: responseSession,
          message: `Claude CLI session started for project '${name}'`,
        });
      } catch (error) {
        console.error(`Failed to start Claude CLI for project ${name}:`, error);

        // Provide more specific error messages based on the error type
        let statusCode = 500;
        let errorType = 'Failed to start Claude CLI';
        let message = error.message;

        if (error.message.includes('Maximum number of sessions')) {
          statusCode = 429;
          errorType = 'Too many sessions';
          message =
            'Maximum number of Claude CLI sessions reached. Please close some sessions before starting new ones.';
        } else if (error.message.includes('not accessible')) {
          statusCode = 403;
          errorType = 'Permission denied';
          message = `Cannot access project directory: ${name}. Please check permissions.`;
        } else if (error.message.includes('Working directory must be within')) {
          statusCode = 403;
          errorType = 'Invalid project location';
          message = 'Project is outside the allowed directory. Please check server configuration.';
        }

        res.status(statusCode).json({
          success: false,
          error: errorType,
          message,
        });
      }
    } catch (error) {
      console.error('Error starting Claude CLI session:', error);
      res.status(500).json({
        error: 'Failed to start Claude CLI session',
        message: error.message,
      });
    }
  });

  // Get active sessions
  router.get('/sessions', async (req, res) => {
    try {
      const sessions = Array.from(activeSessions.values()).map((session) => ({
        sessionId: session.sessionId,
        projectPath: session.projectPath,
        status: session.status,
        startedAt: session.startedAt,
        stoppedAt: session.stoppedAt,
        error: session.error,
      }));

      res.json({
        sessions,
        count: sessions.length,
      });
    } catch (error) {
      console.error('Error listing sessions:', error);
      res.status(500).json({
        error: 'Failed to list sessions',
        message: error.message,
      });
    }
  });

  // Get specific session status
  router.get('/sessions/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const session = activeSessions.get(sessionId);

      if (!session) {
        return res.status(404).json({
          error: 'Session not found',
          message: `Session '${sessionId}' does not exist or has expired`,
        });
      }

      const sessionInfo = {
        sessionId: session.sessionId,
        projectPath: session.projectPath,
        status: session.status,
        startedAt: session.startedAt,
        stoppedAt: session.stoppedAt,
        error: session.error,
      };

      res.json(sessionInfo);
    } catch (error) {
      console.error('Error getting session status:', error);
      res.status(500).json({
        error: 'Failed to get session status',
        message: error.message,
      });
    }
  });

  // Stop a Claude CLI session
  router.delete('/sessions/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const session = activeSessions.get(sessionId);

      if (!session) {
        return res.status(404).json({
          error: 'Session not found',
          message: `Session '${sessionId}' does not exist or has expired`,
        });
      }

      if (session.status !== 'running') {
        return res.status(400).json({
          error: 'Session not running',
          message: `Session '${sessionId}' is not currently running (status: ${session.status})`,
        });
      }

      console.log(`Stopping Claude CLI session: ${sessionId}`);

      // Close the session using ClaudeCodeService
      try {
        await claudeService.closeSession(sessionId, 'user_requested');
        session.status = 'stopped';
        session.stoppedAt = new Date().toISOString();
      } catch (error) {
        console.error(`Error closing session: ${error.message}`);
      }

      res.json({
        success: true,
        message: `Claude CLI session '${sessionId}' is being stopped`,
        sessionId,
      });
    } catch (error) {
      console.error('Error stopping session:', error);
      res.status(500).json({
        error: 'Failed to stop session',
        message: error.message,
      });
    }
  });

  // Mount routes
  app.use('/api', router);
}
