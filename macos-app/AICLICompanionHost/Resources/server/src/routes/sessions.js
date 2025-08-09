import express from 'express';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('SessionsAPI');
const router = express.Router();

/**
 * GET /api/sessions - List all active sessions
 */
router.get('/', async (req, res) => {
  try {
    const aicliService = req.app.get('aicliService');
    const sessions = aicliService.sessionManager.getAllSessions();

    res.json({
      success: true,
      sessions,
      count: sessions.length,
    });
  } catch (error) {
    logger.error('Failed to get sessions', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve sessions',
    });
  }
});

/**
 * GET /api/sessions/:sessionId/status - Get session status
 */
router.get('/:sessionId/status', async (req, res) => {
  const { sessionId } = req.params;

  try {
    const aicliService = req.app.get('aicliService');
    const status = aicliService.sessionManager.getSessionStatus(sessionId);

    if (!status) {
      return res.status(404).json({
        success: false,
        error: 'Session not found',
        hasNewMessages: false,
      });
    }

    // Check if there are completed messages that haven't been sent
    const buffer = aicliService.sessionManager.getSessionBuffer(sessionId);
    const hasNewMessages = buffer && buffer.assistantMessages.length > 0;

    res.json({
      success: true,
      hasNewMessages,
      messageCount: buffer?.assistantMessages.length || 0,
      ...status,
    });
  } catch (error) {
    logger.error('Failed to get session status', { sessionId, error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve session status',
      hasNewMessages: false,
    });
  }
});

/**
 * DELETE /api/sessions/:sessionId - Kill a session
 */
router.delete('/:sessionId', async (req, res) => {
  const { sessionId } = req.params;

  logger.info('Killing session', { sessionId });

  try {
    const aicliService = req.app.get('aicliService');
    const killed = await aicliService.sessionManager.killSession(sessionId);

    if (!killed) {
      return res.status(404).json({
        success: false,
        error: 'Session not found',
      });
    }

    res.json({
      success: true,
      message: 'Session terminated',
      sessionId,
    });
  } catch (error) {
    logger.error('Failed to kill session', { sessionId, error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to terminate session',
    });
  }
});

/**
 * POST /api/sessions/:sessionId/keepalive - Reset session timeout
 */
router.post('/:sessionId/keepalive', async (req, res) => {
  const { sessionId } = req.params;

  logger.info('Keeping session alive', { sessionId });

  try {
    const aicliService = req.app.get('aicliService');
    const kept = aicliService.sessionManager.keepSessionAlive(sessionId);

    if (!kept) {
      return res.status(404).json({
        success: false,
        error: 'Session not found',
      });
    }

    // Get updated status
    const status = aicliService.sessionManager.getSessionStatus(sessionId);

    res.json({
      success: true,
      message: 'Session timeout reset',
      ...status,
    });
  } catch (error) {
    logger.error('Failed to keep session alive', { sessionId, error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to reset session timeout',
    });
  }
});

/**
 * GET /api/sessions/claude - Get all Claude sessions being tracked
 */
router.get('/claude', async (req, res) => {
  try {
    const aicliService = req.app.get('aicliService');
    const sessions = [];

    // Get Claude sessions from session manager
    for (const [sessionId, sessionData] of aicliService.sessionManager.claudeSessions) {
      const now = Date.now();
      const timeSinceActivity = now - sessionData.lastActivity;
      const hoursInactive = Math.floor(timeSinceActivity / (60 * 60 * 1000));
      const minutesInactive = Math.floor((timeSinceActivity % (60 * 60 * 1000)) / (60 * 1000));

      sessions.push({
        sessionId,
        lastActivity: new Date(sessionData.lastActivity).toISOString(),
        inactiveTime: `${hoursInactive}h ${minutesInactive}m`,
        expired: sessionData.expired || false,
        warningsSent: sessionData.warningsSent || [],
        hoursUntilExpiry: sessionData.expired ? 0 : Math.max(0, 24 - hoursInactive),
      });
    }

    // Sort by last activity (most recent first)
    sessions.sort((a, b) => new Date(b.lastActivity) - new Date(a.lastActivity));

    res.json({
      success: true,
      count: sessions.length,
      expiredCount: sessions.filter((s) => s.expired).length,
      activeCount: sessions.filter((s) => !s.expired).length,
      sessions,
    });
  } catch (error) {
    logger.error('Failed to get Claude sessions', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve Claude sessions',
    });
  }
});

/**
 * POST /api/sessions/claude/cleanup - Manually trigger cleanup of expired sessions
 */
router.post('/claude/cleanup', async (req, res) => {
  try {
    const aicliService = req.app.get('aicliService');
    const cleanedCount = aicliService.sessionManager.cleanupExpiredClaudeSessions();

    logger.info('Manually triggered Claude session cleanup', { cleanedCount });

    res.json({
      success: true,
      message: `Cleaned up ${cleanedCount} expired Claude session${cleanedCount === 1 ? '' : 's'}`,
      cleanedCount,
    });
  } catch (error) {
    logger.error('Failed to cleanup Claude sessions', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to cleanup expired sessions',
    });
  }
});

/**
 * GET /api/sessions/:sessionId/expired - Check if a specific Claude session is expired
 */
router.get('/:sessionId/expired', async (req, res) => {
  const { sessionId } = req.params;

  try {
    const aicliService = req.app.get('aicliService');
    const isExpired = aicliService.sessionManager.isClaudeSessionExpired(sessionId);
    const sessionData = aicliService.sessionManager.claudeSessions.get(sessionId);

    if (!sessionData) {
      return res.json({
        success: true,
        sessionId,
        expired: false,
        tracked: false,
        message: 'Session not being tracked (may be new or unknown)',
      });
    }

    const now = Date.now();
    const timeSinceActivity = now - sessionData.lastActivity;
    const hoursInactive = Math.floor(timeSinceActivity / (60 * 60 * 1000));

    res.json({
      success: true,
      sessionId,
      expired: isExpired,
      tracked: true,
      lastActivity: new Date(sessionData.lastActivity).toISOString(),
      hoursInactive,
      hoursUntilExpiry: isExpired ? 0 : Math.max(0, 24 - hoursInactive),
    });
  } catch (error) {
    logger.error('Failed to check session expiry', { sessionId, error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to check session expiry',
    });
  }
});

export default router;
