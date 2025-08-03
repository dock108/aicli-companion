import { WebSocketConnectionManager } from './websocket-connection-manager.js';
import { WebSocketMessageRouter } from './websocket-message-router.js';
import { WebSocketMessageHandlers } from './websocket-message-handlers.js';
import { WebSocketEventBroadcaster } from './websocket-event-broadcaster.js';
import { WebSocketUtilities } from './websocket-utilities.js';

/**
 * Main WebSocket service that orchestrates all WebSocket functionality
 * Maintains backward compatibility with the original setupWebSocket API
 */
export function setupWebSocket(wss, aicliService, authToken) {
  console.log('🚀 Setting up WebSocket service with modular architecture...');

  // Initialize all modules
  const connectionManager = new WebSocketConnectionManager();
  const messageRouter = new WebSocketMessageRouter();
  const eventBroadcaster = new WebSocketEventBroadcaster(connectionManager);

  // Make clients accessible globally for backward compatibility
  global.webSocketClients = connectionManager.getAllClients();

  // Register all message handlers with the router
  const handlers = WebSocketMessageHandlers.getAllHandlers();
  messageRouter.registerHandlers(handlers);

  // Set up AICLI service event listeners
  eventBroadcaster.setupEventListeners(aicliService);

  // Handle new WebSocket connections
  wss.on('connection', async (ws, request) => {
    // Handle connection through connection manager
    const clientId = await connectionManager.handleConnection(ws, request, authToken);

    if (!clientId) {
      // Connection was rejected (likely authentication failure)
      return;
    }

    // Set up message routing for this connection
    messageRouter.setupMessageListener(ws, clientId, aicliService, connectionManager);

    // Log successful connection setup
    console.log(`✅ WebSocket connection fully configured: ${clientId}`);
  });

  // Handle connection manager events
  connectionManager.on('clientConnected', ({ clientId, connectionInfo }) => {
    console.log(`🔗 Client connected: ${clientId} from ${connectionInfo.ip}`);

    // Emit to event broadcaster for any system-wide notifications
    eventBroadcaster.emit('clientConnected', { clientId, connectionInfo });
  });

  connectionManager.on('clientDisconnected', ({ clientId, sessionCount, closeCode, reason }) => {
    console.log(
      `🔌 Client disconnected: ${clientId} (${sessionCount} sessions, code: ${closeCode})`
    );

    // Clean up any remaining sessions for this client
    // Note: Sessions should continue running in background for reconnection
    console.log(`   Preserving ${sessionCount} AICLI sessions for background processing`);

    // Unregister device token for push notifications
    import('./push-notification.js')
      .then(({ pushNotificationService }) => {
        pushNotificationService.unregisterDevice(clientId);
      })
      .catch((error) => {
        console.warn('Failed to unregister device for push notifications:', error);
      });

    // Emit to event broadcaster
    eventBroadcaster.emit('clientDisconnected', { clientId, sessionCount, closeCode, reason });
  });

  // Handle message router events for monitoring
  messageRouter.on('messageReceived', ({ clientId, messageType, timestamp: _timestamp }) => {
    if (messageType !== 'ping') {
      // Reduce log noise
      console.log(`📨 Message received: ${messageType} from ${clientId}`);
    }
  });

  messageRouter.on('routingError', ({ clientId, error, messageType }) => {
    console.error(`❌ Routing error from ${clientId} (${messageType}): ${error}`);

    // Emit to event broadcaster for error tracking
    eventBroadcaster.emit('routingError', { clientId, error, messageType });
  });

  // Handle event broadcaster events for monitoring
  eventBroadcaster.on('messageBroadcast', ({ sessionId, messageType, clientCount }) => {
    if (messageType !== 'ping' && messageType !== 'commandProgress') {
      // Reduce log noise
      console.log(`📡 Broadcast ${messageType} to ${clientCount} clients (session: ${sessionId})`);
    }
  });

  // Start health monitoring
  connectionManager.startHealthMonitoring();

  // Handle WebSocket server close
  wss.on('close', async () => {
    console.log('🔄 WebSocket server closing, shutting down modules...');

    connectionManager.stopHealthMonitoring();
    connectionManager.shutdown();
    await messageRouter.shutdown();
    eventBroadcaster.shutdown();

    console.log('✅ WebSocket service shutdown complete');
  });

  // Expose service statistics and control methods
  const service = {
    // Statistics methods
    getStats() {
      return {
        connections: connectionManager.getStats(),
        routing: messageRouter.getStats(),
        broadcasting: eventBroadcaster.getStats(),
        timestamp: new Date().toISOString(),
      };
    },

    // Control methods
    broadcastToAll(message) {
      eventBroadcaster.broadcastToAll(message);
    },

    broadcastToSession(sessionId, message) {
      eventBroadcaster.broadcastToSession(sessionId, message);
    },

    broadcastToSubscribed(eventType, message) {
      eventBroadcaster.broadcastToSubscribed(eventType, message);
    },

    // Get clients for backward compatibility
    getClients() {
      return connectionManager.getAllClients();
    },

    // Shutdown method
    async shutdown() {
      connectionManager.stopHealthMonitoring();
      connectionManager.shutdown();
      await messageRouter.shutdown();
      eventBroadcaster.shutdown();
    },

    // Module access for advanced usage
    modules: {
      connectionManager,
      messageRouter,
      eventBroadcaster,
      utilities: WebSocketUtilities,
      handlers: WebSocketMessageHandlers,
    },
  };

  console.log(`🎉 WebSocket service setup complete!`);
  console.log(
    `   Registered message types: ${WebSocketMessageHandlers.getSupportedTypes().join(', ')}`
  );
  console.log(`   Health monitoring: enabled`);
  console.log(`   Event broadcasting: enabled`);
  console.log(`   Authentication: ${authToken ? 'enabled' : 'disabled'}`);

  return service;
}
