import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { spawn } from 'child_process';
import { ServerConfig } from '../config/server-config.js';
import rateLimit from 'express-rate-limit';

export function setupProjectRoutes(app) {
  const router = express.Router();
  const config = new ServerConfig();

  // Session management for active Claude CLI processes
  const activeSessions = new Map();

  // Get the configured project directory from config
  const getProjectsDir = () => {
    return config.configPath;
  };

  // Helper function to start Claude CLI process
  const startClaudeProcess = (projectPath, sessionId) => {
    return new Promise((resolve, reject) => {
      console.log(`Starting Claude CLI in directory: ${projectPath}`);
      
      // Spawn Claude CLI process with the project directory as working directory
      const claudeProcess = spawn('claude', [], {
        cwd: projectPath,
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env }
      });

      const sessionInfo = {
        sessionId,
        process: claudeProcess,
        projectPath,
        status: 'running',
        startedAt: new Date().toISOString(),
        pid: claudeProcess.pid
      };

      // Handle process events
      claudeProcess.on('spawn', () => {
        console.log(`Claude CLI started with PID: ${claudeProcess.pid}`);
        sessionInfo.status = 'running';
        activeSessions.set(sessionId, sessionInfo);
        resolve(sessionInfo);
      });

      claudeProcess.on('error', (error) => {
        console.error(`Failed to start Claude CLI: ${error.message}`);
        sessionInfo.status = 'failed';
        sessionInfo.error = error.message;
        reject(error);
      });

      claudeProcess.on('exit', (code, signal) => {
        console.log(`Claude CLI process exited with code ${code}, signal ${signal}`);
        sessionInfo.status = 'stopped';
        sessionInfo.exitCode = code;
        sessionInfo.exitSignal = signal;
        sessionInfo.stoppedAt = new Date().toISOString();
        
        // Clean up session after a delay
        setTimeout(() => {
          activeSessions.delete(sessionId);
        }, 60000); // Keep session info for 1 minute after exit
      });

      // Store session immediately with 'starting' status
      sessionInfo.status = 'starting';
      activeSessions.set(sessionId, sessionInfo);
    });
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
      const sessionId = `project_${name}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

      console.log(`Starting Claude CLI session for project: ${name}`);
      console.log(`Project path: ${projectPath}`);
      console.log(`Session ID: ${sessionId}`);

      try {
        // Start Claude CLI process in the project directory
        const sessionInfo = await startClaudeProcess(projectPath, sessionId);
        
        // Return session info without the process object (not serializable)
        const responseSession = {
          sessionId: sessionInfo.sessionId,
          projectName: name,
          projectPath: sessionInfo.projectPath,
          status: sessionInfo.status,
          startedAt: sessionInfo.startedAt,
          pid: sessionInfo.pid
        };

        res.json({
          success: true,
          session: responseSession,
          message: `Claude CLI session started for project '${name}'`,
        });
      } catch (error) {
        console.error(`Failed to start Claude CLI for project ${name}:`, error);
        res.status(500).json({
          success: false,
          error: 'Failed to start Claude CLI',
          message: error.message,
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
      const sessions = Array.from(activeSessions.values()).map(session => ({
        sessionId: session.sessionId,
        projectPath: session.projectPath,
        status: session.status,
        startedAt: session.startedAt,
        stoppedAt: session.stoppedAt,
        pid: session.pid,
        exitCode: session.exitCode,
        error: session.error
      }));

      res.json({
        sessions,
        count: sessions.length
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
        pid: session.pid,
        exitCode: session.exitCode,
        error: session.error
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

      console.log(`Stopping Claude CLI session: ${sessionId} (PID: ${session.pid})`);
      
      // Gracefully terminate the process
      session.process.kill('SIGTERM');
      session.status = 'stopping';

      // Force kill after 5 seconds if it doesn't exit gracefully
      setTimeout(() => {
        if (session.status === 'stopping') {
          console.log(`Force killing Claude CLI session: ${sessionId}`);
          session.process.kill('SIGKILL');
        }
      }, 5000);

      res.json({
        success: true,
        message: `Claude CLI session '${sessionId}' is being stopped`,
        sessionId
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
