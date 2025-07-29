import express from 'express';
import { exec } from 'child_process';
import util from 'util';
import { promisify } from 'util';
import rateLimit from 'express-rate-limit';

// Rate limiter for expensive system command routes
const aicliStatusLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10, // limit each IP to 10 requests per windowMs
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});

const execAsync = promisify(exec);

export function setupAICLIStatusRoutes(app, aicliService) {
  const router = express.Router();

  // Get AICLI CLI status and version
  router.get('/aicli/status', aicliStatusLimiter, async (req, res) => {
    try {
      // Check if AICLI CLI is installed using the same path as AICLICodeService
      let version = null;
      let isInstalled = false;
      const path = aicliService.aicliCommand;

      try {
        // Use the path from AICLICodeService
        const { stdout: versionOutput } = await execAsync(`${aicliService.aicliCommand} --version`);
        version = versionOutput.trim();
        isInstalled = true;
      } catch (error) {
        console.log('AICLI CLI not found at:', aicliService.aicliCommand);
        console.error('Error:', error.message);

        // Try to check availability through the service
        isInstalled = await aicliService.checkAvailability();
      }

      // Get active sessions info
      const activeSessions = aicliService.getActiveSessions();
      const sessionDetails = activeSessions.map((sessionId) => {
        const session = aicliService.activeSessions.get(sessionId);
        return {
          sessionId,
          workingDirectory: session?.workingDirectory || 'unknown',
          isActive: session?.isActive || false,
          createdAt: session?.createdAt ? new Date(session.createdAt).toISOString() : null,
          lastActivity: session?.lastActivity ? new Date(session.lastActivity).toISOString() : null,
          pid: session?.process?.pid || null,
        };
      });

      // Get system info
      const systemInfo = {};
      try {
        const { stdout: nodeVersion } = await execAsync('node --version');
        systemInfo.nodeVersion = nodeVersion.trim();
        systemInfo.platform = process.platform;
        systemInfo.architecture = process.arch;
      } catch (error) {
        console.error('Failed to get system info:', error);
      }

      res.json({
        aicli: {
          installed: isInstalled,
          version,
          path,
          available: isInstalled && aicliService.isAvailable(),
        },
        sessions: {
          active: activeSessions.length,
          max: aicliService.maxSessions,
          details: sessionDetails,
        },
        system: systemInfo,
        service: {
          uptime: process.uptime(),
          memory: process.memoryUsage(),
          pid: process.pid,
        },
      });
    } catch (error) {
      console.error('Error getting AICLI status:', error);
      res.status(500).json({
        error: 'Failed to get AICLI status',
        message: error.message,
      });
    }
  });

  // Get detailed session info
  router.get('/aicli/sessions/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const session = aicliService.activeSessions.get(sessionId);

      if (!session) {
        return res.status(404).json({
          error: 'Session not found',
          message: `No active session with ID: ${sessionId}`,
        });
      }

      res.json({
        sessionId,
        workingDirectory: session.workingDirectory,
        isActive: session.isActive,
        createdAt: new Date(session.createdAt).toISOString(),
        lastActivity: new Date(session.lastActivity).toISOString(),
        process: {
          pid: session.process?.pid || null,
          connected: session.process?.connected || false,
          signalCode: session.process?.signalCode || null,
          exitCode: session.process?.exitCode || null,
        },
      });
    } catch (error) {
      console.error('Error getting session info:', error);
      res.status(500).json({
        error: 'Failed to get session info',
        message: error.message,
      });
    }
  });

  // Test AICLI CLI execution
  router.post('/aicli/test', async (req, res) => {
    try {
      const { prompt = 'Hello, AICLI!' } = req.body;

      console.log('Testing AICLI CLI with prompt:', prompt);

      const result = await aicliService.sendOneTimePrompt(prompt, {
        format: 'json',
        workingDirectory: process.cwd(),
      });

      res.json({
        success: true,
        prompt,
        response: result,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error('AICLI CLI test failed:', error);
      res.status(500).json({
        success: false,
        error: 'AICLI CLI test failed',
        message: error.message,
        details: error.stack,
      });
    }
  });

  // Debug AICLI CLI with different command types
  router.post('/aicli/debug/:testType', async (req, res) => {
    try {
      const { testType } = req.params;
      const validTypes = ['version', 'help', 'simple', 'json'];

      if (!validTypes.includes(testType)) {
        return res.status(400).json({
          error: 'Invalid test type',
          message: `Test type must be one of: ${validTypes.join(', ')}`,
          available: validTypes,
        });
      }

      console.log(`🧪 Running AICLI CLI debug test: ${testType}`);

      const result = await aicliService.testAICLICommand(testType);

      res.json({
        success: true,
        testType,
        result,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      const sanitizedTestType = String(req.params.testType).replace(/[^a-zA-Z0-9_-]/g, '');
      console.error(util.format('AICLI CLI debug test (%s) failed:', sanitizedTestType), error);
      res.status(500).json({
        success: false,
        testType: req.params.testType,
        error: 'AICLI CLI debug test failed',
        message: error.message,
        details: error.stack,
      });
    }
  });

  // Get AICLI CLI logs for a session
  router.get('/aicli/sessions/:sessionId/logs', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { lines: _lines = 100 } = req.query;

      // This would need to be implemented in the AICLICodeService
      // to capture and store logs per session
      res.json({
        sessionId,
        logs: [],
        message: 'Log capture not yet implemented',
      });
    } catch (error) {
      console.error('Error getting session logs:', error);
      res.status(500).json({
        error: 'Failed to get session logs',
        message: error.message,
      });
    }
  });

  // Mount routes
  app.use('/api', router);
}
