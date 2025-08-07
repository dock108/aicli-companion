import express from 'express';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('ChatAPI');
// TODO: Check what validation middleware exists
// import { validateRequest } from '../middleware/validation.js';
import { pushNotificationService } from '../services/push-notification.js';

const router = express.Router();

/**
 * POST /api/chat - Send message to Claude and get response via APNS
 */
router.post('/', async (req, res) => {
  const { message, projectPath, sessionId, deviceToken } = req.body;
  
  if (!message) {
    return res.status(400).json({
      success: false,
      error: 'Message is required'
    });
  }

  const requestId = req.headers['x-request-id'] || `REQ_${Date.now()}`;
  
  logger.info('Processing chat message', {
    requestId,
    messageLength: message.length,
    projectPath,
    sessionId: sessionId || 'new',
    hasDeviceToken: !!deviceToken
  });

  try {
    // Get AICLI service from app instance
    const aicliService = req.app.get('aicliService');
    
    // Send prompt to Claude
    const result = await aicliService.sendPrompt(message, {
      sessionId,
      requestId,
      streaming: false, // HTTP doesn't support streaming
      workingDirectory: projectPath || process.cwd(),
      skipPermissions: true,
      format: 'text'
    });

    // Extract Claude's response and session ID
    let content = '';
    let claudeSessionId = sessionId;
    
    if (result?.response?.result) {
      content = result.response.result;
    } else if (result?.response?.text) {
      content = result.response.text;
    } else if (typeof result?.response === 'string') {
      content = result.response;
    } else if (result?.result) {
      content = result.result;
    }

    // Extract session ID if this was a new session
    if (!claudeSessionId && result?.response?.session_id) {
      claudeSessionId = result.response.session_id;
      logger.info('Extracted new session ID from Claude', { claudeSessionId });
    }

    // Send immediate HTTP response
    const responseData = {
      success: true,
      content,
      sessionId: claudeSessionId,
      projectPath,
      requestId,
      timestamp: new Date().toISOString()
    };

    res.json(responseData);

    // Send push notification if device token provided
    if (deviceToken) {
      try {
        // First register the device if not already registered
        const deviceId = req.headers['x-device-id'] || `device_${Date.now()}`;
        await pushNotificationService.registerDevice(deviceId, {
          token: deviceToken,
          platform: 'ios'
        });
        
        // Send Claude response notification
        await pushNotificationService.sendClaudeResponseNotification(deviceId, {
          message: content,
          sessionId: claudeSessionId,
          projectName: projectPath?.split('/').pop() || 'Project',
          totalChunks: 1,
          requestId
        });
        
        logger.info('Push notification sent for chat response', { requestId, deviceId });
      } catch (pushError) {
        logger.warn('Failed to send push notification', { requestId, error: pushError.message });
      }
    }

  } catch (error) {
    logger.error('Chat message processing failed', { 
      requestId,
      error: error.message 
    });

    res.status(500).json({
      success: false,
      error: 'Failed to process message',
      requestId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /api/chat/:sessionId/messages - Get messages for a session
 */
router.get('/:sessionId/messages', async (req, res) => {
  const { sessionId } = req.params;
  const { limit = 50, offset = 0 } = req.query;

  logger.info('Fetching chat messages', { sessionId, limit, offset });

  try {
    // In stateless architecture, we don't store messages server-side
    // This endpoint exists for potential future use or external integrations
    res.json({
      success: true,
      sessionId,
      messages: [],
      totalCount: 0,
      hasMore: false,
      note: 'Server is stateless - messages managed client-side'
    });

  } catch (error) {
    logger.error('Failed to fetch chat messages', { 
      sessionId, 
      error: error.message 
    });

    res.status(500).json({
      success: false,
      error: 'Failed to fetch messages'
    });
  }
});

export default router;