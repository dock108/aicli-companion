import { EventEmitter } from 'events';
import { WebSocketUtilities } from './websocket-utilities.js';

/**
 * Routes incoming WebSocket messages to appropriate handlers
 */
export class WebSocketMessageRouter extends EventEmitter {
  constructor() {
    super();
    this.handlers = new Map();
    this.messageQueue = [];
  }

  /**
   * Register a message handler for a specific message type
   */
  registerHandler(messageType, handler) {
    if (typeof handler !== 'function') {
      throw new Error(`Handler for message type '${messageType}' must be a function`);
    }

    this.handlers.set(messageType, handler);
    console.log(`📋 Registered handler for message type: ${messageType}`);
  }

  /**
   * Register multiple handlers at once
   */
  registerHandlers(handlerMap) {
    Object.entries(handlerMap).forEach(([messageType, handler]) => {
      this.registerHandler(messageType, handler);
    });
  }

  /**
   * Unregister a message handler
   */
  unregisterHandler(messageType) {
    const removed = this.handlers.delete(messageType);
    console.log(`📋 ${removed ? 'Removed' : 'Failed to remove'} handler for message type: ${messageType}`);
    return removed;
  }

  /**
   * Get all registered message types
   */
  getRegisteredTypes() {
    return Array.from(this.handlers.keys());
  }

  /**
   * Route incoming WebSocket message to appropriate handler
   */
  async routeMessage(clientId, rawData, aicliService, connectionManager) {
    let message;
    let requestId = null;

    try {
      // Parse the message
      message = WebSocketUtilities.safeParse(rawData.toString());
      if (!message) {
        throw new Error('Failed to parse message as JSON');
      }

      requestId = message.requestId;

      // Validate message structure
      const validation = WebSocketUtilities.validateMessage(message);
      if (!validation.valid) {
        throw new Error(validation.error);
      }

      // Update client activity
      connectionManager.updateClientActivity(clientId);

      // Log incoming message (excluding ping for noise reduction)
      if (message.type !== 'ping') {
        console.log(`📨 Routing message: ${message.type} from client ${clientId}`);
      }

      // Emit routing event for monitoring
      this.emit('messageReceived', {
        clientId,
        messageType: message.type,
        requestId: message.requestId,
        timestamp: new Date().toISOString(),
      });

      // Route to appropriate handler
      await this.dispatchMessage(clientId, message, aicliService, connectionManager);

    } catch (error) {
      console.error(`❌ Error routing message from client ${clientId}:`, error);

      // Send error response to client
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'ROUTING_ERROR',
        error.message,
        connectionManager.getAllClients(),
        {
          originalMessage: message ? message.type : 'unknown',
          timestamp: new Date().toISOString(),
        }
      );

      // Emit error event
      this.emit('routingError', {
        clientId,
        error: error.message,
        requestId,
        originalMessage: message,
        timestamp: new Date().toISOString(),
      });
    }
  }

  /**
   * Dispatch message to registered handler
   */
  async dispatchMessage(clientId, message, aicliService, connectionManager) {
    const { type, requestId, data } = message;
    const clients = connectionManager.getAllClients();

    // Check if handler exists
    const handler = this.handlers.get(type);
    if (!handler) {
      throw new Error(`No handler registered for message type: ${type}`);
    }

    try {
      // Call the handler with consistent parameters
      await handler(clientId, requestId, data, aicliService, clients, connectionManager);

      // Emit successful dispatch event
      this.emit('messageDispatched', {
        clientId,
        messageType: type,
        requestId,
        timestamp: new Date().toISOString(),
      });

    } catch (handlerError) {
      console.error(`❌ Handler error for message type '${type}':`, handlerError);

      // Send handler-specific error to client
      WebSocketUtilities.sendErrorMessage(
        clientId,
        requestId,
        'HANDLER_ERROR',
        `Handler failed: ${handlerError.message}`,
        clients,
        {
          messageType: type,
          timestamp: new Date().toISOString(),
        }
      );

      // Emit handler error event
      this.emit('handlerError', {
        clientId,
        messageType: type,
        requestId,
        error: handlerError.message,
        timestamp: new Date().toISOString(),
      });

      // Re-throw to be caught by parent error handler
      throw handlerError;
    }
  }

  /**
   * Handle WebSocket connection message events
   */
  setupMessageListener(ws, clientId, aicliService, connectionManager) {
    ws.on('message', async (data) => {
      try {
        await this.routeMessage(clientId, data, aicliService, connectionManager);
      } catch (error) {
        // Error is already handled in routeMessage, just log here
        console.error(`Message routing failed for client ${clientId}:`, error.message);
      }
    });
  }

  /**
   * Create a middleware function that can be used to intercept messages
   */
  createMiddleware(middlewareFunction) {
    const originalDispatch = this.dispatchMessage.bind(this);
    
    this.dispatchMessage = async (clientId, message, aicliService, connectionManager) => {
      try {
        // Run middleware
        const shouldContinue = await middlewareFunction(clientId, message, aicliService, connectionManager);
        
        if (shouldContinue !== false) {
          // Continue with normal dispatch
          return await originalDispatch(clientId, message, aicliService, connectionManager);
        } else {
          console.log(`🚫 Message intercepted by middleware: ${message.type} from client ${clientId}`);
        }
      } catch (middlewareError) {
        console.error(`❌ Middleware error:`, middlewareError);
        // Continue with normal dispatch even if middleware fails
        return await originalDispatch(clientId, message, aicliService, connectionManager);
      }
    };
  }

  /**
   * Queue messages for batch processing (useful for high-volume scenarios)
   */
  enableMessageQueueing(options = {}) {
    const batchSize = options.batchSize || 10;
    const flushInterval = options.flushInterval || 100; // ms
    
    this.messageQueue = [];
    
    const originalRouteMessage = this.routeMessage.bind(this);
    
    this.routeMessage = async (clientId, rawData, aicliService, connectionManager) => {
      this.messageQueue.push({ clientId, rawData, aicliService, connectionManager });
      
      if (this.messageQueue.length >= batchSize) {
        await this.flushMessageQueue();
      }
    };

    // Flush queue periodically
    this.queueFlushInterval = setInterval(async () => {
      if (this.messageQueue.length > 0) {
        await this.flushMessageQueue();
      }
    }, flushInterval);
  }

  /**
   * Flush queued messages
   */
  async flushMessageQueue() {
    const batch = this.messageQueue.splice(0);
    console.log(`📦 Processing message batch: ${batch.length} messages`);

    // Process messages in parallel with concurrency limit
    const concurrency = 5;
    for (let i = 0; i < batch.length; i += concurrency) {
      const chunk = batch.slice(i, i + concurrency);
      await Promise.allSettled(
        chunk.map(({ clientId, rawData, aicliService, connectionManager }) =>
          this.routeMessage(clientId, rawData, aicliService, connectionManager)
        )
      );
    }
  }

  /**
   * Disable message queueing
   */
  disableMessageQueueing() {
    if (this.queueFlushInterval) {
      clearInterval(this.queueFlushInterval);
      this.queueFlushInterval = null;
    }
    
    // Flush any remaining messages
    if (this.messageQueue.length > 0) {
      this.flushMessageQueue();
    }
  }

  /**
   * Get routing statistics
   */
  getStats() {
    return {
      registeredHandlers: this.handlers.size,
      handlerTypes: this.getRegisteredTypes(),
      queueEnabled: !!this.queueFlushInterval,
      queueSize: this.messageQueue ? this.messageQueue.length : 0,
    };
  }

  /**
   * Shutdown the router
   */
  shutdown() {
    console.log('🔄 Shutting down WebSocket Message Router...');
    
    this.disableMessageQueueing();
    this.handlers.clear();
    this.removeAllListeners();
    
    console.log('✅ WebSocket Message Router shut down complete');
  }
}