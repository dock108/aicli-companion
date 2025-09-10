import express from 'express';
import { randomUUID } from 'crypto';
import { createLogger } from '../utils/logger.js';
import { ValidationUtils } from '../utils/validation.js';
import { messageQueueManager, MessagePriority } from '../services/message-queue.js';
import { deviceRegistry } from '../services/device-registry.js';
import { pushNotificationService } from '../services/push-notification.js';
import { createChatMessageHandler } from '../handlers/chat-message-handler.js';
import { sendErrorResponse } from '../utils/response-utils.js';
import { PlanningModeService } from '../services/planning-mode.js';

const logger = createLogger('ChatAPI');
const router = express.Router();

// Import AICLI service singleton instance
import { aicliService } from '../services/aicli-instance.js';

// Initialize planning mode service
const planningModeService = new PlanningModeService();

/**
 * POST /api/chat - Send message to Claude and get response via APNS (always async)
 */
router.post('/', async (req, res) => {
  const {
    message,
    projectPath,
    sessionId: clientSessionId,
    deviceToken,
    attachments,
    autoResponse, // Auto-response metadata
    priority = MessagePriority.NORMAL, // Message priority for queue
    deviceId, // Device identifier for coordination
    userId, // User identifier for device coordination
    deviceInfo, // Device information (platform, version, etc.)
    mode = 'normal', // Chat mode: normal, planning, code
  } = req.body;

  const requestId =
    req.headers['x-request-id'] || `REQ_${randomUUID().replace(/-/g, '').substring(0, 8)}`;
  const sessionId = clientSessionId; // Preserve original session ID

  // Log active sessions for debugging
  if (aicliService && aicliService.sessionManager) {
    logger.info('Active sessions check', {
      requestId,
      projectPath,
      activeSessions: aicliService.sessionManager.getActiveSessions().length,
    });
  }

  if (!message) {
    return sendErrorResponse(res, 'INVALID_REQUEST', 'Message is required');
  }

  // Handle device registration and coordination if deviceId and userId provided
  let resolvedDeviceId = deviceId;
  if (deviceId && userId) {
    try {
      // Register or update device
      const registrationResult = deviceRegistry.registerDevice(userId, deviceId, deviceInfo || {});
      if (registrationResult.success) {
        // Update heartbeat
        deviceRegistry.updateLastSeen(deviceId);

        logger.info('Device registered/updated', {
          requestId,
          userId,
          deviceId: deviceId ? `${deviceId.substring(0, 8)}...` : 'undefined',
          isNewDevice: registrationResult.isNew,
          platform: registrationResult.device.platform,
        });
      }
    } catch (error) {
      logger.error('Device registration failed', {
        requestId,
        userId,
        deviceId: deviceId ? `${deviceId.substring(0, 8)}...` : 'undefined',
        error: error.message,
      });
      // Continue without device coordination
    }
  } else {
    // Fallback: use deviceToken as deviceId for backward compatibility
    resolvedDeviceId = deviceToken;
    if (deviceToken) {
      logger.info('Using deviceToken as deviceId for backward compatibility', {
        requestId,
        deviceToken: `${deviceToken.substring(0, 10)}...`,
      });
    }
  }

  // Validate message content
  const messageValidation = ValidationUtils.validateMessageContent(message);
  if (!messageValidation.valid) {
    logger.error('Message validation failed', {
      requestId,
      errors: messageValidation.errors,
      messageLength: message?.length,
    });

    return res.status(400).json({
      success: false,
      error: 'Invalid message content',
      details: messageValidation.errors,
      requestId,
    });
  }

  // Log warnings if any
  if (messageValidation.warnings.length > 0) {
    logger.warn('Message validation warnings', {
      requestId,
      warnings: messageValidation.warnings,
      messageLength: message.length,
    });
  }

  if (!deviceToken) {
    return res.status(400).json({
      success: false,
      error: 'Device token is required for APNS message delivery',
    });
  }

  // Validate attachments if provided
  if (attachments && attachments.length > 0) {
    const attachmentValidation = ValidationUtils.validateAttachments(attachments);
    if (!attachmentValidation.valid) {
      logger.error('Attachment validation failed', {
        requestId,
        errors: attachmentValidation.errors,
        attachmentCount: attachments.length,
      });

      return res.status(400).json({
        success: false,
        error: 'Invalid attachments',
        details: attachmentValidation.errors,
        requestId,
      });
    }

    if (attachmentValidation.warnings.length > 0) {
      logger.warn('Attachment validation warnings', {
        requestId,
        warnings: attachmentValidation.warnings,
      });
    }
  }

  // Log the request details for debugging
  logger.info('Processing chat message for APNS delivery', {
    requestId,
    sessionId: sessionId || 'new',
    messageLength: message.length,
    projectPath,
    deviceToken: `${deviceToken.substring(0, 16)}...`,
    attachmentCount: attachments?.length || 0,
    autoResponse: autoResponse
      ? {
          isActive: autoResponse.isActive,
          iteration: autoResponse.iteration,
        }
      : null,
  });

  // Register device for push notifications
  // Use the device token itself as the device ID for consistent mapping
  const pushDeviceId = deviceToken; // This ensures we can always find the device
  try {
    await pushNotificationService.registerDevice(pushDeviceId, {
      token: deviceToken,
      platform: 'ios',
    });
    logger.info('Device registered for APNS message delivery', {
      requestId,
      deviceId: `${pushDeviceId.substring(0, 16)}...`, // Log partial token for privacy
    });
  } catch (pushRegError) {
    logger.error('Failed to register device for push notifications', {
      requestId,
      error: pushRegError.message,
    });
    // Continue anyway - the push might still work
  }

  // Queue message
  // Use session ID for queue if provided, otherwise create a temp one
  const queueSessionId = sessionId || `temp_${requestId}`;

  // Handle device election if sessionId provided
  if (sessionId && deviceId && userId) {
    const electionResult = deviceRegistry.electPrimary(userId, sessionId, deviceId);
    if (electionResult.success) {
      if (electionResult.isPrimary) {
        logger.info('Device elected as primary for session', {
          requestId,
          sessionId,
          deviceId: `${deviceId.substring(0, 8)}...`,
        });
      } else {
        logger.info('Device is secondary for session', {
          requestId,
          sessionId,
          primaryDeviceId: `${electionResult.primaryDeviceId?.substring(0, 8)}...`,
        });
      }
    }
  }

  // Adjust message priority based on context
  let messagePriority = priority;
  if (autoResponse?.isActive) {
    // High priority for first auto-response or manual triggers
    if (autoResponse.iteration === 1 || autoResponse.userTriggered) {
      messagePriority = MessagePriority.HIGH;
    }
    // Low priority for auto-response generated follow-ups
    else if (autoResponse.isActive && autoResponse.iteration > 1) {
      messagePriority = MessagePriority.LOW;
    }
  }

  // Set up the message handler BEFORE queuing (must be before to avoid race condition)
  if (!messageQueueManager.getQueue(queueSessionId).listenerCount('process-message')) {
    const handler = createChatMessageHandler({
      aicliService,
      pushNotificationService,
    });
    messageQueueManager.setMessageHandler(queueSessionId, handler);
  }

  // Queue the message with device context for deduplication
  const messageMetadata = {
    requestId,
    timestamp: new Date().toISOString(),
    deviceId: resolvedDeviceId,
    userId,
    deviceInfo,
  };

  // If in planning mode, prefix the message with instructions
  let processedMessage = message;
  if (mode === 'planning') {
    // Use centralized planning mode prefix from PlanningModeService
    const planningPrefix = planningModeService.getPlanningModePrefix();
    processedMessage = planningPrefix + message;
    logger.info('Planning mode activated - added instruction prefix', {
      requestId,
      mode,
      originalLength: message.length,
      prefixedLength: processedMessage.length,
    });
  } else if (mode === 'code') {
    // Optional prefix for code mode
    processedMessage = message; // No prefix needed for code mode
  }

  const queueResult = messageQueueManager.queueMessage(
    queueSessionId,
    {
      message: processedMessage,
      projectPath,
      deviceToken,
      attachments,
      autoResponse,
      requestId,
      sessionId,
      mode, // Include mode for handler
      validatedMessage: processedMessage, // Use the processed (prefixed) message
      content: message, // Duplicate detector needs original message
    },
    messagePriority,
    messageMetadata
  );

  // Check if message was rejected due to duplication
  if (!queueResult.queued) {
    if (queueResult.reason === 'duplicate') {
      logger.info('Duplicate message detected and rejected', {
        requestId,
        messageHash: queueResult.messageHash,
        originalDevice: queueResult.duplicateInfo?.originalDeviceId,
        currentDevice: resolvedDeviceId,
        timeDifference: queueResult.duplicateInfo?.timeDifference,
      });

      // Return success but indicate it was a duplicate
      return res.json({
        success: true,
        message: 'Duplicate message detected - not processed',
        requestId,
        sessionId: sessionId || null,
        projectPath,
        timestamp: new Date().toISOString(),
        deliveryMethod: 'apns',
        duplicate: true,
        duplicateInfo: {
          messageHash: queueResult.messageHash,
          originalDevice: `${queueResult.duplicateInfo?.originalDeviceId?.substring(0, 8)}...`,
          timeDifference: queueResult.duplicateInfo?.timeDifference,
        },
      });
    } else {
      // Other queue rejection reasons
      logger.error('Message queue rejected message', {
        requestId,
        reason: queueResult.reason,
        sessionId: queueSessionId,
      });

      return res.status(500).json({
        success: false,
        error: 'Failed to queue message for processing',
        reason: queueResult.reason,
        requestId,
      });
    }
  }

  const messageId = queueResult.messageId;

  logger.info('Message queued for processing', {
    requestId,
    messageId,
    sessionId: queueSessionId,
    priority: messagePriority,
    queueStatus: messageQueueManager.getQueueStatus(queueSessionId),
  });

  // Return immediate response - message will be processed async
  res.json({
    success: true,
    message: 'Message queued for APNS delivery',
    requestId,
    messageId,
    sessionId: sessionId || null,
    projectPath,
    timestamp: new Date().toISOString(),
    deliveryMethod: 'apns',
    queuePosition: queueResult.position || 1,
    estimatedProcessingTime: '2-5 seconds',
  });
});

/**
 * POST /api/chat/auto-response/pause - Pause auto-response mode for a session
 */
router.post('/auto-response/pause', async (req, res) => {
  const { sessionId, deviceId, userId } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  // Update device heartbeat if device context provided
  if (deviceId && userId) {
    try {
      deviceRegistry.updateLastSeen(deviceId);
    } catch (error) {
      logger.warn('Failed to update device heartbeat', {
        requestId,
        deviceId: `${deviceId.substring(0, 8)}...`,
        error: error.message,
      });
    }
  }

  logger.info('Pausing auto-response mode', { sessionId, requestId });

  // Pause the message queue for this session
  messageQueueManager.pauseQueue(sessionId);

  // Send acknowledgment
  res.json({
    success: true,
    message: 'Auto-response mode paused',
    sessionId,
    requestId,
  });
});

/**
 * POST /api/chat/auto-response/resume - Resume auto-response mode for a session
 */
router.post('/auto-response/resume', async (req, res) => {
  const { sessionId, deviceId, userId } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  // Update device heartbeat if device context provided
  if (deviceId && userId) {
    try {
      deviceRegistry.updateLastSeen(deviceId);
    } catch (error) {
      logger.warn('Failed to update device heartbeat', {
        requestId,
        deviceId: `${deviceId.substring(0, 8)}...`,
        error: error.message,
      });
    }
  }

  logger.info('Resuming auto-response mode', { sessionId, requestId });

  // Resume the message queue for this session
  messageQueueManager.resumeQueue(sessionId);

  // Log queue status after resume
  const queueStatus = messageQueueManager.getQueueStatus(sessionId);
  if (queueStatus) {
    logger.info('Queue status after resume', {
      sessionId,
      requestId,
      queueLength: queueStatus.queue.length,
      processing: queueStatus.processing,
      paused: queueStatus.paused,
    });
  }

  res.json({
    success: true,
    message: 'Auto-response mode resumed',
    sessionId,
    requestId,
    queueStatus: queueStatus
      ? {
          queueLength: queueStatus.queue.length,
          processing: queueStatus.processing,
        }
      : null,
  });
});

/**
 * POST /api/chat/auto-response/stop - Stop auto-response mode for a session
 */
router.post('/auto-response/stop', async (req, res) => {
  const { sessionId, deviceId, userId, reason } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  // Update device heartbeat if device context provided
  if (deviceId && userId) {
    try {
      deviceRegistry.updateLastSeen(deviceId);
    } catch (error) {
      logger.warn('Failed to update device heartbeat', {
        requestId,
        deviceId: deviceId ? `${deviceId.substring(0, 8)}...` : 'undefined',
        error: error.message,
      });
    }
  }

  logger.info('Stopping auto-response mode', { sessionId, requestId, reason });

  // Stop the message queue for this session
  messageQueueManager.pauseQueue(sessionId);
  messageQueueManager.clearQueue(sessionId);

  res.json({
    success: true,
    message: 'Auto-response mode stopped',
    action: 'stop',
    sessionId,
    requestId,
    reason: reason || 'user_requested',
  });
});

/**
 * GET /api/chat/:sessionId/progress - Get thinking progress for a session
 */
router.get('/:sessionId/progress', async (req, res) => {
  const { sessionId } = req.params;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  // Get AICLI service
  const aicliServiceInstance = req.app.get('aicliService') || aicliService;

  if (!aicliServiceInstance || !aicliServiceInstance.sessionManager) {
    return res.status(404).json({
      success: false,
      error: 'Service not available',
      requestId,
    });
  }

  // Get session buffer/metadata
  const sessionBuffer = aicliServiceInstance.sessionManager.getSessionBuffer(sessionId);

  if (!sessionBuffer) {
    return res.status(404).json({
      success: false,
      error: 'Session not found',
      sessionId,
      requestId,
    });
  }

  // Get thinking metadata
  const thinkingMetadata = sessionBuffer.thinkingMetadata || {};
  const isThinking = thinkingMetadata.isThinking || false;

  res.json({
    success: true,
    sessionId,
    isThinking,
    activity: thinkingMetadata.activity || null,
    duration: thinkingMetadata.duration || 0,
    tokenCount: thinkingMetadata.tokenCount || 0,
    requestId,
  });
});

/**
 * GET /api/chat/:sessionId/messages - Get messages for a session
 */
router.get('/:sessionId/messages', async (req, res) => {
  const { sessionId } = req.params;
  const { limit = 50, offset = 0 } = req.query;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  // Get AICLI service
  const aicliServiceInstance = req.app.get('aicliService') || aicliService;

  if (!aicliServiceInstance || !aicliServiceInstance.sessionManager) {
    return res.status(500).json({
      success: false,
      error: 'Service not available',
      requestId,
    });
  }

  try {
    // Get session messages
    const messages = aicliServiceInstance.sessionManager.getSessionMessages(
      sessionId,
      parseInt(limit),
      parseInt(offset)
    );

    res.json({
      success: true,
      sessionId,
      messages: messages || [],
      limit: parseInt(limit),
      offset: parseInt(offset),
      total: messages ? messages.length : 0,
      requestId,
    });
  } catch (error) {
    logger.error('Failed to get session messages', {
      requestId,
      sessionId,
      error: error.message,
    });

    res.status(500).json({
      success: false,
      error: 'Failed to retrieve messages',
      requestId,
    });
  }
});

/**
 * POST /api/chat/interrupt - Interrupt current processing for a session
 */
router.post('/interrupt', async (req, res) => {
  const { sessionId, deviceId, userId } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  // Update device heartbeat if device context provided
  if (deviceId && userId) {
    try {
      deviceRegistry.updateLastSeen(deviceId);
    } catch (error) {
      logger.warn('Failed to update device heartbeat', {
        requestId,
        deviceId: `${deviceId.substring(0, 8)}...`,
        error: error.message,
      });
    }
  }

  logger.info('Interrupting session processing', { sessionId, requestId });

  // Pause the queue first
  messageQueueManager.pauseQueue(sessionId);

  // Then clear any pending messages
  const clearedCount = messageQueueManager.clearQueue(sessionId);

  logger.info('Session interrupted', {
    sessionId,
    requestId,
    clearedMessages: clearedCount,
  });

  res.json({
    success: true,
    message: 'Session processing interrupted',
    sessionId,
    requestId,
    clearedMessages: clearedCount,
  });
});

export default router;
