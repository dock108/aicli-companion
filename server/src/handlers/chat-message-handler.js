/**
 * Chat message queue handler
 * Processes messages from the queue and sends responses via APNS
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('ChatMessageHandler');

/**
 * Creates a message handler for processing queued chat messages
 * @param {Object} services - Service dependencies
 * @returns {Function} Message handler function
 */
export function createChatMessageHandler(services) {
  const { aicliService, pushNotificationService } = services;

  return async function handleQueuedMessage(queuedMessage, callback) {
    // Process Claude request asynchronously and deliver via APNS
    const { message: msgData } = queuedMessage;
    const {
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
        responseType: typeof result?.response,
        // Only log keys if response is an object, not a string
        responseKeys:
          result?.response && typeof result?.response === 'object'
            ? Object.keys(result.response).slice(0, 10) // Limit to first 10 keys
            : [],
        responseLength: typeof result?.response === 'string' ? result?.response?.length : undefined,
        responseHasResult: !!result?.response?.result,
        responseResultType: typeof result?.response?.result,
        // New fields for enhanced text accumulation
        resultSource: result?.source || 'unknown',
        directResult: !!result?.result,
        directResultType: typeof result?.result,
        directResultLength: result?.result?.length || 0,
      });

      // Extract the Claude session ID from the first response
      const claudeSessionId = result?.sessionId || msgSessionId || result?.response?.session_id;

      if (!msgSessionId && claudeSessionId) {
        logger.info('New conversation - using Claude-generated session ID', {
          requestId: msgRequestId,
          claudeSessionId,
        });
      }

      // Extract content using the enhanced accumulation logic
      let content = '';

      // Priority 1: Check for streaming completion with accumulated text
      if (result?.result && typeof result.result === 'string') {
        // Direct result from streaming or accumulated text
        content = result.result;
        logger.info('Using direct result', {
          requestId: msgRequestId,
          contentLength: content.length,
        });
      }
      // Priority 2: Check if response itself is a string (plain text response)
      else if (result?.response && typeof result.response === 'string') {
        content = result.response;
        logger.info('Using plain text response', {
          requestId: msgRequestId,
          contentLength: content.length,
        });
      }
      // Priority 3: Check nested response.result (non-streaming structured response)
      else if (result?.response?.result && typeof result.response.result === 'string') {
        content = result.response.result;
        logger.info('Using nested response result', {
          requestId: msgRequestId,
          contentLength: content.length,
        });
      }
      // Priority 4: Check for streaming scenarios
      else if (result?.source === 'streaming') {
        // Streaming was enabled but we need to check for content
        if (result?.result && result.result.length > 0) {
          // We have accumulated streaming content
          logger.info('Using streaming accumulated text', {
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
          callback(null, { success: true, sessionId: claudeSessionId });
          return;
        }
      } else {
        // Non-streaming empty response - this is unusual but don't send fallback
        logger.warn('Non-streaming response was empty', {
          requestId: msgRequestId,
          sessionId: claudeSessionId,
          hasResponses:
            typeof result?.response === 'object' ? !!result?.response?.responses : false,
          responsesCount:
            typeof result?.response === 'object' ? result?.response?.responses?.length || 0 : 0,
          responseType: typeof result?.response,
        });

        // Don't send fallback - let stall detection handle truly stuck operations
        callback(null, { success: true, sessionId: claudeSessionId });
        return;
      }

      // Send Claude response via APNS
      await pushNotificationService.sendMessageNotification(msgDeviceToken, {
        message: content,
        projectPath: msgProjectPath,
        sessionId: claudeSessionId,
        requestId: msgRequestId,
        timestamp: new Date().toISOString(),
        type: 'response',
        attachments: (msgAttachments || []).map((att) => ({
          id: att.id,
          mimeType: att.mimeType,
          filename: att.filename,
          size: att.data ? att.data.length : 0,
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
        userErrorMessage = 'Claude took too long to respond. Please try again.';
        errorType = 'TIMEOUT';
      } else if (
        error.message?.includes('Session expired') ||
        error.message?.includes('session not found')
      ) {
        userErrorMessage = 'Your conversation session has expired. Starting a new one...';
        errorType = 'SESSION_EXPIRED';
      } else if (error.message?.includes('Claude CLI not found')) {
        userErrorMessage = 'Claude CLI is not available. Please check the server configuration.';
        errorType = 'CLI_NOT_FOUND';
      } else if (error.message?.includes('API quota exceeded')) {
        userErrorMessage = 'API quota exceeded. Please try again later.';
        errorType = 'QUOTA_EXCEEDED';
      }

      logger.error('Failed to process Claude request', {
        requestId: msgRequestId,
        error: error.message,
        stack: error.stack,
        errorType,
      });

      // Send error notification via APNS
      try {
        await pushNotificationService.sendErrorNotification(msgDeviceToken, {
          error: userErrorMessage,
          errorType,
          projectPath: msgProjectPath,
          sessionId: msgSessionId,
          requestId: msgRequestId,
          timestamp: new Date().toISOString(),
        });

        logger.info('Error notification sent via APNS', {
          requestId: msgRequestId,
          deviceId: `${msgDeviceToken.substring(0, 16)}...`,
          errorType,
        });
      } catch (pushError) {
        logger.error('Failed to send error notification via APNS', {
          requestId: msgRequestId,
          error: pushError.message,
        });
      }

      // Report error to queue callback
      callback(error);
    } finally {
      // Always clean up the stream listener
      if (streamListener) {
        aicliService.removeListener('streamChunk', streamListener);
      }
    }
  };
}
