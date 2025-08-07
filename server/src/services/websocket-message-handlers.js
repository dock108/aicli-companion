import { WebSocketUtilities } from './websocket-utilities.js';
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
      // Server is stateless - no message queue to acknowledge
      const acknowledgedCount = messageIds.length;

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
   * Handle 'streamStart' message - acknowledge stream start request
   * Server is stateless - just acknowledges the client's intent to start streaming
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

    logger.info('Stream start request acknowledged', {
      clientId,
      sessionId,
      workingDirectory: workingDirectory || process.cwd(),
    });

    // Server is stateless - just acknowledge the stream start
    // The client manages its own session state
    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('streamStart', requestId, {
        success: true,
        sessionId: sessionId,  // Echo back the session ID provided by client
        message: 'Stream ready',
        timestamp: new Date().toISOString(),
      }),
      clients
    );
    
    // Note: Message queuing removed - server doesn't track sessions
    // If a client needs missed messages, it should request them explicitly
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
   * Handle 'streamClose' message - server is stateless, just acknowledge
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

    logger.info('Stream close request acknowledged', { 
      sessionId, 
      clientId,
      clearChat 
    });

    // Server is stateless - no cleanup needed
    // iOS app manages its own session state
    
    if (clearChat) {
      // Client is clearing the chat - just acknowledge
      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('streamClose', requestId, {
          success: true,
          sessionId,
          clearChat: true,
          newSessionId: null,  // iOS will get new session ID from Claude on next message
          message: 'Ready for new conversation',
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } else {
      // Normal close - just acknowledge
      // Note: Not sending response for normal close as iOS doesn't expect it
      logger.debug('Stream close acknowledged', { sessionId, clientId });
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

      // Server is stateless - no session tracking or message queuing
      // iOS app manages its own sessions and message history
      if (sessionIds && Array.isArray(sessionIds)) {
        logger.debug('Client subscribing to sessions - acknowledged but not tracked', {
          clientId,
          sessionIds,
        });
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
   * Handle 'claudeCommand' message - pass command through to Claude
   * Server is stateless - just routes messages between iOS and Claude
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
      // Server is stateless - no session tracking needed
      let result;

      // Check if this is a meta-command (status, test) or a chat message
      const metaCommands = ['status', 'test'];  // Removed 'sessions' - server doesn't track sessions
      const isMetaCommand = metaCommands.includes(command.toLowerCase());

      if (isMetaCommand) {
        // Handle meta-commands
        switch (command.toLowerCase()) {
          case 'status':
            result = await aicliService.healthCheck();
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
          requestId,  // Pass through the request ID for response tracking
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
          projectPath, // Include project path for iOS thread routing
          error: result.error || null,
        };
      } else {
        // Agent response - extract content directly from result
        sessionLogger.debug('Processing Claude response', {
          resultKeys: result ? Object.keys(result) : [],
        });

        let content = '';
        
        // Extract content from the result object
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
          // Fallback extraction
          content = result?.text || result?.content || JSON.stringify(result);
          sessionLogger.debug('Using fallback extraction', { length: content.length });
        }

        // Extract Claude's session ID from the response if present
        let claudeSessionId = sessionId; // Use provided sessionId if available
        if (!claudeSessionId && result?.response?.session_id) {
          claudeSessionId = result.response.session_id;
          sessionLogger.info('Extracted Claude session ID from response', { claudeSessionId });
        }

        responseData = {
          content,
          success: result?.success !== false, // Default to true unless explicitly false
          sessionId: claudeSessionId, // Use Claude's session ID or echo back what was sent
          projectPath, // Include project path for iOS thread routing
          error: result?.error || null,
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
   * Handle 'getMessageHistory' message - NO LONGER SUPPORTED
   * Server is stateless and doesn't store message history
   */
  static async handleGetMessageHistoryMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    _connectionManager
  ) {
    const { sessionId } = data;

    logger.info('Client requesting message history - not supported in stateless mode', {
      clientId,
      sessionId,
    });

    // Server is stateless - doesn't store message history
    WebSocketUtilities.sendErrorMessage(
      clientId,
      requestId,
      'NOT_SUPPORTED',
      'Server is stateless and does not store message history. iOS app should manage its own message persistence.',
      clients,
      { sessionId }
    );
  }

  /**
   * Handle 'clearChat' message - server is stateless, just acknowledge
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

    logger.info('Clear chat requested - acknowledging', { sessionId, clientId });

    // Server is stateless - no cleanup needed
    // iOS app manages its own chat history
    // Next message without session ID will start a fresh conversation with Claude

    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('clearChat', requestId, {
        success: true,
        oldSessionId: sessionId,
        newSessionId: null, // iOS will get new one from Claude on next message
        message: 'Ready for new conversation',
        timestamp: new Date().toISOString(),
      }),
      clients
    );
  }

  /**
   * Handle 'registerDevice' message - server is stateless, just acknowledge
   */
  static handleRegisterDeviceMessage(clientId, requestId, data, clients) {
    const { deviceToken, deviceInfo } = data;

    logger.info('Device registration acknowledged', {
      clientId,
      platform: deviceInfo?.platform,
    });

    // Server is stateless - no push notification management
    // iOS app manages its own push notifications
    
    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('registerDevice', requestId, {
        success: true,
        message: 'Device registration acknowledged',
        timestamp: new Date().toISOString(),
      }),
      clients
    );
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
