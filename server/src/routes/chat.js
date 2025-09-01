import express from 'express';
import { randomUUID } from 'crypto';
import { createLogger } from '../utils/logger.js';
import { ValidationUtils } from '../utils/validation.js';
import { messageQueueManager, MessagePriority } from '../services/message-queue.js';

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
    priority = MessagePriority.NORMAL, // Message priority for queue
  } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

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

  // Queue the message for processing based on priority
  // Use session ID or create a temporary one for queue management
  const queueSessionId = sessionId || `temp_${requestId}`;

  // Determine priority based on message content and metadata
  let messagePriority = priority;
  if (message && typeof message === 'string') {
    // High priority for stop/cancel commands
    if (
      message.toLowerCase().includes('stop') ||
      message.toLowerCase().includes('cancel') ||
      message.toLowerCase().includes('abort')
    ) {
      messagePriority = MessagePriority.HIGH;
    }
    // Low priority for auto-response generated follow-ups
    else if (autoResponse?.isActive && autoResponse?.iteration > 1) {
      messagePriority = MessagePriority.LOW;
    }
  }

  // Queue the message
  const messageId = messageQueueManager.queueMessage(
    queueSessionId,
    {
      message,
      projectPath,
      deviceToken,
      attachments,
      autoResponse,
      requestId,
      sessionId,
      validatedMessage: messageValidation.message ?? message,
    },
    messagePriority,
    { requestId, timestamp: new Date().toISOString() }
  );

  logger.info('Message queued for processing', {
    requestId,
    messageId,
    sessionId: queueSessionId,
    priority: messagePriority,
    queueStatus: messageQueueManager.getQueueStatus(queueSessionId),
  });

  // Set up the message handler if not already set
  if (!messageQueueManager.getQueue(queueSessionId).listenerCount('process-message')) {
    messageQueueManager.setMessageHandler(queueSessionId, async (queuedMessage, callback) => {
      // Process Claude request asynchronously and deliver via APNS
      const { message: msgData } = queuedMessage;
      const {
        message: queuedMsg,
        projectPath: msgProjectPath,
        deviceToken: msgDeviceToken,
        attachments: msgAttachments,
        autoResponse: msgAutoResponse,
        requestId: msgRequestId,
        sessionId: msgSessionId,
        validatedMessage,
      } = msgData;

      // NO TIMEOUT - Claude operations can take as long as needed
      // Timeout should only come from activity monitoring (Issue #28)
      let streamListener; // Declare streamListener in the outer scope

      try {
        logger.info('Starting async Claude processing from queue', {
          requestId: msgRequestId,
          messageId: queuedMessage.id,
          priority: queuedMessage.priority,
          hasSessionId: !!msgSessionId,
          sessionIdValue: msgSessionId || 'new conversation',
        });

        // Set up streaming status updates listener
        streamListener = async (data) => {
          // Only process chunks for our request ID
          if (data.requestId !== msgRequestId) return;

          const chunk = data.chunk;

          // Send progress updates for interesting chunk types
          if (chunk.type === 'system' && chunk.subtype === 'init') {
            // Initial system message - Claude is starting
            await pushNotificationService.sendProgressNotification(msgDeviceToken, {
              projectPath: msgProjectPath,
              activity: 'Initializing',
              duration: 0,
              tokenCount: 0,
              requestId: msgRequestId,
            });
          } else if (chunk.type === 'assistant' && chunk.message) {
            // Assistant is thinking/typing
            const messageContent = chunk.message?.content?.[0]?.text || '';
            const preview = messageContent.substring(0, 50);

            await pushNotificationService.sendProgressNotification(msgDeviceToken, {
              projectPath: msgProjectPath,
              activity: preview ? `Typing: ${preview}...` : 'Thinking',
              duration: Math.floor((Date.now() - startTime) / 1000),
              tokenCount: messageContent.length,
              requestId: msgRequestId,
            });
          } else if (chunk.type === 'tool_use') {
            // Claude is using a tool
            await pushNotificationService.sendProgressNotification(msgDeviceToken, {
              projectPath: msgProjectPath,
              activity: `Using ${chunk.tool_name || 'tool'}`,
              duration: Math.floor((Date.now() - startTime) / 1000),
              tokenCount: 0,
              requestId: msgRequestId,
            });
          }
        };

        // Start time for duration tracking
        const startTime = Date.now();

        // Attach the listener
        aicliService.on('streamChunk', streamListener);

        // Use the regular AICLI service for sending prompts
        // IMPORTANT: Set streaming: true to use the processRunner with --resume fix
        const result = await aicliService.sendPrompt(validatedMessage, {
          sessionId: msgSessionId,
          requestId: msgRequestId,
          workingDirectory: msgProjectPath || process.cwd(),
          attachments: msgAttachments,
          streaming: true, // Use streaming to get processRunner with --resume
          deviceToken: msgDeviceToken, // Pass device token for stall notifications
        });

        // Log the full result structure for debugging
        logger.info('Claude response structure', {
          requestId: msgRequestId,
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
        let claudeSessionId = result?.sessionId || msgSessionId;

        // Extract content from the response structure
        // Enhanced extraction to handle new text accumulation from tool use
        if (result?.result && typeof result.result === 'string') {
          // New: Direct result from enhanced streaming (tool use text accumulation)
          content = result.result;
          logger.info('Using direct result from enhanced streaming', {
            requestId: msgRequestId,
            source: result.source || 'direct',
            contentLength: content.length,
          });
        } else if (result?.response?.result) {
          // Original: The actual Claude response is in result.response.result (from Claude CLI)
          content = result.response.result;
          logger.info('Using nested response result', {
            requestId: msgRequestId,
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

        // If content is still empty, try to extract from responses array
        if ((!content || content.trim().length === 0) && result?.response?.responses) {
          logger.info('Primary content extraction empty, checking responses array', {
            requestId: msgRequestId,
            responsesCount: result.response.responses.length,
          });

          // Try to find text content in the responses array
          for (const resp of result.response.responses) {
            if (resp.type === 'text' && resp.text) {
              content += resp.text;
            } else if (resp.type === 'text' && resp.content) {
              content += resp.content;
            } else if (resp.type === 'assistant' && resp.message) {
              content += resp.message;
            } else if (resp.type === 'message' && resp.content) {
              content += resp.content;
            } else if (resp.type === 'result' && resp.result) {
              content += resp.result;
            }
          }

          if (content.length > 0) {
            logger.info('Extracted content from responses array', {
              requestId: msgRequestId,
              contentLength: content.length,
              sessionId: claudeSessionId,
            });
          }
        }

        // Log content extraction result
        logger.info('Content extraction', {
          requestId: msgRequestId,
          contentLength: content.length,
          contentPreview: content.substring(0, 100),
          sessionId: claudeSessionId,
        });

        // Log session ID handling
        if (!msgSessionId && claudeSessionId) {
          logger.info('New conversation - using Claude-generated session ID', {
            claudeSessionId,
            requestId: msgRequestId,
          });
        } else if (msgSessionId && claudeSessionId && msgSessionId !== claudeSessionId) {
          logger.warn('Session ID mismatch - Claude returned different ID', {
            expectedSessionId: msgSessionId,
            claudeReturnedSessionId: claudeSessionId,
            requestId: msgRequestId,
          });
        }

        // Ensure session is tracked for future requests and add to session buffer
        await aicliService.sessionManager.trackSessionForRouting(claudeSessionId, msgProjectPath);
        const buffer = aicliService.sessionManager.getSessionBuffer(claudeSessionId);
        if (buffer) {
          // Only add user message if this is a new conversation (no sessionId was provided initially)
          if (!msgSessionId) {
            // This is a new conversation, add the user message
            if (!buffer.userMessages) {
              buffer.userMessages = [];
            }
            buffer.userMessages.push({
              content: queuedMsg,
              timestamp: new Date().toISOString(),
              requestId: msgRequestId,
              attachments: msgAttachments?.length || 0,
            });
            logger.info('Added user message to new session buffer', {
              requestId: msgRequestId,
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
            requestId: msgRequestId,
            deliveredVia: 'apns',
          });
          logger.info('Added assistant response to session buffer', {
            requestId: msgRequestId,
            sessionId: claudeSessionId,
          });
        }

        // Store message with ID if it's large (for fetching later)
        let largeMessageId = null;
        const MESSAGE_FETCH_THRESHOLD = 3000;
        if (content.length > MESSAGE_FETCH_THRESHOLD) {
          largeMessageId = randomUUID();

          // Store the message in the session buffer for later retrieval
          aicliService.sessionManager.storeMessage(claudeSessionId, largeMessageId, content, {
            type: 'assistant',
            requestId: msgRequestId,
            projectPath: msgProjectPath,
            originalMessage: queuedMsg,
            attachmentInfo: msgAttachments?.map((att) => ({
              name: att.name,
              mimeType: att.mimeType,
              size: att.size || (att.data.length * 3) / 4,
            })),
          });

          logger.info('Stored large message for fetching', {
            messageId: largeMessageId,
            sessionId: claudeSessionId,
            contentLength: content.length,
          });
        }

        // Check if content is empty - but handle streaming responses properly
        if (!content || content.trim().length === 0) {
          // Check if this is a streaming response with accumulated text
          const isStreamingResponse =
            result?.source === 'streaming' ||
            result?.source === 'accumulated_text' ||
            result?.streaming === true;

          if (isStreamingResponse) {
            // For streaming, the accumulated text comes back as result.result
            // The process runner returns with source: 'accumulated_text'
            if (
              result?.result &&
              typeof result.result === 'string' &&
              result.result.trim().length > 0
            ) {
              logger.info('Extracting accumulated text from streaming response', {
                requestId: msgRequestId,
                sessionId: claudeSessionId,
                source: result.source || 'streaming',
                textLength: result.result.length,
              });
              content = result.result;
            } else {
              // Streaming completed but no content accumulated
              // This can happen if Claude hasn't responded yet or if there's a genuine issue
              logger.info('Streaming response pending or empty', {
                requestId: msgRequestId,
                sessionId: claudeSessionId,
                source: result?.source,
                hasResult: !!result?.result,
              });

              // Don't send anything - let the stream complete naturally
              // The stall detection will handle truly stuck operations
              return;
            }
          } else {
            // Non-streaming empty response - this is unusual but don't send fallback
            logger.warn('Non-streaming response was empty', {
              requestId: msgRequestId,
              sessionId: claudeSessionId,
              hasResponses: !!result?.response?.responses,
              responsesCount: result?.response?.responses?.length || 0,
            });

            // Don't send fallback - let stall detection handle truly stuck operations
            return;
          }
        }

        // Send Claude response via APNS
        // Use deviceToken as deviceId since that's how we registered it
        await pushNotificationService.sendClaudeResponseNotification(msgDeviceToken, {
          message: content,
          messageId: largeMessageId, // Include message ID for large messages
          sessionId: claudeSessionId,
          projectName: msgProjectPath?.split('/').pop() || 'Project',
          projectPath: msgProjectPath,
          totalChunks: 1,
          requestId: msgRequestId,
          isLongRunningCompletion: true, // All APNS deliveries are treated as completions
          // Don't include originalMessage in payload - it can make payload too large
          // originalMessage: message, // REMOVED - can exceed 4KB limit
          attachmentInfo: msgAttachments?.map((att) => ({
            name: att.name,
            mimeType: att.mimeType,
            size: att.size || (att.data.length * 3) / 4,
          })), // Include attachment metadata without the data
          autoResponse: msgAutoResponse, // Include auto-response metadata
        });

        logger.info('Claude response delivered via APNS', {
          requestId: msgRequestId,
          deviceId: `${msgDeviceToken.substring(0, 16)}...`,
          sessionId: claudeSessionId,
          contentLength: content.length,
        });

        // Report success to queue callback
        callback(null, { success: true, sessionId: claudeSessionId });
      } catch (error) {
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
          requestId: msgRequestId,
          error: error.message,
          errorType,
          stack: error.stack,
          sessionId: msgSessionId,
          messageLength: queuedMsg?.length,
        });

        // Send detailed error notification via APNS
        try {
          await pushNotificationService.sendErrorNotification(msgDeviceToken, {
            sessionId: msgSessionId || 'error-no-session',
            projectName: msgProjectPath?.split('/').pop() || 'Project',
            projectPath: msgProjectPath,
            error: userErrorMessage,
            errorType,
            technicalDetails: process.env.NODE_ENV === 'development' ? error.message : undefined,
            requestId: msgRequestId,
          });

          logger.info('Error notification sent via APNS', {
            requestId: msgRequestId,
            deviceId: `${msgDeviceToken.substring(0, 16)}...`,
            errorType,
          });
        } catch (pushError) {
          logger.error('Failed to send error notification via APNS', {
            requestId: msgRequestId,
            originalError: error.message,
            pushError: pushError.message,
          });
        }

        // Report error to queue callback
        callback(error);
      } finally {
        // Clean up listener
        if (streamListener) {
          aicliService.removeListener('streamChunk', streamListener);
        }
      }
    });
  }
});

/**
 * POST /api/chat/auto-response/pause - Pause auto-response mode for a session
 */
router.post('/auto-response/pause', async (req, res) => {
  const { sessionId, deviceToken } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  logger.info('Pausing auto-response mode', { sessionId, requestId });

  // Pause the message queue for this session
  messageQueueManager.pauseQueue(sessionId);

  // Log queue status after pause
  const queueStatus = messageQueueManager.getQueueStatus(sessionId);
  if (queueStatus) {
    logger.info('Queue paused', {
      sessionId,
      queueLength: queueStatus.queueLength,
      processing: queueStatus.processing,
      requestId,
    });
  }

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
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  logger.info('Resuming auto-response mode', { sessionId, requestId });

  // Resume the message queue for this session
  messageQueueManager.resumeQueue(sessionId);

  // Log queue status after resume
  const queueStatus = messageQueueManager.getQueueStatus(sessionId);
  if (queueStatus) {
    logger.info('Queue resumed', {
      sessionId,
      queueLength: queueStatus.queueLength,
      processing: queueStatus.processing,
      requestId,
    });
  }

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
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  logger.info('Stopping auto-response mode', { sessionId, reason, requestId });

  // Pause the message queue for this session to stop processing
  messageQueueManager.pauseQueue(sessionId);

  // Clear any pending messages in the queue
  const queueStatus = messageQueueManager.getQueueStatus(sessionId);
  if (queueStatus && queueStatus.queueLength > 0) {
    logger.info('Clearing pending messages from queue', {
      sessionId,
      pendingMessages: queueStatus.queueLength,
      requestId,
    });
    messageQueueManager.clearQueue(sessionId);
  }

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
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

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

/**
 * POST /api/chat/kill - Kill/cancel a running Claude operation
 */
router.post('/kill', async (req, res) => {
  const { sessionId, deviceToken, reason = 'User requested cancellation' } = req.body;
  const requestId = req.headers['x-request-id'] || `REQ_${randomUUID()}`;

  logger.info('Kill operation requested', { sessionId, requestId, reason });

  if (!sessionId) {
    return res.status(400).json({
      success: false,
      error: 'Session ID is required',
    });
  }

  try {
    // Get AICLI service from app instance
    const aicliService = req.app.get('aicliService');

    if (!aicliService) {
      logger.error('AICLI service not initialized', { requestId });
      return res.status(500).json({
        success: false,
        error: 'Service temporarily unavailable',
      });
    }

    // Kill the Claude process for this session
    const killResult = await aicliService.killSession(sessionId, reason);

    if (!killResult.success) {
      logger.warn('Session kill failed', {
        sessionId,
        requestId,
        reason: killResult.error,
      });

      return res.status(404).json({
        success: false,
        error: killResult.error || 'Session not found or not running',
      });
    }

    logger.info('Session killed successfully', {
      sessionId,
      requestId,
      processKilled: killResult.processKilled,
      sessionCleaned: killResult.sessionCleaned,
    });

    // Send notification if device token provided
    if (deviceToken) {
      await pushNotificationService.sendAutoResponseControlNotification(deviceToken, {
        projectPath: killResult.projectPath,
        action: 'stop',
        reason: `Session terminated: ${reason}`,
        requestId,
      });
    }

    res.json({
      success: true,
      sessionId,
      message: 'Session terminated successfully',
      processKilled: killResult.processKilled,
      sessionCleaned: killResult.sessionCleaned,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Failed to kill session', {
      sessionId,
      requestId,
      error: error.message,
      stack: error.stack,
    });

    res.status(500).json({
      success: false,
      error: 'Failed to terminate session',
      details: error.message,
    });
  }
});

export default router;
