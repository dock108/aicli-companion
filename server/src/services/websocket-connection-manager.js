import { v4 as uuidv4 } from 'uuid';
import { EventEmitter } from 'events';
import { WebSocketUtilities } from './websocket-utilities.js';
import { WEBSOCKET_EVENTS, SERVER_VERSION, DEFAULT_CONFIG } from '../constants/index.js';

/**
 * Manages WebSocket client connections, authentication, and health monitoring
 */
export class WebSocketConnectionManager extends EventEmitter {
  constructor(options = {}) {
    super();
    this.clients = new Map();
    this.pingInterval = null;
    // Allow dependency injection for testing
    this.generateId = options.generateId || uuidv4;
    this.healthCheckInterval = options.healthCheckInterval || 15000; // Default 15 seconds
  }

  /**
   * Handle new WebSocket connection
   */
  handleConnection(ws, request, authToken) {
    const clientId = this.generateId();
    const clientIP = request.socket.remoteAddress;
    const clientFamily = request.socket.remoteFamily;
    const userAgent = request.headers['user-agent'] || 'unknown';

    console.log(`WebSocket client connected: ${clientId} from ${clientIP} (${clientFamily})`);
    console.log(`   User-Agent: ${userAgent}`);
    console.log(`   Total clients: ${this.clients.size + 1}`);

    // Authentication check
    if (authToken) {
      const url = new URL(request.url, `http://${request.headers.host}`);
      const token =
        url.searchParams.get('token') || request.headers.authorization?.replace('Bearer ', '');

      if (!token || token !== authToken) {
        ws.close(1008, 'Authentication required');
        return null;
      }
    }

    // Store client info
    const client = {
      ws,
      sessionIds: new Set(),
      isAlive: true,
      subscribedEvents: new Set(),
      connectedAt: new Date(),
      lastActivity: new Date(),
    };

    this.clients.set(clientId, client);

    // Set up ping/pong for connection health
    ws.isAlive = true;
    ws.on('pong', () => {
      ws.isAlive = true;
      const clientData = this.clients.get(clientId);
      if (clientData) {
        clientData.lastActivity = new Date();
      }
    });

    // Handle connection close
    ws.on('close', (code, reason) => {
      this.handleDisconnection(clientId, code, reason);
    });

    // Handle connection errors
    ws.on('error', (error) => {
      console.error(`WebSocket error for client ${clientId}:`, error);
      this.handleDisconnection(clientId, 1011, 'Internal error');
    });

    // Send welcome message
    this.sendWelcomeMessage(clientId);

    // Emit connection event
    this.emit('clientConnected', {
      clientId,
      client,
      connectionInfo: {
        ip: clientIP,
        family: clientFamily,
        userAgent,
      },
    });

    return clientId;
  }

  /**
   * Handle client disconnection
   */
  handleDisconnection(clientId, code, reason) {
    const client = this.clients.get(clientId);
    if (!client) return;

    const sessionCount = client.sessionIds.size;
    const reasonStr = reason ? reason.toString() : 'No reason provided';

    console.log(`WebSocket client disconnected: ${clientId}`);
    console.log(`   Close code: ${code}`);
    console.log(`   Reason: ${reasonStr}`);
    console.log(`   Sessions associated: ${sessionCount}`);
    console.log(`   Connection duration: ${Date.now() - client.connectedAt.getTime()}ms`);

    // Emit disconnection event before cleanup
    this.emit('clientDisconnected', {
      clientId,
      client,
      closeCode: code,
      reason: reasonStr,
      sessionCount,
    });

    // Clean up client data
    this.clients.delete(clientId);

    console.log(`   Remaining clients: ${this.clients.size}`);
  }

  /**
   * Send welcome message to newly connected client
   */
  sendWelcomeMessage(clientId) {
    // Get Claude Code version if available
    let claudeCodeVersion = null;
    try {
      // This will be filled in by the actual version check if needed
      // For now, we'll leave it as null and the client can handle that
      claudeCodeVersion = null;
    } catch (error) {
      // Ignore version check errors
    }

    const welcomeMessage = {
      type: WEBSOCKET_EVENTS.WELCOME,
      timestamp: new Date().toISOString(),
      data: {
        clientId: clientId,
        serverVersion: SERVER_VERSION,
        claudeCodeVersion,
        capabilities: [
          'chat',
          'streaming',
          'permissions',
          'file-operations',
          'session-management'
        ],
        maxSessions: DEFAULT_CONFIG.MAX_SESSIONS
      }
    };

    const success = WebSocketUtilities.sendMessage(clientId, welcomeMessage, this.clients);
    if (success) {
      console.log(`✅ Welcome message sent to client ${clientId}`);
    } else {
      console.warn(`⚠️ Failed to send welcome message to client ${clientId}`);
    }
  }

  /**
   * Start health monitoring for all connections
   */
  startHealthMonitoring() {
    if (this.pingInterval) {
      return; // Already running
    }

    this.pingInterval = setInterval(() => {
      const deadClients = [];

      this.clients.forEach((client, clientId) => {
        if (client.ws.isAlive === false) {
          console.log(`📡 Terminating dead WebSocket connection: ${clientId}`);
          deadClients.push(clientId);
          client.ws.terminate();
          return;
        }

        // Mark as potentially dead and send ping
        client.ws.isAlive = false;

        try {
          client.ws.ping();
        } catch (error) {
          console.error(`Failed to ping client ${clientId}:`, error);
          deadClients.push(clientId);
          client.ws.terminate();
        }
      });

      // Clean up dead clients
      deadClients.forEach((clientId) => {
        this.handleDisconnection(clientId, 1006, 'Connection lost - no pong received');
      });

      if (this.clients.size > 0) {
        console.log(`📡 Pinged ${this.clients.size} WebSocket clients`);
      }
    }, this.healthCheckInterval);
  }

  /**
   * Stop health monitoring
   */
  stopHealthMonitoring() {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
  }

  /**
   * Get client by ID
   */
  getClient(clientId) {
    return this.clients.get(clientId);
  }

  /**
   * Get all clients
   */
  getAllClients() {
    return this.clients;
  }

  /**
   * Add session to client
   */
  addSessionToClient(clientId, sessionId) {
    const client = this.clients.get(clientId);
    if (client) {
      client.sessionIds.add(sessionId);
      console.log(
        `📎 Added session ${sessionId} to client ${clientId} (total: ${client.sessionIds.size})`
      );
    }
  }

  /**
   * Remove session from client
   */
  removeSessionFromClient(clientId, sessionId) {
    const client = this.clients.get(clientId);
    if (client) {
      client.sessionIds.delete(sessionId);
      console.log(
        `📎 Removed session ${sessionId} from client ${clientId} (remaining: ${client.sessionIds.size})`
      );
    }
  }

  /**
   * Subscribe client to events
   */
  subscribeClient(clientId, events) {
    const client = this.clients.get(clientId);
    if (client) {
      if (Array.isArray(events)) {
        events.forEach((event) => client.subscribedEvents.add(event));
      } else {
        client.subscribedEvents.add(events);
      }
      console.log(
        `📡 Client ${clientId} subscribed to events: ${Array.from(client.subscribedEvents).join(', ')}`
      );
    }
  }

  /**
   * Update client last activity
   */
  updateClientActivity(clientId) {
    const client = this.clients.get(clientId);
    if (client) {
      client.lastActivity = new Date();
    }
  }

  /**
   * Get clients by session ID
   */
  getClientsBySession(sessionId) {
    const sessionClients = [];
    this.clients.forEach((client, clientId) => {
      if (client.sessionIds.has(sessionId)) {
        sessionClients.push({ clientId, client });
      }
    });
    return sessionClients;
  }

  /**
   * Shutdown connection manager
   */
  shutdown() {
    console.log('🔄 Shutting down WebSocket Connection Manager...');

    this.stopHealthMonitoring();

    // Close all connections
    this.clients.forEach((client, clientId) => {
      try {
        client.ws.close(1001, 'Server shutting down');
      } catch (error) {
        console.warn(`Failed to close connection ${clientId}:`, error.message);
      }
    });

    this.clients.clear();
    console.log('✅ WebSocket Connection Manager shut down complete');
  }

  /**
   * Get connection statistics
   */
  getStats() {
    let totalSessions = 0;
    let totalSubscriptions = 0;

    this.clients.forEach((client) => {
      totalSessions += client.sessionIds.size;
      totalSubscriptions += client.subscribedEvents.size;
    });

    return {
      connectedClients: this.clients.size,
      totalSessions,
      totalSubscriptions,
      healthMonitoring: !!this.pingInterval,
    };
  }
}
