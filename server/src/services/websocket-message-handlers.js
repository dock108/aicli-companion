import { WebSocketUtilities } from './websocket-utilities.js';
import { pushNotificationService } from './push-notification.js';
import { messageQueueService } from './message-queue.js';
import fs from 'fs';
import path from 'path';

/**
 * Collection of WebSocket message handlers for different message types
 */
export class WebSocketMessageHandlers {
  /**
   * Handle 'ask' message - one-time prompts
   */
  static async handleAskMessage(clientId, requestId, data, aicliService, clients) {
    const { prompt, workingDirectory, options } = data;

    console.log(`🤖 Processing ask message for client ${clientId}`);
    console.log(`   Prompt: "${prompt}"`);
    console.log(`   Working dir: ${workingDirectory || process.cwd()}`);

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
      console.error(`❌ Ask request failed:`, error);
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

    console.log(`🌊 Starting stream session for client ${clientId}`);
    console.log(`   Session ID: ${sessionId}`);
    console.log(`   Working dir: ${workingDirectory || process.cwd()}`);

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
        messageQueueService.trackSessionClient(sessionId, clientId);

        const queuedMessages = messageQueueService.getUndeliveredMessages(sessionId, clientId);
        if (queuedMessages.length > 0) {
          console.log(
            `📬 Delivering ${queuedMessages.length} queued messages for session ${sessionId}`
          );

          const deliveredMessageIds = [];
          for (const queuedMessage of queuedMessages) {
            const success = WebSocketUtilities.sendMessage(
              clientId,
              queuedMessage.message,
              clients
            );
            if (success) {
              deliveredMessageIds.push(queuedMessage.id);
            }
          }

          if (deliveredMessageIds.length > 0) {
            messageQueueService.markAsDelivered(deliveredMessageIds, clientId);
          }
        }
      } else {
        throw new Error(sessionResult.message || 'Failed to create session');
      }
    } catch (error) {
      console.error(`❌ Stream start failed:`, error);
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

    console.log(`📤 Sending to stream session ${sessionId} from client ${clientId}`);

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
      console.error(`❌ Stream send failed:`, error);
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
    const { sessionId } = data;

    console.log(
      `⏸️ Pausing stream session ${sessionId} for client ${clientId} (session will remain active for continuation)`
    );

    try {
      // Instead of closing the session, just remove it from the client's active sessions
      // but keep the session alive in the AICLI service for continuation
      connectionManager.removeSessionFromClient(clientId, sessionId);

      // Mark the client as no longer active for this session, but don't close the session
      console.log(`📝 Session ${sessionId} paused - can be continued later`);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('streamClose', requestId, {
          success: true,
          sessionId,
          message: 'Session paused - can be continued later',
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      console.error(`❌ Stream close failed:`, error);
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

  /**
   * Handle 'permission' message - respond to permission prompts
   */
  static async handlePermissionMessage(clientId, requestId, data, aicliService, clients) {
    const { sessionId, response } = data;

    console.log(`🔐 Processing permission response for session ${sessionId}: ${response}`);

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
      console.error(`❌ Permission handling failed:`, error);
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

    console.log(`📡 Client ${clientId} subscribing to events:`, events);
    if (sessionIds) {
      console.log(`📡 Client ${clientId} subscribing to sessions:`, sessionIds);
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
          messageQueueService.trackSessionClient(sessionId, clientId);

          // Check for and deliver any queued messages
          const undeliveredMessages = messageQueueService.getUndeliveredMessages(
            sessionId,
            clientId
          );

          if (undeliveredMessages.length > 0) {
            console.log(
              `📬 Found ${undeliveredMessages.length} queued messages for session ${sessionId}`
            );

            // Send each queued message to the client
            const deliveredMessageIds = [];
            for (const queuedMessage of undeliveredMessages) {
              const success = WebSocketUtilities.sendMessage(
                clientId,
                queuedMessage.message,
                clients
              );

              if (success) {
                deliveredMessageIds.push(queuedMessage.id);
                console.log(
                  `✅ Delivered queued message ${queuedMessage.id} to client ${clientId}`
                );
              }
            }

            // Mark messages as delivered
            if (deliveredMessageIds.length > 0) {
              messageQueueService.markAsDelivered(deliveredMessageIds, clientId);
              console.log(
                `📨 Delivered ${deliveredMessageIds.length} queued messages for session ${sessionId}`
              );
            }
          }
        }
      }

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('subscribe', requestId, {
          success: true,
          subscribedEvents: events,
          sessionIds: sessionIds || [],
          message: `Subscribed to ${events.length} events${sessionIds ? ` and ${sessionIds.length} sessions` : ''}`,
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      console.error(`❌ Subscription failed:`, error);
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

    console.log(`📁 Setting working directory for client ${clientId}: ${workingDirectory}`);

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
      console.error(`❌ Set working directory failed:`, error);
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

    console.log(`⚡ Executing Claude command for client ${clientId}:`);
    console.log(`   Session: ${sessionId}`);
    console.log(`   Command: ${command}`);
    console.log(`   Args: ${JSON.stringify(args)}`);
    console.log(`   Project Path: ${projectPath}`);

    try {
      // Associate session with client if not already done
      if (sessionId) {
        connectionManager.addSessionToClient(clientId, sessionId);

        // Check if this session was backgrounded and mark it as foregrounded
        if (aicliService.hasSession(sessionId)) {
          await aicliService.markSessionForegrounded(sessionId);
        }
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
        console.log(`🤖 Processing as agent prompt: "${command}"`);

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
        console.log(`🔍 Checking session buffer for sessionId: ${sessionId}`);
        const buffer = aicliService.sessionManager.getSessionBuffer(sessionId);
        let content = '';

        if (!buffer) {
          console.log(`⚠️ No buffer found for session ${sessionId}`);
        } else {
          console.log(
            `📋 Buffer found with ${buffer.assistantMessages?.length || 0} assistant messages`
          );
        }

        if (buffer && buffer.assistantMessages && buffer.assistantMessages.length > 0) {
          // Aggregate all assistant messages from the session
          const aggregatedContent = aicliService.aggregateBufferedContent(buffer);
          console.log(`🔗 Aggregated content has ${aggregatedContent.length} blocks`);

          // Convert aggregated content blocks to text
          const textBlocks = [];
          aggregatedContent.forEach((block) => {
            if (block.type === 'text' && block.text) {
              textBlocks.push(block.text);
            }
          });

          content = textBlocks.join('\n\n');
          console.log(
            `📝 Aggregated ${buffer.assistantMessages.length} assistant messages into response with ${textBlocks.length} text blocks`
          );
        } else {
          // Fallback to result object
          console.log(`⚠️ No buffered messages, falling back to result object`);
          console.log(`📦 Result object keys:`, Object.keys(result));
          console.log(`📦 Result object:`, JSON.stringify(result, null, 2));

          // The result object from sendPrompt contains the final response
          if (result && result.response) {
            // Check if response is the final result object from AICLI
            if (typeof result.response === 'object' && result.response.result) {
              content = result.response.result;
              console.log(`📄 Using result.response.result field (${content.length} chars)`);
            } else if (result.response.text) {
              content = result.response.text;
              console.log(`📄 Using result.response.text field (${content.length} chars)`);
            } else if (typeof result.response === 'string') {
              content = result.response;
              console.log(`📄 Using result.response as string (${content.length} chars)`);
            }
          } else if (result && result.result) {
            content = result.result;
            console.log(`📄 Using result.result field (${content.length} chars)`);
          }

          if (!content) {
            // Last resort fallback
            content = result.text || result.content || JSON.stringify(result);
            console.log(`📄 Using final fallback extraction (${content.length} chars)`);
          }
        }

        responseData = {
          content,
          success: result.success !== false, // Default to true unless explicitly false
          sessionId,
          error: result.error || null,
        };
      }

      const response = WebSocketUtilities.createResponse('claudeResponse', requestId, responseData);

      const messageSent = WebSocketUtilities.sendMessage(clientId, response, clients);
      if (messageSent) {
        console.log(`✅ Claude response sent successfully to client ${clientId}`);
      } else {
        console.warn(`⚠️ Failed to send Claude response to client ${clientId}`);
      }
    } catch (error) {
      console.error(`❌ Claude command failed:`, error);
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
   * Handle 'client_backgrounding' message - client going to background
   */
  static async handleClientBackgroundingMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    _connectionManager
  ) {
    // Handle the case where data might be undefined or the message structure is different
    const sessionId = data?.sessionId || '';
    const timestamp = data?.timestamp || new Date().toISOString();

    console.log(`📱 Client ${clientId} entering background mode (session: ${sessionId})`);

    // Update client state (this would typically be stored in connection manager)
    const client = clients.get(clientId);
    if (client) {
      client.isBackgrounded = true;
      client.lastActivity = new Date();
      client.backgroundTimestamp = timestamp;

      // If there's an active session, mark it as backgrounded but don't kill it
      if (sessionId && sessionId !== '') {
        console.log(`⏸️ Marking session ${sessionId} as backgrounded`);
        // Mark session as backgrounded in the AICLI service to extend timeout
        await aicliService.markSessionBackgrounded(sessionId);
        client.backgroundedSessionId = sessionId;
      }
    }

    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('client_backgrounding', requestId, {
        success: true,
        isBackgrounding: true,
        message: 'Client backgrounded, session preserved',
        timestamp: new Date().toISOString(),
      }),
      clients
    );
  }

  /**
   * Handle 'registerDevice' message - register device for push notifications
   */
  static handleRegisterDeviceMessage(clientId, requestId, data, clients) {
    const { deviceToken, deviceInfo } = data;

    console.log(`📱 Registering device for client ${clientId}`);
    console.log(`   Device token: ${deviceToken?.substring(0, 20)}...`);
    console.log(`   Device info:`, deviceInfo);

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
      console.error(`❌ Device registration failed:`, error);
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
      client_backgrounding: this.handleClientBackgroundingMessage,
      registerDevice: this.handleRegisterDeviceMessage,
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
