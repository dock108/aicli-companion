import express from 'express';
import { authenticate } from '../middleware/auth.js';

/**
 * Setup session routes
 */
export function setupSessionRoutes(app, aicliService) {
  const router = express.Router();

  /**
   * Continue an existing session
   * iOS TODO: Use this endpoint to continue with existing session ID
   */
  router.post('/api/sessions/continue', authenticate, async (req, res) => {
    const { sessionId, workingDirectory } = req.body;

    if (!sessionId || !workingDirectory) {
      return res.status(400).json({
        error: 'sessionId and workingDirectory are required',
      });
    }

    try {
      const session = await aicliService.sessionManager.getSession(sessionId);

      if (!session) {
        return res.status(404).json({ error: 'Session not found' });
      }

      // Verify working directory matches
      if (session.workingDirectory !== workingDirectory) {
        // TODO: [QUESTION] Should we allow session migration to new directory?
        // Current behavior: reject mismatched directories
        return res.status(400).json({
          error: 'Working directory mismatch',
          expected: session.workingDirectory,
          provided: workingDirectory,
        });
      }

      // Mark session as foregrounded (not backgrounded)
      await aicliService.sessionManager.markSessionForegrounded(sessionId);

      res.json({
        success: true,
        sessionId,
        conversationStarted: session.conversationStarted,
        workingDirectory: session.workingDirectory,
        initialPrompt: session.initialPrompt,
        createdAt: session.createdAt,
        lastActivity: session.lastActivity,
      });
    } catch (error) {
      console.error('Session continuation error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * Get session status
   */
  router.get('/api/sessions/:sessionId', authenticate, async (req, res) => {
    const { sessionId } = req.params;

    try {
      const session = await aicliService.sessionManager.getSession(sessionId);

      if (!session) {
        return res.status(404).json({ error: 'Session not found' });
      }

      res.json({
        sessionId,
        workingDirectory: session.workingDirectory,
        conversationStarted: session.conversationStarted,
        isActive: session.isActive,
        isBackgrounded: session.isBackgrounded,
        createdAt: session.createdAt,
        lastActivity: session.lastActivity,
      });
    } catch (error) {
      console.error('Session status error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  /**
   * List all sessions
   */
  router.get('/api/sessions', authenticate, async (req, res) => {
    try {
      const sessions = aicliService.sessionManager.getAllSessions();

      res.json({
        sessions: sessions.map((session) => ({
          sessionId: session.sessionId,
          workingDirectory: session.workingDirectory,
          conversationStarted: session.conversationStarted,
          isActive: session.isActive,
          isBackgrounded: session.isBackgrounded,
          createdAt: session.createdAt,
          lastActivity: session.lastActivity,
        })),
        count: sessions.length,
      });
    } catch (error) {
      console.error('Session list error:', error);
      res.status(500).json({ error: error.message });
    }
  });

  app.use(router);
}
