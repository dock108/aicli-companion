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
        const queuedMessages = messageQueueService.getQueuedMessages(sessionId);
        if (queuedMessages.length > 0) {
          console.log(
            `📬 Delivering ${queuedMessages.length} queued messages for session ${sessionId}`
          );

          for (const queuedMessage of queuedMessages) {
            WebSocketUtilities.sendMessage(clientId, queuedMessage, clients);
          }

          messageQueueService.markMessagesDelivered(sessionId);
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

    console.log(`🔚 Closing stream session ${sessionId} for client ${clientId}`);

    try {
      const result = await aicliService.closeSession(sessionId);

      // Remove session from client
      connectionManager.removeSessionFromClient(clientId, sessionId);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('streamClose', requestId, {
          success: result.success,
          sessionId,
          message: result.message,
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
  static handlePingMessage(clientId, requestId, data, clients) {
    const { timestamp: clientTimestamp } = data || {};

    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('pong', requestId, {
        clientTimestamp,
        serverTimestamp: new Date().toISOString(),
      }),
      clients
    );
  }

  /**
   * Handle 'subscribe' message - subscribe to events
   */
  static handleSubscribeMessage(clientId, requestId, data, clients, connectionManager) {
    const { events } = data;

    console.log(`📡 Client ${clientId} subscribing to events:`, events);

    try {
      if (!Array.isArray(events)) {
        throw new Error('Events must be an array');
      }

      // Subscribe client to events
      connectionManager.subscribeClient(clientId, events);

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('subscribe', requestId, {
          success: true,
          subscribedEvents: events,
          message: `Subscribed to ${events.length} events`,
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
        { requestedEvents: events }
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
   * Handle 'aicliCommand' message - execute direct AICLI commands
   */
  static async handleAICLICommandMessage(
    clientId,
    requestId,
    data,
    aicliService,
    clients,
    connectionManager
  ) {
    const { sessionId, command, args, workingDirectory: _workingDirectory } = data;

    console.log(`⚡ Executing AICLI command for client ${clientId}:`);
    console.log(`   Session: ${sessionId}`);
    console.log(`   Command: ${command}`);
    console.log(`   Args: ${JSON.stringify(args)}`);

    try {
      // Associate session with client if not already done
      if (sessionId) {
        connectionManager.addSessionToClient(clientId, sessionId);
      }

      // This would be handled by the AICLI service based on the command
      // For now, we'll delegate to the appropriate service method
      let result;

      switch (command) {
        case 'status':
          result = await aicliService.healthCheck();
          break;
        case 'sessions':
          result = { sessions: aicliService.getActiveSessions() };
          break;
        case 'test':
          result = await aicliService.testAICLICommand(args?.[0] || 'version');
          break;
        default:
          throw new Error(`Unknown command: ${command}`);
      }

      WebSocketUtilities.sendMessage(
        clientId,
        WebSocketUtilities.createResponse('aicliCommand', requestId, {
          success: true,
          command,
          result,
          timestamp: new Date().toISOString(),
        }),
        clients
      );
    } catch (error) {
      console.error(`❌ AICLI command failed:`, error);
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
  static handleClientBackgroundingMessage(clientId, requestId, data, clients) {
    const { isBackgrounding } = data;

    console.log(
      `📱 Client ${clientId} ${isBackgrounding ? 'entering' : 'leaving'} background mode`
    );

    // Update client state (this would typically be stored in connection manager)
    const client = clients.get(clientId);
    if (client) {
      client.isBackgrounded = isBackgrounding;
      client.lastActivity = new Date();
    }

    WebSocketUtilities.sendMessage(
      clientId,
      WebSocketUtilities.createResponse('client_backgrounding', requestId, {
        success: true,
        isBackgrounding,
        message: `Background state ${isBackgrounding ? 'enabled' : 'disabled'}`,
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
      aicliCommand: this.handleAICLICommandMessage,
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
