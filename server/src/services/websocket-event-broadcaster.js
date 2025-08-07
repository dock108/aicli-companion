import { EventEmitter } from 'events';
import { WebSocketUtilities } from './websocket-utilities.js';

/**
 * Handles AICLI service events and broadcasts them to appropriate WebSocket clients
 */
export class WebSocketEventBroadcaster extends EventEmitter {
  constructor(connectionManager) {
    super();
    this.connectionManager = connectionManager;
    this.eventListeners = new Map();
  }

  /**
   * Set up all AICLI service event listeners
   */
  setupEventListeners(aicliService) {
    // Stream data events
    this.addEventHandler(aicliService, 'streamData', (data) => {
      this.handleStreamDataEvent(data);
    });

    // System initialization events
    this.addEventHandler(aicliService, 'systemInit', (data) => {
      this.handleSystemInitEvent(data);
    });

    // Assistant message events
    this.addEventHandler(aicliService, 'assistantMessage', (data) => {
      this.handleAssistantMessageEvent(data);
    });

    // Tool usage events
    this.addEventHandler(aicliService, 'toolUse', (data) => {
      this.handleToolUseEvent(data);
    });

    // Tool result events
    this.addEventHandler(aicliService, 'toolResult', (data) => {
      this.handleToolResultEvent(data);
    });

    // Conversation result events
    this.addEventHandler(aicliService, 'conversationResult', (data) => {
      this.handleConversationResultEvent(data);
    });

    // Permission required events
    this.addEventHandler(aicliService, 'permissionRequired', (data) => {
      this.handlePermissionRequiredEvent(data);
    });

    // Process events
    this.addEventHandler(aicliService, 'processStart', (data) => {
      this.handleProcessStartEvent(data);
    });

    this.addEventHandler(aicliService, 'processExit', (data) => {
      this.handleProcessExitEvent(data);
    });

    this.addEventHandler(aicliService, 'processStderr', (data) => {
      this.handleProcessStderrEvent(data);
    });

    // Stream chunk events
    this.addEventHandler(aicliService, 'streamChunk', (data) => {
      this.handleStreamChunkEvent(data);
    });

    // Command progress events
    this.addEventHandler(aicliService, 'commandProgress', (data) => {
      this.handleCommandProgressEvent(data);
    });

    // Stream error events
    this.addEventHandler(aicliService, 'streamError', (data) => {
      this.handleStreamErrorEvent(data);
    });

    console.log(`📡 Set up ${this.eventListeners.size} AICLI service event listeners`);
  }

  /**
   * Add event handler and track it for cleanup
   */
  addEventHandler(aicliService, eventName, handler) {
    aicliService.on(eventName, handler);

    // Store reference for cleanup
    if (!this.eventListeners.has(aicliService)) {
      this.eventListeners.set(aicliService, new Map());
    }
    this.eventListeners.get(aicliService).set(eventName, handler);
  }

  /**
   * Handle streamData events
   */
  handleStreamDataEvent(data) {
    if (!this.validateEventData(data, 'streamData')) return;

    const message = {
      type: 'streamData',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        streamType: WebSocketUtilities.determineStreamType(data.data),
        content: WebSocketUtilities.formatStreamContent(data.data),
        isComplete: data.isComplete || false,
        originalMessage: data.originalMessage,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle systemInit events
   */
  handleSystemInitEvent(data) {
    if (!this.validateEventData(data, 'systemInit')) return;

    const message = {
      type: 'systemInit',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: data.data,
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle assistantMessage events
   */
  handleAssistantMessageEvent(data) {
    if (!this.validateEventData(data, 'assistantMessage')) return;

    console.log(`📢 Broadcasting assistantMessage for session ${data.sessionId}`);

    const message = {
      type: 'assistantMessage',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: data.data,
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle toolUse events
   */
  handleToolUseEvent(data) {
    if (!this.validateEventData(data, 'toolUse')) return;

    const message = {
      type: 'toolUse',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: data.data,
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle toolResult events
   */
  handleToolResultEvent(data) {
    if (!this.validateEventData(data, 'toolResult')) return;

    const message = {
      type: 'toolResult',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: data.data,
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle conversationResult events
   */
  handleConversationResultEvent(data) {
    if (!this.validateEventData(data, 'conversationResult')) return;

    const message = {
      type: 'conversationResult',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: data.data,
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle permissionRequired events
   */
  handlePermissionRequiredEvent(data) {
    if (!this.validateEventData(data, 'permissionRequired')) return;

    console.log(`🔐 Broadcasting permission request for session ${data.sessionId}`);

    const message = {
      type: 'permissionRequired',
      requestId: null,
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        prompt: data.prompt,
        options: data.options,
        default: data.default,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle processStart events
   */
  handleProcessStartEvent(data) {
    if (!this.validateEventData(data, 'processStart')) return;

    const message = {
      type: 'processStart',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        pid: data.pid,
        command: data.command,
        workingDirectory: data.workingDirectory,
        processType: data.type,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle processExit events
   */
  handleProcessExitEvent(data) {
    if (!this.validateEventData(data, 'processExit')) return;

    const message = {
      type: 'processExit',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        pid: data.pid,
        exitCode: data.code,
        stdout: data.stdout,
        stderr: data.stderr,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle processStderr events
   */
  handleProcessStderrEvent(data) {
    if (!this.validateEventData(data, 'processStderr')) return;

    const message = {
      type: 'processStderr',
      requestId: null,
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        pid: data.pid,
        stderr: data.data,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle streamChunk events
   */
  handleStreamChunkEvent(data) {
    if (!this.validateEventData(data, 'streamChunk')) return;

    // Validate the chunk before broadcasting
    if (!WebSocketUtilities.validateStreamChunk(data.chunk)) {
      console.log('🚫 Filtering invalid stream chunk from broadcast');
      return;
    }

    const message = {
      type: 'streamChunk',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        chunk: data.chunk,
        isFinal: data.chunk?.isFinal || false,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle commandProgress events
   */
  handleCommandProgressEvent(data) {
    if (!this.validateEventData(data, 'commandProgress')) return;

    const progressInfo = WebSocketUtilities.parseProgressFromOutput(data.data);

    const message = {
      type: 'commandProgress',
      requestId: data.requestId || null, // Use requestId from event
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        pid: data.pid,
        rawOutput: data.data,
        progress: progressInfo,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Handle streamError events
   */
  handleStreamErrorEvent(data) {
    if (!this.validateEventData(data, 'streamError')) return;

    console.error(`🚨 Broadcasting stream error for session ${data.sessionId}: ${data.error}`);

    const message = {
      type: 'streamError',
      requestId: null,
      timestamp: new Date().toISOString(),
      data: {
        sessionId: data.sessionId,
        error: data.error,
        details: data.details,
      },
    };

    this.broadcastToSession(data.sessionId, message);
  }

  /**
   * Broadcast message to all clients associated with a session
   */
  broadcastToSession(sessionId, message) {
    WebSocketUtilities.broadcastToSessionClients(
      sessionId,
      message,
      this.connectionManager.getAllClients()
    );

    // Emit event for monitoring
    this.emit('messageBroadcast', {
      sessionId,
      messageType: message.type,
      timestamp: message.timestamp,
      clientCount: this.connectionManager.getClientsBySession(sessionId).length,
    });
  }

  /**
   * Validate event data has required fields
   * In stateless architecture, null sessionId is acceptable for first messages
   */
  validateEventData(data, eventType) {
    if (!data) {
      console.warn(`⚠️ ${eventType} event missing data`);
      return false;
    }

    // In stateless architecture, null sessionId is expected for first messages
    // Only log debug info, not warnings
    if (!data.sessionId) {
      console.debug(`🔄 ${eventType} event with null sessionId (stateless mode)`);
    }

    return true;
  }

  /**
   * Broadcast system-wide message to all connected clients
   */
  broadcastToAll(message) {
    const clients = this.connectionManager.getAllClients();
    let successCount = 0;

    clients.forEach((client, clientId) => {
      if (WebSocketUtilities.sendMessage(clientId, message, clients)) {
        successCount++;
      }
    });

    console.log(`📡 System broadcast sent to ${successCount}/${clients.size} clients`);

    this.emit('systemBroadcast', {
      messageType: message.type,
      timestamp: message.timestamp,
      clientCount: successCount,
      totalClients: clients.size,
    });
  }

  /**
   * Broadcast to clients subscribed to specific events
   */
  broadcastToSubscribed(eventType, message) {
    const clients = this.connectionManager.getAllClients();
    let successCount = 0;

    clients.forEach((client, clientId) => {
      if (client.subscribedEvents && client.subscribedEvents.has(eventType)) {
        if (WebSocketUtilities.sendMessage(clientId, message, clients)) {
          successCount++;
        }
      }
    });

    console.log(`📡 Event broadcast (${eventType}) sent to ${successCount} subscribed clients`);

    this.emit('eventBroadcast', {
      eventType,
      messageType: message.type,
      timestamp: message.timestamp,
      subscriberCount: successCount,
    });
  }

  /**
   * Remove all event listeners from AICLI service
   */
  removeEventListeners(aicliService) {
    const serviceListeners = this.eventListeners.get(aicliService);
    if (serviceListeners) {
      serviceListeners.forEach((handler, eventName) => {
        aicliService.removeListener(eventName, handler);
      });
      this.eventListeners.delete(aicliService);
      console.log(`🧹 Removed ${serviceListeners.size} event listeners from AICLI service`);
    }
  }

  /**
   * Get broadcasting statistics
   */
  getStats() {
    const clients = this.connectionManager.getAllClients();
    let totalSubscriptions = 0;
    const eventSubscriptions = new Map();

    clients.forEach((client) => {
      if (client.subscribedEvents) {
        totalSubscriptions += client.subscribedEvents.size;
        client.subscribedEvents.forEach((event) => {
          eventSubscriptions.set(event, (eventSubscriptions.get(event) || 0) + 1);
        });
      }
    });

    return {
      connectedClients: clients.size,
      totalSubscriptions,
      eventSubscriptions: Object.fromEntries(eventSubscriptions),
      activeListeners: this.eventListeners.size,
    };
  }

  /**
   * Shutdown the event broadcaster
   */
  shutdown() {
    console.log('🔄 Shutting down WebSocket Event Broadcaster...');

    // Remove all event listeners
    this.eventListeners.forEach((serviceListeners, aicliService) => {
      this.removeEventListeners(aicliService);
    });

    this.removeAllListeners();
    console.log('✅ WebSocket Event Broadcaster shut down complete');
  }
}
