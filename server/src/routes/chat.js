import express from 'express';
import { randomUUID } from 'crypto';
import { createLogger } from '../utils/logger.js';
import { ValidationUtils } from '../utils/validation.js';

const logger = createLogger('ChatAPI');
// TODO: Check what validation middleware exists
// import { validateRequest } from '../middleware/validation.js';
import { pushNotificationService } from '../services/push-notification.js';

const router = express.Router();

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
  } = req.body;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  // Look up existing session for this project path if client didn't send a sessionId
  const aicliService = req.app.get('aicliService');
  let sessionId = clientSessionId;

  if (!sessionId && projectPath) {
    // Try to find an existing session for this project
    const existingSession =
      await aicliService.sessionManager.findSessionByWorkingDirectory(projectPath);
    if (existingSession) {
      sessionId = existingSession.sessionId;
      logger.info('Found existing session for project', {
        requestId,
        projectPath,
        sessionId,
      });
    } else {
      logger.info('No existing session found for project', {
        requestId,
        projectPath,
        activeSessions: aicliService.sessionManager.getActiveSessions().length,
      });
    }
  }

  if (!message) {
    return res.status(400).json({
      success: false,
      error: 'Message is required',
    });
  }

  // Validate message content and size
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
  if (attachments && Array.isArray(attachments)) {
    const MAX_ATTACHMENT_SIZE = parseInt(process.env.MAX_ATTACHMENT_SIZE || '10485760'); // 10MB default
    const ALLOWED_MIME_TYPES = [
      'image/jpeg',
      'image/png',
      'image/gif',
      'application/pdf',
      'text/plain',
      'text/markdown',
      'application/json',
      'text/javascript',
      'text/x-python',
      'text/x-swift',
      'text/x-java-source',
      'text/x-c++src',
      'text/x-csrc',
      'text/x-chdr',
      'application/octet-stream',
    ];

    for (const attachment of attachments) {
      if (!attachment.data || !attachment.name || !attachment.mimeType) {
        return res.status(400).json({
          success: false,
          error: 'Each attachment must have data, name, and mimeType',
        });
      }

      // Validate size (base64 is ~33% larger than original)
      const estimatedSize = (attachment.data.length * 3) / 4;
      if (estimatedSize > MAX_ATTACHMENT_SIZE) {
        return res.status(400).json({
          success: false,
          error: `Attachment ${attachment.name} exceeds maximum size of ${MAX_ATTACHMENT_SIZE} bytes`,
        });
      }

      // Validate MIME type
      if (!ALLOWED_MIME_TYPES.includes(attachment.mimeType)) {
        logger.warn('Unsupported MIME type for attachment', {
          name: attachment.name,
          mimeType: attachment.mimeType,
          requestId,
        });
      }
    }
  }

  logger.info('Processing chat message for APNS delivery', {
    requestId,
    messageLength: message.length,
    projectPath,
    sessionId: sessionId || 'new',
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

  // If we have an existing session, immediately add the user message to the buffer
  if (sessionId) {
    await aicliService.sessionManager.trackSessionForRouting(sessionId, projectPath);
    const buffer = aicliService.sessionManager.getSessionBuffer(sessionId);
    if (buffer) {
      if (!buffer.userMessages) {
        buffer.userMessages = [];
      }
      buffer.userMessages.push({
        content: message,
        timestamp: new Date().toISOString(),
        requestId,
        attachments: attachments?.length || 0,
      });
      logger.info('Added user message to existing session buffer', {
        requestId,
        sessionId,
        messageCount: buffer.userMessages.length,
      });
    }
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
    // NO TIMEOUT - Claude operations can take as long as needed
    // Timeout should only come from activity monitoring (Issue #28)
    let processingCompleted = false;

    try {
      logger.info('Starting async Claude processing', {
        requestId,
        hasSessionId: !!sessionId,
        sessionIdValue: sessionId || 'new conversation',
      });

      // Set up streaming status updates listener
      const streamListener = async (data) => {
        // Only process chunks for our request ID
        if (data.requestId !== requestId) return;
        
        const chunk = data.chunk;
        
        // Send progress updates for interesting chunk types
        if (chunk.type === 'system' && chunk.subtype === 'init') {
          // Initial system message - Claude is starting
          await pushNotificationService.sendProgressNotification(deviceToken, {
            projectPath,
            activity: 'Initializing',
            duration: 0,
            tokenCount: 0,
            requestId,
          });
        } else if (chunk.type === 'assistant' && chunk.message) {
          // Assistant is thinking/typing
          const messageContent = chunk.message?.content?.[0]?.text || '';
          const preview = messageContent.substring(0, 50);
          
          await pushNotificationService.sendProgressNotification(deviceToken, {
            projectPath,
            activity: preview ? `Typing: ${preview}...` : 'Thinking',
            duration: Math.floor((Date.now() - startTime) / 1000),
            tokenCount: messageContent.length,
            requestId,
          });
        } else if (chunk.type === 'tool_use') {
          // Claude is using a tool
          await pushNotificationService.sendProgressNotification(deviceToken, {
            projectPath,
            activity: `Using ${chunk.tool_name || 'tool'}`,
            duration: Math.floor((Date.now() - startTime) / 1000),
            tokenCount: 0,
            requestId,
          });
        }
      };
      
      // Start time for duration tracking
      const startTime = Date.now();
      
      // Attach the listener
      aicliService.on('streamChunk', streamListener);

      // Use the regular AICLI service for sending prompts
      // IMPORTANT: Set streaming: true to use the processRunner with --resume fix
      const result = await aicliService.sendPrompt(messageValidation.message ?? message, {
        sessionId,
        requestId,
        workingDirectory: projectPath || process.cwd(),
        attachments,
        streaming: true, // Use streaming to get processRunner with --resume
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
        // New fields for enhanced text accumulation
        resultSource: result?.source || 'unknown',
        directResult: !!result?.result,
        directResultType: typeof result?.result,
        directResultLength: typeof result?.result === 'string' ? result.result.length : 0,
      });

      // Extract Claude's response and session ID
      let content = '';
      // The AICLI service returns { sessionId, success, response }
      // where response contains the actual Claude response
      let claudeSessionId = result?.sessionId || sessionId;

      // Extract content from the response structure
      // Enhanced extraction to handle new text accumulation from tool use
      if (result?.result && typeof result.result === 'string') {
        // New: Direct result from enhanced streaming (tool use text accumulation)
        content = result.result;
        logger.info('Using direct result from enhanced streaming', {
          requestId,
          source: result.source || 'direct',
          contentLength: content.length,
        });
      } else if (result?.response?.result) {
        // Original: The actual Claude response is in result.response.result (from Claude CLI)
        content = result.response.result;
        logger.info('Using nested response result', {
          requestId,
          contentLength: content.length,
        });
      } else if (result?.response?.session_id) {
        // Also check if session_id is in the response object
        claudeSessionId = result.response.session_id || claudeSessionId;
        content = result.response.result || '';
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
        // Only add user message if this is a new conversation (no sessionId was provided initially)
        if (!sessionId) {
          // This is a new conversation, add the user message
          if (!buffer.userMessages) {
            buffer.userMessages = [];
          }
          buffer.userMessages.push({
            content: message,
            timestamp: new Date().toISOString(),
            requestId,
            attachments: attachments?.length || 0,
          });
          logger.info('Added user message to new session buffer', {
            requestId,
            sessionId: claudeSessionId,
          });
        }

        // Add assistant response to buffer
        if (!buffer.assistantMessages) {
          buffer.assistantMessages = [];
        }
        buffer.assistantMessages.push({
          content,
          timestamp: new Date().toISOString(),
          requestId,
          deliveredVia: 'apns',
        });
        logger.info('Added assistant response to session buffer', {
          requestId,
          sessionId: claudeSessionId,
        });
      }

      // Store message with ID if it's large (for fetching later)
      let messageId = null;
      const MESSAGE_FETCH_THRESHOLD = 3000;
      if (content.length > MESSAGE_FETCH_THRESHOLD) {
        messageId = randomUUID();

        // Store the message in the session buffer for later retrieval
        aicliService.sessionManager.storeMessage(claudeSessionId, messageId, content, {
          type: 'assistant',
          requestId,
          projectPath,
          originalMessage: message,
          attachmentInfo: attachments?.map((att) => ({
            name: att.name,
            mimeType: att.mimeType,
            size: att.size || (att.data.length * 3) / 4,
          })),
        });

        logger.info('Stored large message for fetching', {
          messageId,
          sessionId: claudeSessionId,
          contentLength: content.length,
        });
      }

      // Skip sending notification if content is empty
      if (!content || content.trim().length === 0) {
        logger.warn('Skipping APNS delivery - Claude returned empty content', {
          requestId,
          sessionId: claudeSessionId,
        });

        // Don't try to send response - it was already sent on line 215
        // Just return from the async handler
        return;
      }

      // Send Claude response via APNS
      // Use deviceToken as deviceId since that's how we registered it
      await pushNotificationService.sendClaudeResponseNotification(deviceToken, {
        message: content,
        messageId, // Include message ID for large messages
        sessionId: claudeSessionId,
        projectName: projectPath?.split('/').pop() || 'Project',
        projectPath,
        totalChunks: 1,
        requestId,
        isLongRunningCompletion: true, // All APNS deliveries are treated as completions
        // Don't include originalMessage in payload - it can make payload too large
        // originalMessage: message, // REMOVED - can exceed 4KB limit
        attachmentInfo: attachments?.map((att) => ({
          name: att.name,
          mimeType: att.mimeType,
          size: att.size || (att.data.length * 3) / 4,
        })), // Include attachment metadata without the data
        autoResponse, // Include auto-response metadata
      });

      logger.info('Claude response delivered via APNS', {
        requestId,
        deviceId: `${deviceToken.substring(0, 16)}...`,
        sessionId: claudeSessionId,
        contentLength: content.length,
      });

      // Mark processing as completed
      processingCompleted = true;
      
      // Clean up the listener after successful processing
      aicliService.removeListener('streamChunk', streamListener);
    } catch (error) {
      // Clean up the listener on error
      aicliService.removeListener('streamChunk', streamListener);

      // Determine error type and user-friendly message
      let userErrorMessage = 'Failed to process message';
      let errorType = 'PROCESSING_ERROR';

      if (error.message?.includes('timeout')) {
        userErrorMessage =
          'Claude is taking longer than expected. Please try again or break your message into smaller parts.';
        errorType = 'TIMEOUT';
      } else if (error.message?.includes('ECONNREFUSED')) {
        userErrorMessage = 'Unable to connect to Claude. Please check if the service is running.';
        errorType = 'CONNECTION_ERROR';
      } else if (error.message?.includes('ENOMEM')) {
        userErrorMessage =
          'Server ran out of memory processing your request. Please try a smaller message.';
        errorType = 'MEMORY_ERROR';
      } else if (error.message?.includes('rate limit')) {
        userErrorMessage = 'Too many requests. Please wait a moment and try again.';
        errorType = 'RATE_LIMIT';
      } else if (error.code === 'ENOTFOUND') {
        userErrorMessage = 'Claude CLI not found. Please ensure it is installed and configured.';
        errorType = 'SERVICE_NOT_FOUND';
      }

      logger.error('Async Claude processing failed', {
        requestId,
        error: error.message,
        errorType,
        stack: error.stack,
        sessionId,
        messageLength: message?.length,
      });

      // Send detailed error notification via APNS
      try {
        await pushNotificationService.sendErrorNotification(deviceToken, {
          sessionId: sessionId || 'error-no-session',
          projectName: projectPath?.split('/').pop() || 'Project',
          projectPath,
          error: userErrorMessage,
          errorType,
          technicalDetails: process.env.NODE_ENV === 'development' ? error.message : undefined,
          requestId,
        });

        logger.info('Error notification sent via APNS', {
          requestId,
          deviceId: `${deviceToken.substring(0, 16)}...`,
          errorType,
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
 * POST /api/chat/auto-response/pause - Pause auto-response mode for a session
 */
router.post('/auto-response/pause', async (req, res) => {
  const { sessionId, deviceToken } = req.body;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  logger.info('Pausing auto-response mode', { sessionId, requestId });

  // Send pause notification if device token provided
  if (deviceToken) {
    await pushNotificationService.sendAutoResponseControlNotification(deviceToken, {
      sessionId,
      action: 'pause',
      requestId,
    });
  }

  res.json({
    success: true,
    sessionId,
    action: 'pause',
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/chat/auto-response/resume - Resume auto-response mode for a session
 */
router.post('/auto-response/resume', async (req, res) => {
  const { sessionId, deviceToken } = req.body;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  logger.info('Resuming auto-response mode', { sessionId, requestId });

  // Send resume notification if device token provided
  if (deviceToken) {
    await pushNotificationService.sendAutoResponseControlNotification(deviceToken, {
      sessionId,
      action: 'resume',
      requestId,
    });
  }

  res.json({
    success: true,
    sessionId,
    action: 'resume',
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/chat/auto-response/stop - Stop auto-response mode for a session
 */
router.post('/auto-response/stop', async (req, res) => {
  const { sessionId, deviceToken, reason } = req.body;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  logger.info('Stopping auto-response mode', { sessionId, reason, requestId });

  // Send stop notification if device token provided
  if (deviceToken) {
    await pushNotificationService.sendAutoResponseControlNotification(deviceToken, {
      sessionId,
      action: 'stop',
      reason: reason || 'manual',
      requestId,
    });
  }

  res.json({
    success: true,
    sessionId,
    action: 'stop',
    reason: reason || 'manual',
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /api/chat/:sessionId/progress - Get thinking progress for a session
 */
router.get('/:sessionId/progress', async (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Fetching thinking progress', { sessionId, requestId });

  try {
    // Get AICLI service from app instance
    const aicliService = req.app.get('aicliService');

    // Check if session exists and get progress
    const sessionBuffer = aicliService.sessionManager.getSessionBuffer(sessionId);

    if (!sessionBuffer) {
      return res.status(404).json({
        success: false,
        error: 'Session not found',
        sessionId,
      });
    }

    // Extract thinking metadata from session
    const thinkingMetadata = sessionBuffer.thinkingMetadata || {
      isThinking: false,
      activity: null,
      duration: 0,
      tokenCount: 0,
    };

    res.json({
      success: true,
      sessionId,
      isThinking: thinkingMetadata.isThinking,
      activity: thinkingMetadata.activity,
      duration: thinkingMetadata.duration,
      tokenCount: thinkingMetadata.tokenCount,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Failed to fetch thinking progress', {
      sessionId,
      error: error.message,
    });

    res.status(500).json({
      success: false,
      error: 'Failed to fetch progress',
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
    // Get AICLI service from app instance
    const aicliService = req.app.get('aicliService');

    // Get the session buffer which contains all messages
    const buffer = aicliService.sessionManager.getSessionBuffer(sessionId);

    if (!buffer) {
      // No buffer means no active session
      return res.json({
        success: true,
        sessionId,
        messages: [],
        totalCount: 0,
        hasMore: false,
        note: 'No active session found',
      });
    }

    // Combine user and assistant messages, maintaining chronological order
    const allMessages = [];

    // Add user messages with proper structure
    if (buffer.userMessages && buffer.userMessages.length > 0) {
      buffer.userMessages.forEach((msg) => {
        allMessages.push({
          content: msg.content || msg.message,
          sender: 'user',
          timestamp: msg.timestamp || new Date().toISOString(),
          requestId: msg.requestId,
          type: 'text',
        });
      });
    }

    // Add assistant messages with proper structure
    if (buffer.assistantMessages && buffer.assistantMessages.length > 0) {
      buffer.assistantMessages.forEach((msg) => {
        allMessages.push({
          content: msg.content || msg.message,
          sender: 'assistant',
          timestamp: msg.timestamp || new Date().toISOString(),
          requestId: msg.requestId,
          type: 'markdown',
          deliveredVia: msg.deliveredVia || 'apns',
        });
      });
    }

    // Sort messages by timestamp to maintain conversation flow
    allMessages.sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));

    // Apply pagination if needed
    const paginatedMessages = allMessages.slice(
      parseInt(offset),
      parseInt(offset) + parseInt(limit)
    );

    logger.info('Returning buffered messages', {
      sessionId,
      totalMessages: allMessages.length,
      returnedMessages: paginatedMessages.length,
      offset,
      limit,
    });

    res.json({
      success: true,
      sessionId,
      messages: paginatedMessages,
      totalCount: allMessages.length,
      hasMore: allMessages.length > parseInt(offset) + parseInt(limit),
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
