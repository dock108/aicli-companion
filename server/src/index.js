#!/usr/bin/env node

import express from 'express';
import { createServer } from 'http';
import { createServer as createHttpsServer } from 'https';
import { WebSocketServer } from 'ws';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

import { setupRoutes } from './routes/api-routes.js';
import { setupProjectRoutes } from './routes/projects.js';
import { setupAICLIStatusRoutes } from './routes/aicli-status.js';
import sessionRoutes from './routes/sessions.js';
import pushNotificationRoutes from './routes/push-notifications.js';
import chatRoutes from './routes/chat.js';
import devicesRoutes from './routes/devices.js';
import authRoutes from './routes/auth.js';
import { router as messagesRouter } from './routes/messages.js';
import filesRoutes from './routes/files.js';
import queueRoutes from './routes/queue.js';
import { errorHandler } from './middleware/error.js';
import { aicliService } from './services/aicli-instance.js';
import { ServerConfig } from './config/server-config.js';
import { MiddlewareConfig } from './config/middleware-config.js';
import { TLSConfig } from './config/tls-config.js';
import { ServerStartup } from './config/server-startup.js';
import { pushNotificationService } from './services/push-notification.js';
import { tunnelService } from './services/tunnel.js';
import { deviceRegistry } from './services/device-registry.js';
import { messageQueueManager } from './services/message-queue.js';
import { duplicateDetector } from './services/duplicate-detector.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

class AICLICompanionServer {
  constructor() {
    this.app = express();
    this.config = new ServerConfig();
    this.aicliService = aicliService;
    this.aicliService.safeRootDirectory = this.config.configPath; // Set project directory as safe root

    // Configure AICLI permission settings from environment or config
    if (process.env.AICLI_PERMISSION_MODE) {
      this.aicliService.setPermissionMode(process.env.AICLI_PERMISSION_MODE);
    }

    if (process.env.AICLI_ALLOWED_TOOLS) {
      const tools = process.env.AICLI_ALLOWED_TOOLS.split(',').map((t) => t.trim());
      this.aicliService.setAllowedTools(tools);
    }

    if (process.env.AICLI_DISALLOWED_TOOLS) {
      const tools = process.env.AICLI_DISALLOWED_TOOLS.split(',').map((t) => t.trim());
      this.aicliService.setDisallowedTools(tools);
    }

    if (process.env.AICLI_SKIP_PERMISSIONS === 'true') {
      this.aicliService.setSkipPermissions(true);
    }

    this.tlsConfig = new TLSConfig();

    // Will be set up during start()
    this.server = null;
    this.wss = null;

    // Set up auth token early if required
    if (this.config.authRequired) {
      this.authToken = ServerStartup.generateAuthToken(
        this.config.authToken,
        this.config.authRequired
      );
    } else {
      this.authToken = null;
    }

    this.setupBasicMiddleware();
    this.setupAuthMiddleware(); // Configure auth BEFORE routes
    this.setupRoutes();
    this.setupErrorHandling();
  }

  setupBasicMiddleware() {
    // Set up basic middleware (no auth yet)
    MiddlewareConfig.configure(this.app, this.config);
  }

  setupAuthMiddleware() {
    // Configure authentication middleware if token is set
    if (this.authToken) {
      MiddlewareConfig.configureAuth(this.app, this.authToken);
    }
  }

  setupRoutes() {
    // Store config in app.locals for routes to access
    this.app.locals.authRequired = this.config.authRequired;
    this.app.locals.authToken = this.authToken;
    this.app.locals.port = this.config.port;
    this.app.locals.enableTLS = this.config.enableTLS;

    // Health check (no auth required)
    this.app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        version: this.config.version,
        aicliCodeAvailable: this.aicliService.isAvailable(),
        timestamp: new Date().toISOString(),
      });
    });

    // Auth routes (QR code generation, etc.)
    this.app.use('/api/auth', authRoutes);

    // API routes
    setupRoutes(this.app, this.aicliService);
    setupProjectRoutes(this.app, this.aicliService);
    setupAICLIStatusRoutes(this.app, this.aicliService);
    this.app.use(pushNotificationRoutes);

    // New HTTP + APNS routes
    this.app.set('aicliService', this.aicliService); // Make available to route handlers
    this.app.use('/api/chat', chatRoutes);
    this.app.use('/api/devices', devicesRoutes);
    this.app.use('/api/sessions', sessionRoutes);
    this.app.use('/api/messages', messagesRouter);
    this.app.use('/api/files', filesRoutes);
    this.app.use('/api/queue', queueRoutes);

    // Static files (for web interface if needed)
    this.app.use('/static', express.static(join(__dirname, '../public')));

    // Default route
    this.app.get('/', (req, res) => {
      res.json({
        name: 'AICLI Companion Server',
        version: this.config.version,
        status: 'running',
        architecture: 'HTTP + APNS',
        endpoints: {
          health: '/health',
          api: '/api',
          auth: '/api/auth',
          security: '/api/security',
          chat: '/api/chat',
          devices: '/api/devices',
          projects: '/api/projects',
          files: '/api/files',
          qrCode: '/api/auth/setup',
        },
      });
    });
  }

  setupErrorHandling() {
    this.app.use(errorHandler);

    // Handle uncaught exceptions
    process.on('uncaughtException', (error) => {
      console.error('Uncaught Exception:', error);
      this.shutdown();
    });

    process.on('unhandledRejection', (reason, promise) => {
      console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    });

    // Graceful shutdown
    process.on('SIGTERM', () => this.shutdown());
    process.on('SIGINT', () => this.shutdown());
  }

  async start() {
    try {
      // Auth token and middleware already configured in constructor

      // Initialize push notification service with APNs HTTP/2 API
      pushNotificationService.initialize({
        keyPath: process.env.APNS_KEY_PATH || join(__dirname, '../keys/AuthKey_2Y226B9433.p8'),
        keyId: process.env.APNS_KEY_ID || '2Y226B9433',
        teamId: process.env.APNS_TEAM_ID || 'E3G5D247ZN',
        bundleId: process.env.APNS_BUNDLE_ID || 'com.aiclicompanion.ios',
        production: process.env.APNS_PRODUCTION === 'true', // Explicitly check APNS_PRODUCTION, default to false
      });

      // Set up TLS if enabled
      let tlsOptions = null;
      if (this.config.enableTLS) {
        try {
          tlsOptions = await this.tlsConfig.setupTLS();
        } catch (error) {
          console.warn(`⚠️  TLS setup failed: ${error.message}`);
          console.warn('   Falling back to HTTP');
          this.config.enableTLS = false;
        }
      }

      // Create HTTP or HTTPS server
      if (this.config.enableTLS && tlsOptions) {
        this.server = createHttpsServer(tlsOptions, this.app);
      } else {
        this.server = createServer(this.app);
      }

      // WebSocket server for real-time status updates
      await this.setupWebSocketServer();

      // DISABLED: Session persistence should be managed by clients, not the server
      // The server should start fresh on each restart without loading old sessions
      // console.log('🔄 Initializing session persistence...');
      // await this.aicliService.sessionManager.initializePersistence();

      // DISABLED: No need to reconcile if we're not persisting sessions
      // try {
      //   const reconcileStats = await this.aicliService.sessionManager.reconcileSessionState();
      //   console.log(`📊 Session reconciliation stats:`, reconcileStats);
      // } catch (error) {
      //   console.warn('⚠️ Session reconciliation failed:', error.message);
      // }

      // Verify AICLI Code is available
      const isAvailable = await ServerStartup.checkAICLIAvailability(this.aicliService);

      // Start server
      this.server.listen(this.config.port, this.config.host, async () => {
        const fingerprint = this.config.enableTLS
          ? this.tlsConfig.getCertificateFingerprint()
          : null;

        ServerStartup.displayStartupInfo(this.config, this.authToken, isAvailable, fingerprint);

        // Start tunnel if enabled
        if (this.config.enableTunnel) {
          console.log('🌐 Starting internet tunnel...');
          const publicUrl = await tunnelService.startTunnel(
            this.config.port,
            process.env.NGROK_AUTH_TOKEN
          );

          if (publicUrl) {
            console.log('');
            console.log('═══════════════════════════════════════════════════════');
            console.log('🌍 PUBLIC TUNNEL ACTIVE');
            console.log('═══════════════════════════════════════════════════════');
            console.log(`   Public URL: ${publicUrl}`);
            console.log(`   Auth Required: YES`);
            if (this.authToken) {
              // Mask auth token for security - show only first 8 chars
              const maskedToken = `${this.authToken.substring(0, 8)}...****`;
              console.log(`   Auth Token: ${maskedToken}`);
              console.log('');
              console.log('   iOS Connection URL:');
              console.log(`   ${publicUrl}?token=${maskedToken}`);
            } else {
              console.log('   ⚠️  WARNING: No auth token set!');
              console.log('   Generate one by restarting with AUTH_TOKEN=<your-token>');
            }
            console.log('═══════════════════════════════════════════════════════');
            console.log('');
          } else {
            console.log('❌ Failed to start tunnel - server still available locally');
          }
        }
      });

      // Setup service discovery
      ServerStartup.setupServiceDiscovery(
        this.config.port,
        this.config.enableTLS,
        this.config.enableBonjour
      );
    } catch (error) {
      console.error('Failed to start server:', error);
      process.exit(1);
    }
  }

  async setupWebSocketServer() {
    // Create WebSocket server on same HTTP/HTTPS server
    this.wss = new WebSocketServer({
      server: this.server,
      path: '/ws',
    });

    // Store in global for access from other modules
    global.wss = this.wss;

    // Handle WebSocket connections
    this.wss.on('connection', (ws, req) => {
      console.log('🔌 WebSocket client connected');

      // Verify auth token if required
      if (this.config.authRequired) {
        const url = new URL(req.url, `http://${req.headers.host}`);
        const token =
          url.searchParams.get('token') || req.headers.authorization?.replace('Bearer ', '');

        if (token !== this.config.authToken) {
          console.log('🚫 WebSocket connection rejected - invalid token');
          ws.close(1008, 'Unauthorized');
          return;
        }
      }

      // Initialize connection metadata
      ws.deviceId = null;
      ws.userId = null;
      ws.sessionIds = new Set();
      ws.isAlive = true;

      // Setup ping-pong for connection health
      ws.on('pong', () => {
        ws.isAlive = true;
      });

      ws.on('message', (data) => {
        try {
          const message = JSON.parse(data.toString());
          console.log('📥 WebSocket message received:', message.type);
          this.handleWebSocketMessage(ws, message);
        } catch (error) {
          console.error('❌ Invalid WebSocket message:', error.message);
          ws.send(JSON.stringify({
            type: 'error',
            error: 'Invalid message format'
          }));
        }
      });

      ws.on('close', () => {
        console.log('🔌 WebSocket client disconnected');
        this.handleWebSocketDisconnection(ws);
      });

      ws.on('error', (error) => {
        console.error('❌ WebSocket error:', error.message);
      });

      // Send welcome message
      ws.send(JSON.stringify({
        type: 'connected',
        message: 'WebSocket connection established'
      }));
    });

    // Heartbeat interval to detect disconnected clients
    this.wsHeartbeatInterval = setInterval(() => {
      this.wss.clients.forEach((ws) => {
        if (!ws.isAlive) {
          console.log('🔌 Terminating inactive WebSocket connection');
          return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
      });
    }, 30000); // Check every 30 seconds

    console.log('🔌 WebSocket server configured on /ws path');
    
    // Set up device registry event listeners
    this.setupDeviceRegistryListeners();
  }

  setupDeviceRegistryListeners() {
    // Listen for device events and broadcast to relevant clients
    deviceRegistry.on('deviceRegistered', (event) => {
      this.broadcastToUser(event.userId, {
        type: 'device-registered',
        device: event.device
      });
    });

    deviceRegistry.on('deviceUnregistered', (event) => {
      this.broadcastToUser(event.userId, {
        type: 'device-unregistered',
        deviceId: event.deviceId
      });
    });

    deviceRegistry.on('primaryElected', (event) => {
      this.broadcastToSession(event.sessionId, {
        type: 'primary-elected',
        sessionId: event.sessionId,
        deviceId: event.deviceId
      });
    });

    deviceRegistry.on('primaryTransferred', (event) => {
      this.broadcastToSession(event.sessionId, {
        type: 'primary-transferred',
        sessionId: event.sessionId,
        fromDeviceId: event.fromDeviceId,
        toDeviceId: event.toDeviceId
      });
    });

    deviceRegistry.on('primaryDeviceOffline', (event) => {
      this.broadcastToSession(event.sessionId, {
        type: 'primary-device-offline',
        sessionId: event.sessionId,
        deviceId: event.deviceId
      });
    });

    deviceRegistry.on('primaryDeviceTimeout', (event) => {
      this.broadcastToSession(event.sessionId, {
        type: 'primary-device-timeout',
        sessionId: event.sessionId,
        deviceId: event.deviceId
      });
    });

    // Listen for message queue events
    messageQueueManager.on('duplicate-message', (event) => {
      this.broadcastToSession(event.sessionId, {
        type: 'duplicate-message-detected',
        sessionId: event.sessionId,
        deviceId: event.deviceId,
        messageHash: event.messageHash
      });
    });
  }

  handleWebSocketMessage(ws, message) {
    try {
      switch (message.type) {
        case 'device-announce':
          this.handleDeviceAnnounce(ws, message);
          break;
        case 'device-heartbeat':
          this.handleDeviceHeartbeat(ws, message);
          break;
        case 'session-join':
          this.handleSessionJoin(ws, message);
          break;
        case 'session-leave':
          this.handleSessionLeave(ws, message);
          break;
        case 'primary-election-request':
          this.handlePrimaryElectionRequest(ws, message);
          break;
        case 'primary-transfer-request':
          this.handlePrimaryTransferRequest(ws, message);
          break;
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong', timestamp: Date.now() }));
          break;
        default:
          console.warn('🤔 Unknown WebSocket message type:', message.type);
          ws.send(JSON.stringify({
            type: 'error',
            error: `Unknown message type: ${message.type}`
          }));
      }
    } catch (error) {
      console.error('❌ Error handling WebSocket message:', error.message);
      ws.send(JSON.stringify({
        type: 'error',
        error: 'Failed to process message'
      }));
    }
  }

  handleDeviceAnnounce(ws, message) {
    const { deviceId, userId, deviceInfo = {} } = message;
    
    if (!deviceId || !userId) {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'deviceId and userId are required'
      }));
      return;
    }

    // Register device with device registry
    const result = deviceRegistry.registerDevice(userId, deviceId, deviceInfo);
    
    if (result.success) {
      // Store device info in WebSocket connection
      ws.deviceId = deviceId;
      ws.userId = userId;
      
      // Update device heartbeat
      deviceRegistry.updateLastSeen(deviceId);
      
      ws.send(JSON.stringify({
        type: 'device-announced',
        deviceId,
        registeredAt: result.device.registeredAt
      }));

      console.log(`📱 Device announced: ${deviceId} for user ${userId}`);
    } else {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'Failed to register device'
      }));
    }
  }

  handleDeviceHeartbeat(ws, message) {
    if (ws.deviceId) {
      deviceRegistry.updateLastSeen(ws.deviceId);
      ws.send(JSON.stringify({
        type: 'heartbeat-ack',
        timestamp: Date.now()
      }));
    } else {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'Device not announced'
      }));
    }
  }

  handleSessionJoin(ws, message) {
    const { sessionId } = message;
    
    if (!sessionId || !ws.deviceId) {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'sessionId required and device must be announced'
      }));
      return;
    }

    // Add session to device's session set
    ws.sessionIds.add(sessionId);
    
    // Get current active devices for this user
    const activeDevices = deviceRegistry.getActiveDevices(ws.userId);
    
    // Check if there's already a primary device for this session
    const primaryDeviceId = deviceRegistry.getPrimaryDevice(sessionId);
    
    ws.send(JSON.stringify({
      type: 'session-joined',
      sessionId,
      activeDevices,
      primaryDeviceId,
      isPrimary: primaryDeviceId === ws.deviceId
    }));

    console.log(`🎯 Device ${ws.deviceId} joined session ${sessionId}`);
  }

  handleSessionLeave(ws, message) {
    const { sessionId } = message;
    
    if (!sessionId) {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'sessionId is required'
      }));
      return;
    }

    // Remove session from device's session set
    ws.sessionIds.delete(sessionId);
    
    ws.send(JSON.stringify({
      type: 'session-left',
      sessionId
    }));

    console.log(`🎯 Device ${ws.deviceId} left session ${sessionId}`);
  }

  handlePrimaryElectionRequest(ws, message) {
    const { sessionId } = message;
    
    if (!sessionId || !ws.deviceId || !ws.userId) {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'sessionId required and device must be announced'
      }));
      return;
    }

    // Attempt to elect this device as primary
    const result = deviceRegistry.electPrimary(ws.userId, sessionId, ws.deviceId);
    
    ws.send(JSON.stringify({
      type: 'primary-election-result',
      sessionId,
      success: result.success,
      isPrimary: result.isPrimary,
      primaryDeviceId: result.primaryDeviceId,
      reason: result.reason
    }));

    if (result.success && result.isPrimary) {
      console.log(`👑 Device ${ws.deviceId} elected as primary for session ${sessionId}`);
    }
  }

  handlePrimaryTransferRequest(ws, message) {
    const { sessionId, toDeviceId } = message;
    
    if (!sessionId || !toDeviceId || !ws.deviceId) {
      ws.send(JSON.stringify({
        type: 'error',
        error: 'sessionId, toDeviceId required and device must be announced'
      }));
      return;
    }

    // Attempt to transfer primary status
    const result = deviceRegistry.transferPrimary(sessionId, ws.deviceId, toDeviceId);
    
    ws.send(JSON.stringify({
      type: 'primary-transfer-result',
      sessionId,
      success: result.success,
      newPrimaryDeviceId: result.newPrimaryDeviceId,
      reason: result.reason
    }));

    if (result.success) {
      console.log(`🔄 Primary transferred from ${ws.deviceId} to ${toDeviceId} for session ${sessionId}`);
    }
  }

  handleWebSocketDisconnection(ws) {
    if (ws.deviceId) {
      // Unregister device from registry
      deviceRegistry.unregisterDevice(ws.deviceId);
      console.log(`📱 Device ${ws.deviceId} unregistered due to disconnection`);
    }
  }

  // Broadcast message to all WebSocket connections for a specific user
  broadcastToUser(userId, message) {
    this.wss.clients.forEach((ws) => {
      if (ws.userId === userId && ws.readyState === ws.OPEN) {
        try {
          ws.send(JSON.stringify(message));
        } catch (error) {
          console.error('❌ Failed to send message to user:', error.message);
        }
      }
    });
  }

  // Broadcast message to all WebSocket connections for a specific session
  broadcastToSession(sessionId, message) {
    this.wss.clients.forEach((ws) => {
      if (ws.sessionIds && ws.sessionIds.has(sessionId) && ws.readyState === ws.OPEN) {
        try {
          ws.send(JSON.stringify(message));
        } catch (error) {
          console.error('❌ Failed to send message to session:', error.message);
        }
      }
    });
  }

  // Broadcast message to all connected WebSocket clients
  broadcastToAll(message) {
    this.wss.clients.forEach((ws) => {
      if (ws.readyState === ws.OPEN) {
        try {
          ws.send(JSON.stringify(message));
        } catch (error) {
          console.error('❌ Failed to broadcast message:', error.message);
        }
      }
    });
  }

  async shutdown() {
    console.log('🔄 Shutting down server...');

    // Shutdown WebSocket server
    if (this.wsHeartbeatInterval) {
      clearInterval(this.wsHeartbeatInterval);
    }
    if (this.wss) {
      this.wss.clients.forEach((ws) => {
        ws.close(1000, 'Server shutting down');
      });
      this.wss.close();
    }

    // Shutdown tunnel if active
    if (tunnelService.isTunnelActive()) {
      await tunnelService.stopTunnel();
    }

    // Shutdown AICLI service
    this.aicliService.shutdown();

    // Shutdown push notification service
    pushNotificationService.shutdown();

    this.server.close(() => {
      console.log('✅ Server shut down successfully');
      process.exit(0);
    });

    // Force shutdown after 10 seconds
    setTimeout(() => {
      console.log('⚠️  Force shutting down...');
      process.exit(1);
    }, 10000);
  }
}

// Start server if this file is run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const server = new AICLICompanionServer();
  server.start().catch(console.error);
}

export { AICLICompanionServer };
