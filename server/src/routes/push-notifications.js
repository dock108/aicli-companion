import express from 'express';
import { pushNotificationService } from '../services/push-notification.js';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();

/**
 * GET /api/push-notifications/stats
 * Get push notification statistics
 */
router.get('/api/push-notifications/stats', authenticate, (req, res) => {
  try {
    const stats = pushNotificationService.getStats();
    res.json(stats);
  } catch (error) {
    console.error('Error fetching push notification stats:', error);
    res.status(500).json({
      error: 'Failed to fetch push notification statistics',
      message: error.message,
    });
  }
});

/**
 * POST /api/push-notifications/test
 * Send a test notification to a specific client
 *
 * TODO: [QUESTION] Should this be restricted to development/admin only?
 * Currently protected by authentication, but may need additional restrictions
 */
router.post('/api/push-notifications/test', authenticate, async (req, res) => {
  try {
    const { clientId, message = 'Test notification from AICLI Companion' } = req.body;

    if (!clientId) {
      return res.status(400).json({
        error: 'Missing clientId',
      });
    }

    const testData = {
      sessionId: 'test-session',
      projectName: 'Test Project',
      message,
      totalChunks: 1,
      isLongRunningCompletion: false,
    };

    await pushNotificationService.sendClaudeResponseNotification(clientId, testData);

    res.json({
      success: true,
      message: 'Test notification sent',
      clientId,
    });
  } catch (error) {
    console.error('Error sending test notification:', error);
    res.status(500).json({
      error: 'Failed to send test notification',
      message: error.message,
    });
  }
});

/**
 * DELETE /api/push-notifications/bad-tokens
 * Clear bad tokens cache
 *
 * TODO: [QUESTION] Admin only endpoint?
 */
router.delete('/api/push-notifications/bad-tokens', authenticate, (req, res) => {
  try {
    const previousCount = pushNotificationService.badTokens.size;
    pushNotificationService.badTokens.clear();

    res.json({
      success: true,
      message: 'Bad tokens cache cleared',
      tokensCleared: previousCount,
    });
  } catch (error) {
    console.error('Error clearing bad tokens:', error);
    res.status(500).json({
      error: 'Failed to clear bad tokens',
      message: error.message,
    });
  }
});

export default router;
