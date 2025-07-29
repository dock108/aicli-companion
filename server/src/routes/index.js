import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import { ServerConfig } from '../config/server-config.js';

export function setupRoutes(app, aicliService) {
  const router = express.Router();
  const config = new ServerConfig();

  // Validate working directory to prevent directory traversal
  const validateWorkingDirectory = (workingDirectory) => {
    if (!workingDirectory) return null;

    const baseDir = config.configPath;

    // Reject absolute paths to prevent bypassing baseDir
    if (path.isAbsolute(workingDirectory)) {
      throw new Error('Invalid working directory: Absolute paths are not allowed');
    }
    const requestedPath = path.resolve(baseDir, workingDirectory);
    const normalizedPath = path.normalize(requestedPath);
    const normalizedBase = path.normalize(baseDir);

    // Ensure the requested path is within the configured base directory
    if (!normalizedPath.startsWith(normalizedBase)) {
      throw new Error('Invalid working directory: Access denied');
    }

    return normalizedPath;
  };

  // Health check for AICLI Code service
  router.get('/health', async (req, res) => {
    try {
      const health = await aicliService.healthCheck();
      res.json(health);
    } catch (error) {
      res.status(500).json({
        status: 'error',
        message: error.message,
      });
    }
  });

  // Send a prompt to AICLI Code
  router.post('/ask', async (req, res) => {
    try {
      const { prompt, sessionId, format = 'json', workingDirectory } = req.body;

      if (!prompt) {
        return res.status(400).json({
          error: 'Prompt is required',
        });
      }

      // Validate working directory if provided
      let validatedWorkingDir;
      try {
        validatedWorkingDir = validateWorkingDirectory(workingDirectory);
      } catch (error) {
        return res.status(403).json({
          error: error.message,
        });
      }

      const response = await aicliService.sendPrompt(prompt, {
        sessionId,
        format,
        workingDirectory: validatedWorkingDir,
        streaming: false,
      });

      res.json(response);
    } catch (error) {
      console.error('Error in /ask endpoint:', error);
      res.status(500).json({
        error: error.message,
      });
    }
  });

  // Start a streaming session
  router.post('/stream/start', async (req, res) => {
    try {
      const { prompt, workingDirectory } = req.body;
      const sessionId = uuidv4();

      if (!prompt) {
        return res.status(400).json({
          error: 'Prompt is required',
        });
      }

      // Validate working directory if provided
      let validatedWorkingDir;
      try {
        validatedWorkingDir = validateWorkingDirectory(workingDirectory);
      } catch (error) {
        return res.status(403).json({
          error: error.message,
        });
      }

      const response = await aicliService.sendStreamingPrompt(prompt, {
        sessionId,
        workingDirectory: validatedWorkingDir,
      });

      res.json(response);
    } catch (error) {
      console.error('Error starting streaming session:', error);
      res.status(500).json({
        error: error.message,
      });
    }
  });

  // Send prompt to existing streaming session
  router.post('/stream/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { prompt } = req.body;

      if (!prompt) {
        return res.status(400).json({
          error: 'Prompt is required',
        });
      }

      const response = await aicliService.sendToExistingSession(sessionId, prompt);
      res.json(response);
    } catch (error) {
      console.error('Error sending to streaming session:', error);
      res.status(500).json({
        error: error.message,
      });
    }
  });

  // Close a streaming session
  router.delete('/stream/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const response = await aicliService.closeSession(sessionId);
      res.json(response);
    } catch (error) {
      console.error('Error closing session:', error);
      res.status(500).json({
        error: error.message,
      });
    }
  });

  // Get active sessions
  router.get('/sessions', (req, res) => {
    try {
      const sessions = aicliService.getActiveSessions();
      res.json({ sessions });
    } catch (error) {
      res.status(500).json({
        error: error.message,
      });
    }
  });

  // Handle permission prompts
  router.post('/permission/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { response: userResponse } = req.body;

      if (userResponse === undefined) {
        return res.status(400).json({
          error: 'Response is required (e.g., "y", "n", or custom response)',
        });
      }

      const result = await aicliService.handlePermissionPrompt(sessionId, userResponse);
      res.json(result);
    } catch (error) {
      console.error('Error handling permission prompt:', error);
      res.status(500).json({
        error: error.message,
      });
    }
  });

  // Get server info
  router.get('/info', (req, res) => {
    res.json({
      name: 'AICLI Companion Server',
      version: '1.0.0',
      aicliCodeAvailable: aicliService.isAvailable(),
      endpoints: {
        ask: 'POST /api/ask',
        streamStart: 'POST /api/stream/start',
        streamSend: 'POST /api/stream/:sessionId',
        streamClose: 'DELETE /api/stream/:sessionId',
        sessions: 'GET /api/sessions',
        permission: 'POST /api/permission/:sessionId',
        health: 'GET /api/health',
        projects: 'GET /api/projects',
        projectInfo: 'GET /api/projects/:name',
      },
      websocket: '/ws',
    });
  });

  // Mount API routes
  app.use('/api', router);
}
