import express from 'express';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('ChatAPI');
// TODO: Check what validation middleware exists
// import { validateRequest } from '../middleware/validation.js';
import { pushNotificationService } from '../services/push-notification.js';

const router = express.Router();

/**
 * POST /api/chat - Send message to Claude and get response via APNS (always async)
 */
router.post('/', async (req, res) => {
  const { message, projectPath, sessionId, deviceToken } = req.body;

  if (!message) {
    return res.status(400).json({
      success: false,
      error: 'Message is required',
    });
  }

  if (!deviceToken) {
    return res.status(400).json({
      success: false,
      error: 'Device token is required for APNS message delivery',
    });
  }

  const requestId = req.headers['x-request-id'] || `REQ_${Date.now()}`;

  logger.info('Processing chat message for APNS delivery', {
    requestId,
    messageLength: message.length,
    projectPath,
    sessionId: sessionId || 'new',
    deviceToken: `${deviceToken.substring(0, 16)}...`,
  });

  // Register device for push notifications
  // Use the device token itself as the device ID for consistent mapping
  const deviceId = deviceToken; // This ensures we can always find the device
  try {
    await pushNotificationService.registerDevice(deviceId, {
      token: deviceToken,
      platform: 'ios',
    });
    logger.info('Device registered for APNS message delivery', {
      requestId,
      deviceId: `${deviceId.substring(0, 16)}...`, // Log partial token for privacy
    });
  } catch (pushRegError) {
    logger.error('Failed to register device for push notifications', {
      requestId,
      error: pushRegError.message,
    });
    return res.status(500).json({
      success: false,
      error: 'Failed to register device for push notifications',
      requestId,
      timestamp: new Date().toISOString(),
    });
  }

  // Send immediate acknowledgment
  // For new conversations, sessionId will be null and Claude will generate one
  const responseData = {
    success: true,
    message: 'Message received, processing Claude response',
    requestId,
    sessionId: sessionId || null, // null for new conversations, Claude will provide one
    projectPath,
    timestamp: new Date().toISOString(),
    deliveryMethod: 'apns',
  };

  res.json(responseData);

  // Process Claude request asynchronously and deliver via APNS
  setImmediate(async () => {
    try {
      logger.info('Starting async Claude processing', {
        requestId,
        hasSessionId: !!sessionId,
        sessionIdValue: sessionId || 'new conversation',
      });

      // Get AICLI service from app instance
      const aicliService = req.app.get('aicliService');

      // Process Claude request - pass original sessionId (null for new conversations)
      const result = await aicliService.sendPrompt(message, {
        sessionId, // null for new conversations, Claude will generate one
        requestId,
        streaming: true, // Use streaming to maintain conversation context
        workingDirectory: projectPath || process.cwd(),
        skipPermissions: true,
        format: 'text',
      });

      // Log the full result structure for debugging
      logger.info('Claude response structure', {
        requestId,
        hasResult: !!result,
        resultType: typeof result,
        resultKeys: result ? Object.keys(result) : [],
        hasSessionId: !!result?.sessionId,
        hasResponse: !!result?.response,
        responseKeys: result?.response ? Object.keys(result.response) : [],
        responseHasResult: !!result?.response?.result,
        responseResultType: typeof result?.response?.result,
      });

      // Extract Claude's response and session ID
      let content = '';
      // The AICLI service returns { sessionId, success, response }
      // where response contains the actual Claude response
      let claudeSessionId = result?.sessionId || sessionId;

      // Extract content from the response structure
      // The actual Claude response is in result.response (from AICLI service)
      // and the text content is in result.response.result (from Claude CLI)
      if (result?.response?.result) {
        content = result.response.result;
      } else if (result?.response?.session_id) {
        // Also check if session_id is in the response object
        claudeSessionId = result.response.session_id || claudeSessionId;
        content = result.response.result || '';
      } else if (result?.result) {
        // Fallback to direct result field
        content = result.result;
      } else if (typeof result?.response === 'string') {
        // Fallback if response is a plain string
        content = result.response;
      }

      // Log content extraction result
      logger.info('Content extraction', {
        requestId,
        contentLength: content.length,
        contentPreview: content.substring(0, 100),
        sessionId: claudeSessionId,
      });

      // Log session ID handling
      if (!sessionId && claudeSessionId) {
        logger.info('New conversation - using Claude-generated session ID', {
          claudeSessionId,
          requestId,
        });
      } else if (sessionId && claudeSessionId && sessionId !== claudeSessionId) {
        logger.warn('Session ID mismatch - Claude returned different ID', {
          expectedSessionId: sessionId,
          claudeReturnedSessionId: claudeSessionId,
          requestId,
        });
      }

      // Ensure session is tracked for future requests and add to session buffer
      await aicliService.sessionManager.trackSessionForRouting(claudeSessionId, projectPath);
      const buffer = aicliService.sessionManager.getSessionBuffer(claudeSessionId);
      if (buffer) {
        buffer.assistantMessages.push({
          content,
          timestamp: new Date().toISOString(),
          requestId,
          deliveredVia: 'apns',
        });
        logger.info('Added response to session buffer', {
          requestId,
          sessionId: claudeSessionId,
        });
      }

      // Send Claude response via APNS
      // Use deviceToken as deviceId since that's how we registered it
      await pushNotificationService.sendClaudeResponseNotification(deviceToken, {
        message: content,
        sessionId: claudeSessionId,
        projectName: projectPath?.split('/').pop() || 'Project',
        projectPath,
        totalChunks: 1,
        requestId,
        isLongRunningCompletion: true, // All APNS deliveries are treated as completions
        originalMessage: message, // Include original user message for context
      });

      logger.info('Claude response delivered via APNS', {
        requestId,
        deviceId: `${deviceToken.substring(0, 16)}...`,
        sessionId: claudeSessionId,
        contentLength: content.length,
      });
    } catch (error) {
      logger.error('Async Claude processing failed', {
        requestId,
        error: error.message,
      });

      // Send error notification via APNS
      try {
        await pushNotificationService.sendErrorNotification(deviceToken, {
          sessionId: sessionId || 'error-no-session',
          projectName: projectPath?.split('/').pop() || 'Project',
          projectPath,
          error: `Failed to process message: ${error.message}`,
          requestId,
        });

        logger.info('Error notification sent via APNS', {
          requestId,
          deviceId: `${deviceToken.substring(0, 16)}...`,
        });
      } catch (pushError) {
        logger.error('Failed to send error notification via APNS', {
          requestId,
          originalError: error.message,
          pushError: pushError.message,
        });
      }
    }
  });
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
      note: 'Server is stateless - messages managed client-side',
    });
  } catch (error) {
    logger.error('Failed to fetch chat messages', {
      sessionId,
      error: error.message,
    });

    res.status(500).json({
      success: false,
      error: 'Failed to fetch messages',
    });
  }
});

export default router;
