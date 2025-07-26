import express from 'express';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export function setupClaudeStatusRoutes(app, claudeService) {
  const router = express.Router();

  // Get Claude CLI status and version
  router.get('/claude/status', async (req, res) => {
    try {
      // Check if Claude CLI is installed using the same path as ClaudeCodeService
      let version = null;
      let isInstalled = false;
      let path = claudeService.claudeCommand;

      try {
        // Use the path from ClaudeCodeService
        const { stdout: versionOutput } = await execAsync(`${claudeService.claudeCommand} --version`);
        version = versionOutput.trim();
        isInstalled = true;
      } catch (error) {
        console.log('Claude CLI not found at:', claudeService.claudeCommand);
        console.error('Error:', error.message);
        
        // Try to check availability through the service
        isInstalled = await claudeService.checkAvailability();
      }

      // Get active sessions info
      const activeSessions = claudeService.getActiveSessions();
      const sessionDetails = activeSessions.map(sessionId => {
        const session = claudeService.activeSessions.get(sessionId);
        return {
          sessionId,
          workingDirectory: session?.workingDirectory || 'unknown',
          isActive: session?.isActive || false,
          createdAt: session?.createdAt ? new Date(session.createdAt).toISOString() : null,
          lastActivity: session?.lastActivity ? new Date(session.lastActivity).toISOString() : null,
          pid: session?.process?.pid || null
        };
      });

      // Get system info
      let systemInfo = {};
      try {
        const { stdout: nodeVersion } = await execAsync('node --version');
        systemInfo.nodeVersion = nodeVersion.trim();
        systemInfo.platform = process.platform;
        systemInfo.architecture = process.arch;
      } catch (error) {
        console.error('Failed to get system info:', error);
      }

      res.json({
        claude: {
          installed: isInstalled,
          version,
          path,
          available: isInstalled && claudeService.isAvailable()
        },
        sessions: {
          active: activeSessions.length,
          max: claudeService.maxSessions,
          details: sessionDetails
        },
        system: systemInfo,
        service: {
          uptime: process.uptime(),
          memory: process.memoryUsage(),
          pid: process.pid
        }
      });
    } catch (error) {
      console.error('Error getting Claude status:', error);
      res.status(500).json({
        error: 'Failed to get Claude status',
        message: error.message
      });
    }
  });

  // Get detailed session info
  router.get('/claude/sessions/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const session = claudeService.activeSessions.get(sessionId);

      if (!session) {
        return res.status(404).json({
          error: 'Session not found',
          message: `No active session with ID: ${sessionId}`
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
          exitCode: session.process?.exitCode || null
        }
      });
    } catch (error) {
      console.error('Error getting session info:', error);
      res.status(500).json({
        error: 'Failed to get session info',
        message: error.message
      });
    }
  });

  // Test Claude CLI execution
  router.post('/claude/test', async (req, res) => {
    try {
      const { prompt = 'Hello, Claude!' } = req.body;

      console.log('Testing Claude CLI with prompt:', prompt);
      
      const result = await claudeService.sendOneTimePrompt(prompt, {
        format: 'json',
        workingDirectory: process.cwd()
      });

      res.json({
        success: true,
        prompt,
        response: result,
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      console.error('Claude CLI test failed:', error);
      res.status(500).json({
        success: false,
        error: 'Claude CLI test failed',
        message: error.message,
        details: error.stack
      });
    }
  });

  // Debug Claude CLI with different command types
  router.post('/claude/debug/:testType', async (req, res) => {
    try {
      const { testType } = req.params;
      const validTypes = ['version', 'help', 'simple', 'json'];
      
      if (!validTypes.includes(testType)) {
        return res.status(400).json({
          error: 'Invalid test type',
          message: `Test type must be one of: ${validTypes.join(', ')}`,
          available: validTypes
        });
      }

      console.log(`🧪 Running Claude CLI debug test: ${testType}`);
      
      const result = await claudeService.testClaudeCommand(testType);

      res.json({
        success: true,
        testType,
        result,
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      console.error(`Claude CLI debug test (${req.params.testType}) failed:`, error);
      res.status(500).json({
        success: false,
        testType: req.params.testType,
        error: 'Claude CLI debug test failed',
        message: error.message,
        details: error.stack
      });
    }
  });

  // Get Claude CLI logs for a session
  router.get('/claude/sessions/:sessionId/logs', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const { lines = 100 } = req.query;

      // This would need to be implemented in the ClaudeCodeService
      // to capture and store logs per session
      res.json({
        sessionId,
        logs: [],
        message: 'Log capture not yet implemented'
      });
    } catch (error) {
      console.error('Error getting session logs:', error);
      res.status(500).json({
        error: 'Failed to get session logs',
        message: error.message
      });
    }
  });

  // Mount routes
  app.use('/api', router);
}