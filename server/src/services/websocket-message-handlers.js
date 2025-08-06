import { WebSocketUtilities } from './websocket-utilities.js';
import { pushNotificationService } from './push-notification.js';
import { getMessageQueueService } from './message-queue.js';
import { createLogger } from '../utils/logger.js';
import fs from 'fs';
import path from 'path';

const logger = createLogger('WSHandlers');

/**
 * Collection of WebSocket message handlers for different message types
 */
export class WebSocketMessageHandlers {
  /**
   * Handle 'acknowledgeMessages' message - acknowledge receipt of messages
   */
  static async handleAcknowledgeMessagesMessage(clientId, requestId, data, clients) {
    const { messageIds } = data;

    if (!messageIds || !Array.isArray(messageIds)) {
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'INVALID_MESSAGE_IDS',
        'messageIds must be an array',
        clients
      );
      return;
    }

    logger.debug(`Client acknowledging ${messageIds.length} messages`, { clientId });

    try {
      const acknowledgedCount = getMessageQueueService().acknowledgeMessages(messageIds, clientId);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('acknowledgeMessages', requestId, {
          success: true,
          acknowledgedCount,
          messageIds,
          timestamp: new Date().toISOString(),
        }),
        clients
      );

      logger.debug('Successfully acknowledged messages', {
        acknowledgedCount,
        clientId,
      });
    } catch (error) {
      logger.error('Failed to acknowledge messages', { clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'ACKNOWLEDGE_FAILED',
        error.message,
        clients
      );
    }
  }

  /**
   * Handle 'ask' message - one-time prompts
   */
  static async handleAskMessage(clientId, requestId, data, aicliService, clients) {
    const { prompt, workingDirectory, options } = data;

    logger.info('Processing ask message', {
      clientId,
      prompt: `${prompt.substring(0, 50)}...`,
      workingDirectory: workingDirectory || process.cwd(),
    });

    try {
      const result = await aicliService.sendPrompt(prompt, {
        format: 'json',
        workingDirectory: workingDirectory || process.cwd(),
        ...options,
      });

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('ask', requestId, {
          success: true,
          result,
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Ask request failed', { clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'ASK_FAILED',
        error.message,
        clients,
        { prompt: prompt.substring(0, 100) }
      );
    }
  }

  /**
   * Handle 'streamStart' message - start streaming session
   */
  static async handleStreamStartMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    connectionManager
  ) {
    const { sessionId, initialPrompt, workingDirectory } = data;

    logger.info('Starting stream session', {
      clientId,
      sessionId,
      workingDirectory: workingDirectory || process.cwd(),
    });

    try {
      // Create interactive session
      const sessionResult = await aicliService.createInteractiveSession(
        sessionId,
        initialPrompt,
        workingDirectory || process.cwd()
      );

      if (sessionResult.success) {
        // Associate session with client
        connectionManager.addSessionToClient(clientId, sessionId);

        WebSocketUtilities.sendMessage(
          clientId,
          WebSocketUtilities.createResponse('streamStart', requestId, {
            success: true,
            sessionId: sessionResult.sessionId,
            message: sessionResult.message,
            timestamp: new Date().toISOString(),
          }),
          clients
        );

        // Check for any queued messages for this session
        // Track this client for the session
        getMessageQueueService().trackSessionClient(sessionId, clientId);

        // Use the new delivery method with proper validation and spacing
        getMessageQueueService().deliverQueuedMessages(sessionId, clientId, (message) => {
          return WebSocketUtilities.sendMessage(clientId, message, clients);
        });
      } else {
        throw new Error(sessionResult.message || 'Failed to create session');
      }
    } catch (error) {
      logger.error('Stream start failed', { clientId, sessionId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'STREAM_START_FAILED',
        error.message,
        clients,
        { sessionId }
      );
    }
  }

  /**
   * Handle 'streamSend' message - send message to existing session
   */
  static async handleStreamSendMessage(clientId, requestId, data, aicliService, clients) {
    const { sessionId, prompt } = data;

    logger.debug('Sending to stream session', { sessionId, clientId });

    try {
      const result = await aicliService.sendToExistingSession(sessionId, prompt);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('streamSend', requestId, {
          success: result.success,
          sessionId,
          message: result.message,
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Stream send failed', { clientId, sessionId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'STREAM_SEND_FAILED',
        error.message,
        clients,
        { sessionId }
      );
    }
  }

  /**
   * Handle 'streamClose' message - close streaming session
   */
  static async handleStreamCloseMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    connectionManager
  ) {
    const { sessionId, clearChat = false } = data;

    if (clearChat) {
      // User is clearing the chat - fully close the session
      logger.info('Clearing chat - closing session completely', { sessionId, clientId });

      try {
        // Close the session in AICLI service
        await aicliService.closeSession(sessionId);

        // Clear all queued messages for this session
        await getMessageQueueService().clearSession(sessionId);

        // Remove session from client
        connectionManager.removeSessionFromClient(clientId, sessionId);

        logger.info('Session fully closed and cleared', { sessionId });

        // Send response with instruction to generate new session ID
        WebSocketUtilities.sendMessage(
          clientId,
          WebSocketUtilities.createResponse('streamClose', requestId, {
            success: true,
            sessionId,
            clearChat: true,
            message: 'Session closed. Please generate a new session ID for the next chat.',
            timestamp: new Date().toISOString(),
          }),
          clients
        );
      } catch (error) {
        logger.error('Failed to clear chat session', { sessionId, error: error.message });
        WebSocketUtilities.sendErrorMessage(
          clientId,
          requestId,
          'CLEAR_CHAT_FAILED',
          error.message,
          clients,
          { sessionId }
        );
      }
    } else {
      // Normal close - just pause the session
      logger.info('Pausing stream session (will remain active for continuation)', {
        sessionId,
        clientId,
      });

      try {
        // Instead of closing the session, just remove it from the client's active sessions
        // but keep the session alive in the AICLI service for continuation
        connectionManager.removeSessionFromClient(clientId, sessionId);

        // Mark the client as no longer active for this session, but don't close the session
        logger.debug('Session paused - can be continued later', { sessionId });

        // Note: Not sending response message for 'streamClose' as iOS client doesn't expect it
        // and fails to parse it. The session was successfully paused if we reach this point.
        logger.debug('Session pause complete', { sessionId, clientId });
      } catch (error) {
        logger.error('Stream close failed', { sessionId, clientId, error: error.message });
        WebSocketUtilities.sendErrorMessage(
          clientId,
          requestId,
          'STREAM_CLOSE_FAILED',
          error.message,
          clients,
          { sessionId }
        );
      }
    }
  }

  /**
   * Handle 'permission' message - respond to permission prompts
   */
  static async handlePermissionMessage(clientId, requestId, data, aicliService, clients) {
    const { sessionId, response } = data;

    logger.info('Processing permission response', { sessionId, response, clientId });

    try {
      const result = await aicliService.handlePermissionPrompt(sessionId, response);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('permission', requestId, {
          success: true,
          sessionId,
          accepted: result.accepted,
          message: result.message || 'Permission processed',
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Permission handling failed', { clientId, sessionId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'PERMISSION_FAILED',
        error.message,
        clients,
        { sessionId, response }
      );
    }
  }

  /**
   * Handle 'ping' message - respond with pong
   */
  static handlePingMessage(clientId, requestId, data, aicliService, clients) {
    const { timestamp: clientTimestamp } = data || {};

    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('pong', requestId, {
        clientTimestamp,
        serverTime: new Date().toISOString(),
      }),
      clients
    );
  }

  /**
   * Handle 'subscribe' message - subscribe to events and sessions
   */
  static async handleSubscribeMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    connectionManager
  ) {
    const { events, sessionIds } = data;

    logger.info('Client subscribing to events', { clientId, events });
    if (sessionIds) {
      logger.info('Client subscribing to sessions', {
        clientId,
        sessionIds,
        count: sessionIds.length,
      });
    }

    try {
      if (!Array.isArray(events)) {
        throw new Error('Events must be an array');
      }

      // Subscribe client to events
      connectionManager.subscribeClient(clientId, events);

      // Subscribe client to sessions and deliver queued messages
      if (sessionIds && Array.isArray(sessionIds)) {
        for (const sessionId of sessionIds) {
          // Add session to client tracking
          connectionManager.addSessionToClient(clientId, sessionId);

          // Track this client for the session in message queue
          getMessageQueueService().trackSessionClient(sessionId, clientId);

          // Use the improved delivery method with validation and deduplication
          getMessageQueueService().deliverQueuedMessages(sessionId, clientId, (message) => {
            return WebSocketUtilities.sendMessage(clientId, message, clients);
          });
        }
      }

      // Note: Not sending response message for 'subscribe' as iOS client doesn't expect it
      // and fails to parse it. The subscription was successful if we reach this point.
      logger.info('Successfully subscribed client', {
        clientId,
        eventCount: events.length,
        sessionCount: sessionIds?.length || 0,
      });
    } catch (error) {
      logger.error('Subscription failed', { clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'SUBSCRIPTION_FAILED',
        error.message,
        clients,
        { requestedEvents: events, requestedSessions: sessionIds }
      );
    }
  }

  /**
   * Handle 'setWorkingDirectory' message - set working directory for client
   */
  static async handleSetWorkingDirectoryMessage(clientId, requestId, data, aicliService, clients) {
    const { workingDirectory } = data;

    logger.info('Setting working directory', { clientId, workingDirectory });

    try {
      // Validate the working directory exists
      const resolvedPath = path.resolve(workingDirectory);

      if (!fs.existsSync(resolvedPath)) {
        throw new Error(`Directory does not exist: ${resolvedPath}`);
      }

      const stats = fs.statSync(resolvedPath);
      if (!stats.isDirectory()) {
        throw new Error(`Path is not a directory: ${resolvedPath}`);
      }

      // Store working directory for this client (if needed by service)
      // Note: This would typically be handled by the AICLI service configuration

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('setWorkingDirectory', requestId, {
          success: true,
          workingDirectory: resolvedPath,
          message: 'Working directory set successfully',
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Set working directory failed', { clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'SET_DIRECTORY_FAILED',
        error.message,
        clients,
        { requestedPath: workingDirectory }
      );
    }
  }

  /**
   * Handle 'claudeCommand' message - execute Claude agent commands
   */
  static async handleClaudeCommandMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    connectionManager
  ) {
    const { sessionId, command, args, projectPath } = data;

    // Create logger with session context for this request
    const sessionLogger = logger.child({ sessionId, clientId, requestId });

    sessionLogger.info('Executing Claude command', {
      command: command.substring(0, 50),
      hasArgs: !!args,
      projectPath,
    });

    try {
      // Associate session with client if not already done
      if (sessionId) {
        connectionManager.addSessionToClient(clientId, sessionId);

        // Session tracking removed - server is now message-driven, not state-driven
      }

      let result;

      // Check if this is a meta-command (status, sessions, test) or a chat message
      const metaCommands = ['status', 'sessions', 'test'];
      const isMetaCommand = metaCommands.includes(command.toLowerCase());

      if (isMetaCommand) {
        // Handle meta-commands
        switch (command.toLowerCase()) {
          case 'status':
            result = await aicliService.healthCheck();
            break;
          case 'sessions':
            result = { sessions: aicliService.getActiveSessions() };
            break;
          case 'test':
            result = await aicliService.testAICLICommand(args?.[0] || 'version');
            break;
        }
      } else {
        // Treat as agent prompt - send to Claude for autonomous interaction
        sessionLogger.info('Processing as agent prompt', {
          prompt: `${command.substring(0, 50)}...`,
        });

        result = await aicliService.sendPrompt(command, {
          sessionId,
          streaming: true, // Enable streaming for agent mode
          workingDirectory: projectPath || process.cwd(),
          skipPermissions: true, // Enable autonomous behavior
          format: 'text', // More natural for chat
        });
      }

      // Format response based on whether it's a meta-command or agent response
      let responseData;
      if (isMetaCommand) {
        // Meta-command response
        responseData = {
          content: result.error ? result.error : JSON.stringify(result, null, 2),
          success: !result.error,
          sessionId,
          error: result.error || null,
        };
      } else {
        // Agent response - get aggregated content from session buffer
        sessionLogger.debug('Checking session buffer');
        const buffer = aicliService.sessionManager.getSessionBuffer(sessionId);
        let content = '';

        if (!buffer) {
          sessionLogger.debug('No buffer found for session');
        } else {
          sessionLogger.debug('Buffer found', {
            assistantMessageCount: buffer.assistantMessages?.length || 0,
          });
        }

        if (buffer && buffer.assistantMessages && buffer.assistantMessages.length > 0) {
          // Aggregate all assistant messages from the session
          const aggregatedContent = aicliService.aggregateBufferedContent(buffer);
          sessionLogger.debug('Aggregated content', { blockCount: aggregatedContent.length });

          // Convert aggregated content blocks to text
          const textBlocks = [];
          aggregatedContent.forEach((block) => {
            if (block.type === 'text' && block.text) {
              textBlocks.push(block.text);
            }
          });

          content = textBlocks.join('\n\n');
          sessionLogger.debug('Aggregated assistant messages', {
            messageCount: buffer.assistantMessages.length,
            textBlockCount: textBlocks.length,
          });
        } else {
          // Fallback to result object
          sessionLogger.debug('No buffered messages, using result object', {
            resultKeys: Object.keys(result),
          });

          // The result object from sendPrompt contains the final response
          if (result && result.response) {
            // Check if response is the final result object from AICLI
            if (typeof result.response === 'object' && result.response.result) {
              content = result.response.result;
              sessionLogger.debug('Using result.response.result', { length: content.length });
            } else if (result.response.text) {
              content = result.response.text;
              sessionLogger.debug('Using result.response.text', { length: content.length });
            } else if (typeof result.response === 'string') {
              content = result.response;
              sessionLogger.debug('Using result.response as string', { length: content.length });
            }
          } else if (result && result.result) {
            content = result.result;
            sessionLogger.debug('Using result.result field', { length: content.length });
          }

          if (!content) {
            // Last resort fallback
            content = result.text || result.content || JSON.stringify(result);
            sessionLogger.debug('Using final fallback extraction', { length: content.length });
          }
        }

        // Extract Claude's session ID from the response
        let claudeSessionId = sessionId; // Use provided sessionId if available
        if (!claudeSessionId && result && result.response && result.response.session_id) {
          claudeSessionId = result.response.session_id;
          sessionLogger.info('Extracted Claude session ID from response', { claudeSessionId });
        }

        responseData = {
          content,
          success: result.success !== false, // Default to true unless explicitly false
          sessionId: claudeSessionId, // Use Claude's session ID
          error: result.error || null,
        };
      }

      const response = WebSocketUtilities.createResponse('claudeResponse', requestId, responseData);

      const messageSent = WebSocketUtilities.sendMessage(clientId, response, clients);
      if (messageSent) {
        sessionLogger.debug('Claude response sent successfully');
      } else {
        sessionLogger.warn('Failed to send Claude response');
      }
    } catch (error) {
      sessionLogger.error('Claude command failed', { error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'COMMAND_FAILED',
        error.message,
        clients,
        { command, args }
      );
    }
  }

  /**
   * Handle 'getMessageHistory' message - retrieve message history for a session
   */
  static async handleGetMessageHistoryMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    _connectionManager
  ) {
    const { sessionId, limit, offset } = data;

    logger.info('Client requesting message history', {
      clientId,
      sessionId,
      limit: limit || 'all',
      offset: offset || 0,
    });

    try {
      // Validate session exists
      const session = await aicliService.getSession(sessionId);
      if (!session) {
        throw new Error(`Session ${sessionId} not found`);
      }

      // Get message buffer from session manager
      let buffer = aicliService.sessionManager.getSessionBuffer(sessionId);

      // If no buffer exists in memory, try to load from persistence
      if (!buffer) {
        logger.debug('No message buffer in memory, loading from persistence', { sessionId });
        const { sessionPersistence } = await import('./session-persistence.js');
        const persistedBuffer = await sessionPersistence.loadMessageBuffer(sessionId);

        if (persistedBuffer) {
          logger.debug('Loaded message buffer from persistence', { sessionId });
          // Restore the buffer to session manager
          aicliService.sessionManager.setSessionBuffer(sessionId, persistedBuffer);
          buffer = persistedBuffer;
        } else {
          logger.debug('No persisted message buffer found - may be new session', { sessionId });
        }
      }

      // Get user prompts and assistant messages
      const messages = [];

      // Add user prompts with type 'user'
      if (buffer && buffer.userPrompts) {
        buffer.userPrompts.forEach((prompt, index) => {
          messages.push({
            id: `user-${index}`,
            type: 'user',
            content: prompt,
            timestamp: null, // User prompts don't have timestamps in current implementation
          });
        });
      }

      // Add assistant messages with full content
      if (buffer && buffer.assistantMessages) {
        buffer.assistantMessages.forEach((message) => {
          messages.push({
            id: message.id,
            type: 'assistant',
            content: message.content,
            model: message.model,
            usage: message.usage,
            timestamp: message.timestamp || new Date().toISOString(),
          });
        });
      }

      // Sort messages by timestamp (if available)
      // TODO: [OPTIMIZE] Better message ordering based on actual conversation flow
      // Current implementation may not preserve exact conversation order

      // Apply pagination if requested
      const totalMessages = messages.length;
      const startIndex = offset || 0;
      const endIndex = limit ? startIndex + limit : totalMessages;
      const paginatedMessages = messages.slice(startIndex, endIndex);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('getMessageHistory', requestId, {
          success: true,
          sessionId,
          messages: paginatedMessages,
          totalCount: totalMessages,
          offset: startIndex,
          limit: limit || null,
          hasMore: endIndex < totalMessages,
          sessionMetadata: {
            workingDirectory: session.workingDirectory,
            conversationStarted: session.conversationStarted,
            createdAt: session.createdAt,
            lastActivity: session.lastActivity,
          },
          timestamp: new Date().toISOString(),
        }),
        clients
      );

      logger.debug('Sent message history', {
        sent: paginatedMessages.length,
        total: totalMessages,
        sessionId,
      });
    } catch (error) {
      logger.error('Get message history failed', { clientId, sessionId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'GET_HISTORY_FAILED',
        error.message,
        clients,
        { sessionId }
      );
    }
  }

  /**
   * Handle 'clearChat' message - clear current chat and start fresh
   */
  static async handleClearChatMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    connectionManager
  ) {
    const { sessionId } = data;

    logger.info('Clear chat requested', { sessionId, clientId });

    try {
      // Close the session completely
      await aicliService.closeSession(sessionId);

      // Clear all queued messages
      await getMessageQueueService().clearSession(sessionId);

      // Remove session from client
      connectionManager.removeSessionFromClient(clientId, sessionId);

      // Generate a new session ID for the client to use
      const { v4: uuidv4 } = await import('uuid');
      const newSessionId = uuidv4();

      logger.info('Chat cleared successfully', { oldSessionId: sessionId, newSessionId });

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('clearChat', requestId, {
          success: true,
          oldSessionId: sessionId,
          newSessionId,
          message: 'Chat cleared successfully',
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Failed to clear chat', { sessionId, clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'CLEAR_CHAT_FAILED',
        error.message,
        clients,
        { sessionId }
      );
    }
  }

  /**
   * Handle 'registerDevice' message - register device for push notifications
   */
  static handleRegisterDeviceMessage(clientId, requestId, data, clients) {
    const { deviceToken, deviceInfo } = data;

    logger.info('Registering device', {
      clientId,
      tokenPrefix: `${deviceToken?.substring(0, 20)}...`,
      platform: deviceInfo?.platform,
    });

    try {
      // Store device token with client
      const client = clients.get(clientId);
      if (client) {
        client.deviceToken = deviceToken;
        client.deviceInfo = deviceInfo;
      }

      // Register with push notification service
      pushNotificationService.registerDevice(clientId, deviceToken, deviceInfo);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('registerDevice', requestId, {
          success: true,
          message: 'Device registered for push notifications',
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Device registration failed', { clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'DEVICE_REGISTRATION_FAILED',
        error.message,
        clients,
        { hasDeviceToken: !!deviceToken }
      );
    }
  }

  /**
   * Handle client backgrounding/foregrounding
   */
  static async handleClientBackgroundingMessage(
    clientId,
    data,
    requestId,
    clients,
    claudeService,
    _connectionManager
  ) {
    const { isBackgrounded, sessionId } = data;

    logger.info('Client backgrounding state change', {
      clientId,
      sessionId,
      isBackgrounded,
    });

    try {
      const client = clients.get(clientId);
      if (!client) {
        throw new Error('Client not found');
      }

      // Update client state
      client.isBackgrounded = isBackgrounded;

      // Update session state if session exists
      if (sessionId && claudeService.hasSession(sessionId)) {
        if (isBackgrounded) {
          await claudeService.markSessionBackgrounded(sessionId);
        } else {
          await claudeService.markSessionForegrounded(sessionId);
        }
      }

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('client_backgrounding', requestId, {
          success: true,
          isBackgrounded,
          sessionId,
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      logger.error('Client backgrounding update failed', { clientId, error: error.message });
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'BACKGROUNDING_UPDATE_FAILED',
        error.message,
        clients
      );
    }
  }

  /**
   * Get all available message handlers
   */
  static getAllHandlers() {
    return {
      ask: this.handleAskMessage,
      streamStart: this.handleStreamStartMessage,
      streamSend: this.handleStreamSendMessage,
      streamClose: this.handleStreamCloseMessage,
      permission: this.handlePermissionMessage,
      ping: this.handlePingMessage,
      subscribe: this.handleSubscribeMessage,
      setWorkingDirectory: this.handleSetWorkingDirectoryMessage,
      claudeCommand: this.handleClaudeCommandMessage,
      getMessageHistory: this.handleGetMessageHistoryMessage,
      registerDevice: this.handleRegisterDeviceMessage,
      acknowledgeMessages: this.handleAcknowledgeMessagesMessage,
      clearChat: this.handleClearChatMessage,
      client_backgrounding: this.handleClientBackgroundingMessage,
    };
  }

  /**
   * Get handler for specific message type
   */
  static getHandler(messageType) {
    const handlers = this.getAllHandlers();
    return handlers[messageType] || null;
  }

  /**
   * Get list of supported message types
   */
  static getSupportedTypes() {
    return Object.keys(this.getAllHandlers());
  }
}
