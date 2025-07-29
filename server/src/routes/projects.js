import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { ServerConfig } from '../config/server-config.js';
import rateLimit from 'express-rate-limit';
import crypto from 'crypto';
export function setupProjectRoutes(app, aicliService) {
  const router = express.Router();
  const config = new ServerConfig();

  // Session management for active AICLI CLI processes
  const activeSessions = new Map();

  // Get the configured project directory from config
  const getProjectsDir = () => {
    return config.configPath;
  };

  // List all projects (folders) in the configured directory
  router.get('/projects', async (req, res) => {
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

  // Start AICLI CLI in a specific project directory
  router.post('/projects/:name/start', async (req, res) => {
    try {
      const { name } = req.params;
      const { continueSession, sessionId: existingSessionId } = req.body || {};
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

      // Generate a session ID for this project session or use existing
      const sessionId =
        continueSession && existingSessionId
          ? existingSessionId
          : `project_${name}_${Date.now()}_${crypto.randomBytes(9).toString('hex')}`;

      console.log(
        `${continueSession ? 'Continuing' : 'Starting'} AICLI CLI session for project: ${name}`
      );
      console.log(`Project path: ${projectPath}`);
      console.log(`Session ID: ${sessionId}`);
      console.log(`Continue session: ${continueSession || false}`);

      // Check if AICLI CLI is available first
      const isAvailable = await aicliService.checkAvailability();
      if (!isAvailable) {
        console.error('AICLI CLI is not available on this system');
        return res.status(503).json({
          success: false,
          error: 'AICLI CLI not available',
          message:
            'AICLI CLI is not installed or not in PATH. Please install AICLI CLI to use this feature.',
        });
      }

      try {
        // Check if we're continuing an existing session
        if (continueSession && existingSessionId) {
          // Check if session exists in active sessions
          const existingSession = activeSessions.get(existingSessionId);
          if (existingSession && existingSession.status === 'running') {
            console.log(`✅ Continuing existing AICLI CLI session: ${existingSessionId}`);

            // Return existing session info
            const responseSession = {
              sessionId: existingSession.sessionId,
              projectName: name,
              projectPath,
              status: 'running',
              startedAt: existingSession.startedAt,
            };

            return res.json({
              success: true,
              session: responseSession,
              message: `Continuing AICLI CLI session for project '${name}'`,
              continued: true,
            });
          }
        }

        // Start AICLI CLI session using the AICLIService
        console.log(`📋 Creating AICLI CLI session...`);
        const session = await aicliService.createInteractiveSession(
          sessionId,
          continueSession
            ? `Continuing work in project: ${name}. Previous session context may be available.`
            : `Starting work in project: ${name}`,
          projectPath
        );

        console.log(`✅ AICLI CLI session created successfully!`);
        console.log(`   Session ID: ${session.sessionId}`);
        console.log(`   Message: ${session.message}`);

        // Store session info for tracking
        const sessionInfo = {
          sessionId: session.sessionId,
          projectName: name,
          projectPath,
          status: 'running',
          startedAt: new Date().toISOString(),
          aicliSession: session,
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
          message: `AICLI CLI session started for project '${name}'`,
        });
      } catch (error) {
        console.error(`Failed to start AICLI CLI for project ${name}:`, error);

        // Provide more specific error messages based on the error type
        let statusCode = 500;
        let errorType = 'Failed to start AICLI CLI';
        let message = error.message;

        if (error.message.includes('Maximum number of sessions')) {
          statusCode = 429;
          errorType = 'Too many sessions';
          message =
            'Maximum number of AICLI CLI sessions reached. Please close some sessions before starting new ones.';
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
      console.error('Error starting AICLI CLI session:', error);
      res.status(500).json({
        error: 'Failed to start AICLI CLI session',
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

  // Stop an AICLI CLI session
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

      console.log(`Stopping AICLI CLI session: ${sessionId}`);

      // Close the session using AICLIService
      try {
        await aicliService.closeSession(sessionId, 'user_requested');
        session.status = 'stopped';
        session.stoppedAt = new Date().toISOString();
      } catch (error) {
        console.error(`Error closing session: ${error.message}`);
      }

      res.json({
        success: true,
        message: `AICLI CLI session '${sessionId}' is being stopped`,
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
