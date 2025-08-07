import { v4 as uuidv4 } from 'uuid';
import { EventEmitter } from 'events';
import { WebSocketUtilities } from './websocket-utilities.js';
import { ConnectionStateManager } from './connection-state-manager.js';
import { getTelemetryService } from './telemetry.js';
import { WEBSOCKET_EVENTS, SERVER_VERSION, DEFAULT_CONFIG } from '../constants/index.js';

/**
 * Manages WebSocket client connections, authentication, and health monitoring
 */
export class WebSocketConnectionManager extends EventEmitter {
  constructor(options = {}) {
    super();
    this.clients = new Map();
    this.connectionHistory = new Map(); // Track recent connections for reconnection
    this.pingInterval = null;
    // Allow dependency injection for testing
    this.generateId = options.generateId || uuidv4;
    this.healthCheckInterval = options.healthCheckInterval || 15000; // Default 15 seconds
    this.reconnectionWindow = options.reconnectionWindow || 30000; // 30 seconds

    // TODO: [QUESTION] Optimal reconnection window?
    // 30s is arbitrary - need to test with real app behavior
    // Consider: app background time, network switches, etc.

    // Initialize connection state manager
    this.connectionStateManager = options.connectionStateManager || new ConnectionStateManager();

    // Start connection history cleanup (disabled in test environment)
    if (process.env.NODE_ENV !== 'test') {
      this.startConnectionHistoryCleanup();
    }
  }

  /**
   * Handle new WebSocket connection
   */
  async handleConnection(ws, request, authToken) {
    const clientId = this.generateId();
    const clientInfo = this.extractClientInfo(request);

    // Check for recent connection from same client
    const recentConnection = await this.findRecentConnection(clientInfo);
    if (recentConnection) {
      console.log(`♻️ Client reconnection detected: ${recentConnection.clientId} → ${clientId}`);
      console.log(`   Previous sessions: ${Array.from(recentConnection.sessionIds).join(', ')}`);

      // TODO: [QUESTION] Define reconnection criteria
      // Currently using deviceId from headers, but may need:
      // - IP address consideration?
      // - Auth token validation?
      // - User agent matching?
    }

    console.log(
      `WebSocket client connected: ${clientId} from ${clientInfo.ip} (${clientInfo.family})`
    );
    console.log(`   User-Agent: ${clientInfo.userAgent}`);
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

    // Store client info (stateless - no session tracking)
    const client = {
      ws,
      // Server is stateless - no session tracking
      isAlive: true,
      subscribedEvents: new Set(),
      connectedAt: new Date(),
      lastActivity: new Date(),
      clientInfo,
      isReconnection: !!recentConnection,
      previousClientId: recentConnection?.clientId,
    };

    this.clients.set(clientId, client);

    // Store in connection history for future reconnection detection
    this.addToConnectionHistory(clientId, clientInfo, new Set());

    // Record telemetry
    getTelemetryService().recordConnection(clientId, clientInfo);
    if (recentConnection) {
      getTelemetryService().recordReconnection(clientId, recentConnection.clientId);
    }

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

    // Send minimal welcome message for iOS connection detection
    // iOS app requires this to confirm connection is established
    this.sendMinimalWelcomeMessage(clientId);

    // Emit connection event
    this.emit('clientConnected', {
      clientId,
      client,
      connectionInfo: {
        ip: clientInfo.ip,
        family: clientInfo.family,
        userAgent: clientInfo.userAgent,
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

    // Server is stateless - no session tracking
    const sessionCount = 0;
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

    // Record telemetry
    getTelemetryService().recordDisconnection(clientId);

    console.log(`   Remaining clients: ${this.clients.size}`);
  }


  /**
   * Send minimal welcome message for iOS connection detection
   * iOS app requires this to know connection is established
   */
  sendMinimalWelcomeMessage(clientId) {
    const welcomeMessage = {
      type: WEBSOCKET_EVENTS.WELCOME,
      timestamp: new Date().toISOString(),
      data: {
        clientId,
        serverVersion: SERVER_VERSION,
        capabilities: [],  // Empty array - server is stateless
        // No maxSessions - not needed in stateless architecture
      },
    };

    const success = WebSocketUtilities.sendMessage(clientId, welcomeMessage, this.clients);
    if (success) {
      console.log(`✅ Minimal welcome message sent to client ${clientId}`);
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
   * Add session to client - DISABLED
   * Server is stateless and doesn't track sessions
   */
  addSessionToClient(clientId, sessionId) {
    // Server is stateless - no session tracking
    console.log(`📎 Session tracking disabled (stateless server): ${sessionId}`);
  }

  /**
   * Remove session from client - DISABLED
   * Server is stateless and doesn't track sessions
   */
  removeSessionFromClient(clientId, sessionId) {
    // Server is stateless - no session tracking
    console.log(`📎 Session tracking disabled (stateless server): ${sessionId}`);
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
   * Get clients by session ID - DISABLED
   * Server is stateless and doesn't track sessions
   */
  getClientsBySession(sessionId) {
    // Server is stateless - no session tracking
    return [];
  }

  /**
   * Extract client info from request
   */
  extractClientInfo(request) {
    const userAgent = request.headers['user-agent'] || 'unknown';
    const ip = request.socket.remoteAddress;
    const family = request.socket.remoteFamily;

    // Try to extract device ID from headers (iOS should send this)
    const deviceId = request.headers['x-device-id'] || null;

    return {
      userAgent,
      ip,
      family,
      deviceId,
      // Create a fingerprint for reconnection matching
      fingerprint: this.createClientFingerprint({ userAgent, deviceId }),
    };
  }

  /**
   * Create a fingerprint for client identification
   */
  createClientFingerprint(info) {
    // TODO: [QUESTION] What makes a good fingerprint?
    // Currently using deviceId if available, otherwise user agent
    // May need to consider IP for better accuracy?

    if (info.deviceId) {
      return `device:${info.deviceId}`;
    }

    // Fallback to user agent hash
    return `ua:${Buffer.from(info.userAgent).toString('base64').substring(0, 20)}`;
  }

  /**
   * Find recent connection from same client
   */
  async findRecentConnection(clientInfo) {
    const now = Date.now();

    // First check in-memory history
    for (const [, data] of this.connectionHistory) {
      // Check if within reconnection window
      if (now - data.lastSeen > this.reconnectionWindow) {
        continue;
      }

      // Match by fingerprint
      if (data.fingerprint === clientInfo.fingerprint) {
        return {
          clientId: data.clientId,
          sessionIds: data.sessionIds,
          lastSeen: data.lastSeen,
        };
      }
    }

    // If not found in memory, check persistent state
    const persistedState = await this.connectionStateManager.getConnectionState(
      clientInfo.fingerprint
    );

    if (persistedState && persistedState.sessionIds) {
      return {
        clientId: null, // No recent clientId from persistent state
        sessionIds: persistedState.sessionIds,
        lastSeen: persistedState.lastUpdated,
      };
    }

    return null;
  }

  /**
   * Add to connection history
   */
  async addToConnectionHistory(clientId, clientInfo, sessionIds) {
    const key = `${clientInfo.fingerprint}:${clientId}`;

    this.connectionHistory.set(key, {
      clientId,
      fingerprint: clientInfo.fingerprint,
      sessionIds: new Set(sessionIds),
      lastSeen: Date.now(),
      clientInfo,
    });

    // Also save to persistent state manager
    if (sessionIds.size > 0) {
      await this.connectionStateManager.updateConnectionSessions(
        clientInfo.fingerprint,
        Array.from(sessionIds)
      );
    }
  }

  /**
   * Start connection history cleanup
   */
  startConnectionHistoryCleanup() {
    // Clean up old entries every minute
    this.historyCleanupInterval = setInterval(() => {
      const now = Date.now();
      const expired = [];

      for (const [key, data] of this.connectionHistory) {
        if (now - data.lastSeen > this.reconnectionWindow * 2) {
          expired.push(key);
        }
      }

      expired.forEach((key) => this.connectionHistory.delete(key));

      if (expired.length > 0) {
        console.log(`🧹 Cleaned ${expired.length} expired connection history entries`);
      }
    }, 60000); // Every minute
  }

  /**
   * Shutdown connection manager
   */
  shutdown() {
    console.log('🔄 Shutting down WebSocket Connection Manager...');

    this.stopHealthMonitoring();

    // Stop history cleanup
    if (this.historyCleanupInterval) {
      clearInterval(this.historyCleanupInterval);
    }

    // Shutdown connection state manager
    if (this.connectionStateManager) {
      this.connectionStateManager.shutdown();
    }

    // Close all connections
    this.clients.forEach((client, clientId) => {
      try {
        client.ws.close(1001, 'Server shutting down');
      } catch (error) {
        console.warn(`Failed to close connection ${clientId}:`, error.message);
      }
    });

    this.clients.clear();
    this.connectionHistory.clear();
    console.log('✅ WebSocket Connection Manager shut down complete');
  }

  /**
   * Get connection statistics
   */
  getStats() {
    let totalSubscriptions = 0;

    this.clients.forEach((client) => {
      totalSubscriptions += client.subscribedEvents.size;
    });

    return {
      connectedClients: this.clients.size,
      totalSessions: 0, // Server is stateless
      totalSubscriptions,
      healthMonitoring: !!this.pingInterval,
    };
  }
}
