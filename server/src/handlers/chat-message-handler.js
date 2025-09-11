/**
 * Chat message queue handler
 * Processes messages from the queue and sends responses via APNS
 */

import { createLogger } from '../utils/logger.js';
import { storeMessage } from '../routes/messages.js';
import { randomUUID } from 'crypto';
import { AutonomousAgent } from '../services/autonomous-agent.js';

const logger = createLogger('ChatMessageHandler');

// Initialize autonomous agent with AI configuration
const autonomousAgent = new AutonomousAgent({
  enableAutoResponse: process.env.ENABLE_AUTO_RESPONSE === 'true',
  enableShowstopperDetection: true,
  maxIterations: parseInt(process.env.MAX_AUTO_ITERATIONS || '10'),
  minConfidence: parseFloat(process.env.MIN_CONFIDENCE || '0.6'),
  enableAIResponses: process.env.USE_AI_RESPONSES === 'true',
  apiKey: process.env.OPENAI_API_KEY,
  model: process.env.AI_MODEL,
  temperature: process.env.AI_TEMPERATURE,
  maxTokens: process.env.AI_MAX_TOKENS,
  dataDir: process.env.TRAINING_DATA_DIR,
});

// APNS has a max payload size of 4KB, but we'll be conservative
const MAX_MESSAGE_SIZE = 2000; // 2KB to leave room for other payload data

/**
 * Creates a message handler for processing queued chat messages
 * @param {Object} services - Service dependencies
 * @returns {Function} Message handler function
 */
export function createChatMessageHandler(services) {
  const { aicliService, pushNotificationService, webSocketService } = services;

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
      mode = 'normal', // Extract mode
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

      // Mark session as processing to prevent timeout
      if (msgSessionId) {
        const session = aicliService.sessionManager.getSession(msgSessionId);
        if (session) {
          session.isProcessing = true;
          session.processingStartTime = Date.now();
          logger.info('Session processing started', {
            sessionId: msgSessionId,
            startTime: session.processingStartTime,
          });
        } else {
          logger.warn('Session not found when trying to mark as processing', {
            sessionId: msgSessionId,
          });
        }
      }

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
        mode, // Pass mode to AICLI service
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
        // SIGTERM detection
        isSigterm: !!result?.isSigterm,
        sigtermReason: result?.sigtermReason,
      });

      // Extract the Claude session ID from the response
      // Priority: 1. Claude's actual session ID, 2. Existing session ID from request
      const claudeSessionId =
        result?.claudeSessionId ||
        result?.response?.session_id ||
        result?.sessionId ||
        msgSessionId;

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
          // Check if it's SIGTERM before giving up
          if (!result?.isSigterm) {
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
        }
      } else {
        // Non-streaming empty response - check if it's SIGTERM before giving up
        if (!result?.isSigterm) {
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
      }

      // If this was a SIGTERM, always use our continuation message instead of any partial response
      if (result?.isSigterm) {
        content =
          "I've completed many tasks and need to pause here. Send another message to continue where I left off.";
        logger.info('SIGTERM detected - replacing response with continuation message', {
          requestId: msgRequestId,
          sessionId: claudeSessionId,
          sigtermReason: result.sigtermReason,
          originalContentLength: content.length,
        });
      }

      // Check if message is too large for APNS
      let messageId = null;
      let requiresFetch = false;

      if (content.length > MAX_MESSAGE_SIZE) {
        // Store large message and send only metadata via APNS
        messageId = randomUUID();
        storeMessage(messageId, content, {
          projectPath: msgProjectPath,
          sessionId: claudeSessionId,
          requestId: msgRequestId,
          timestamp: new Date().toISOString(),
        });
        requiresFetch = true;

        logger.info('Stored large message for fetch', {
          requestId: msgRequestId,
          messageId,
          contentLength: content.length,
        });
      }

      // Send notification via APNS
      // If message is large, the notification-types.js will exclude it from payload
      await pushNotificationService.sendMessageNotification(msgDeviceToken, {
        message: requiresFetch ? '' : content, // Don't send content if it needs fetching
        messageId, // Include message ID for fetching
        requiresFetch, // Tell the app to fetch the message
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
        requiresFetch,
        messageId,
      });

      // Analyze response for auto-response if enabled
      if (msgAutoResponse && msgAutoResponse.enabled) {
        try {
          const agentAnalysis = await autonomousAgent.analyzeMessage(content, claudeSessionId);

          // Initialize session context if needed
          if (!autonomousAgent.sessions.has(claudeSessionId)) {
            autonomousAgent.initializeSession(claudeSessionId, {
              projectPath: msgProjectPath,
              projectName: msgAutoResponse.projectName || 'Unknown Project',
              currentTask: msgAutoResponse.currentTask,
            });
          }

          // Send analysis results with notification
          if (agentAnalysis.response && agentAnalysis.shouldContinue) {
            await pushNotificationService.sendAutoResponseNotification(msgDeviceToken, {
              analysis: agentAnalysis.analysis,
              suggestedResponse: agentAnalysis.response,
              confidence: agentAnalysis.response.confidence,
              shouldContinue: agentAnalysis.shouldContinue,
              sessionState: agentAnalysis.sessionState,
              projectPath: msgProjectPath,
              sessionId: claudeSessionId,
              requestId: msgRequestId,
            });

            logger.info('Auto-response analysis sent', {
              requestId: msgRequestId,
              sessionId: claudeSessionId,
              intent: agentAnalysis.analysis.intent.type,
              confidence: agentAnalysis.response.confidence,
              shouldContinue: agentAnalysis.shouldContinue,
            });
          } else if (agentAnalysis.response && agentAnalysis.response.isEscalation) {
            // Send escalation notification
            await pushNotificationService.sendEscalationNotification(msgDeviceToken, {
              reason: agentAnalysis.response.showstopperReasons || 'Critical issue detected',
              message: agentAnalysis.response.message,
              projectPath: msgProjectPath,
              sessionId: claudeSessionId,
              requestId: msgRequestId,
            });

            logger.warn('Escalation required', {
              requestId: msgRequestId,
              sessionId: claudeSessionId,
              reasons: agentAnalysis.response.showstopperReasons,
            });
          }
        } catch (analysisError) {
          logger.error('Failed to analyze for auto-response', {
            requestId: msgRequestId,
            error: analysisError.message,
          });
        }
      }

      // Clear processing state after successful completion
      if (msgSessionId) {
        const session = aicliService.sessionManager.getSession(msgSessionId);
        if (session) {
          session.isProcessing = false;
          session.processingEndTime = Date.now();
          if (session.processingStartTime) {
            const processingDuration = session.processingEndTime - session.processingStartTime;
            logger.info('Session processing completed', {
              sessionId: msgSessionId,
              duration: Math.floor(processingDuration / 1000),
              durationMs: processingDuration,
            });
          } else {
            logger.info('Session processing completed', {
              sessionId: msgSessionId,
              duration: 'unknown',
              note: 'Start time was not recorded',
            });
          }
        }
      }

      // Report success to queue callback
      callback(null, { success: true, sessionId: claudeSessionId });
    } catch (error) {
      // Regular error handling
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

      // Send error message via WebSocket to update UI state
      try {
        if (webSocketService && msgSessionId) {
          webSocketService.sendError(msgSessionId, msgRequestId, userErrorMessage, errorType);
          logger.info('Error message sent via WebSocket', {
            requestId: msgRequestId,
            sessionId: msgSessionId,
            errorType,
          });
        }
      } catch (wsError) {
        logger.error('Failed to send WebSocket message', {
          requestId: msgRequestId,
          sessionId: msgSessionId,
          error: wsError.message,
        });
      }

      // Report error to queue callback
      callback(error);
    } finally {
      // Always clean up the stream listener
      if (streamListener) {
        aicliService.removeListener('streamChunk', streamListener);
      }

      // Always clear processing state when done (success or failure)
      if (msgSessionId) {
        const session = aicliService.sessionManager.getSession(msgSessionId);
        if (session && session.isProcessing) {
          session.isProcessing = false;
          session.processingEndTime = Date.now();
          logger.info('Session processing state cleared (finally block)', {
            sessionId: msgSessionId,
          });
        }
      }
    }
  };
}
