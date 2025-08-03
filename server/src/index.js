#!/usr/bin/env node

import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import { createServer as createHttpsServer } from 'https';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

import { setupRoutes } from './routes/index.js';
import { setupProjectRoutes } from './routes/projects.js';
import { setupAICLIStatusRoutes } from './routes/aicli-status.js';
import { setupSessionRoutes } from './routes/sessions.js';
import telemetryRoutes from './routes/telemetry.js';
import pushNotificationRoutes from './routes/push-notifications.js';
import { setupWebSocket } from './services/websocket.js';
import { errorHandler } from './middleware/error.js';
import { AICLIService } from './services/aicli.js';
import { ServerConfig } from './config/server-config.js';
import { MiddlewareConfig } from './config/middleware-config.js';
import { TLSConfig } from './config/tls-config.js';
import { ServerStartup } from './config/server-startup.js';
import { pushNotificationService } from './services/push-notification.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

class AICLICompanionServer {
  constructor() {
    this.app = express();
    this.config = new ServerConfig();
    this.aicliService = new AICLIService();
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
    this.authToken = this.config.authToken;

    this.setupBasicMiddleware();
    this.setupRoutes();
    this.setupErrorHandling();
  }

  setupBasicMiddleware() {
    // Set up basic middleware (no auth yet)
    MiddlewareConfig.configure(this.app, this.config);
  }

  setupRoutes() {
    // Health check (no auth required)
    this.app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        version: this.config.version,
        aicliCodeAvailable: this.aicliService.isAvailable(),
        timestamp: new Date().toISOString(),
      });
    });

    // API routes
    setupRoutes(this.app, this.aicliService);
    setupProjectRoutes(this.app, this.aicliService);
    setupAICLIStatusRoutes(this.app, this.aicliService);
    setupSessionRoutes(this.app, this.aicliService);
    this.app.use(telemetryRoutes);
    this.app.use(pushNotificationRoutes);

    // Static files (for web interface if needed)
    this.app.use('/static', express.static(join(__dirname, '../public')));

    // Default route
    this.app.get('/', (req, res) => {
      res.json({
        name: 'AICLI Companion Server',
        version: this.config.version,
        status: 'running',
        endpoints: {
          health: '/health',
          api: '/api',
          websocket: '/ws',
        },
      });
    });
  }

  setupWebSocket() {
    this.wss = new WebSocketServer({ server: this.server });
    setupWebSocket(this.wss, this.aicliService, this.authToken);

    // Forward AICLI CLI events to console for host app logging
    this.aicliService.on('processStart', (data) => {
      console.log(
        `[AICLI_PROCESS_START] PID: ${data.pid}, Type: ${data.type}, Session: ${data.sessionId || 'one-time'}`
      );
    });

    this.aicliService.on('processStdout', (data) => {
      console.log(`[AICLI_STDOUT] PID: ${data.pid} - ${data.data}`);
    });

    this.aicliService.on('processStderr', (data) => {
      console.error(`[AICLI_STDERR] PID: ${data.pid} - ${data.data}`);
    });

    this.aicliService.on('processExit', (data) => {
      console.log(
        `[AICLI_PROCESS_EXIT] PID: ${data.pid}, Code: ${data.code}, Session: ${data.sessionId || 'one-time'}`
      );
    });

    this.aicliService.on('processError', (data) => {
      console.error(`[AICLI_PROCESS_ERROR] PID: ${data.pid} - ${data.error}`);
    });

    this.aicliService.on('commandSent', (data) => {
      console.log(`[AICLI_COMMAND] Session: ${data.sessionId} - ${data.prompt}`);
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
      // Generate auth token only if authentication is required
      if (this.config.authRequired) {
        this.authToken = ServerStartup.generateAuthToken(this.authToken, this.config.authRequired);
        // Configure auth middleware now that we have the token
        MiddlewareConfig.configureAuth(this.app, this.authToken);
      } else {
        this.authToken = null;
      }

      // Initialize push notification service
      pushNotificationService.initialize({
        cert: process.env.APNS_CERT_PATH,
        key: process.env.APNS_KEY_PATH,
        passphrase: process.env.APNS_PASSPHRASE,
        production: process.env.NODE_ENV === 'production',
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

      // Set up WebSocket
      this.setupWebSocket();

      // Initialize AICLI session persistence (recover any existing sessions)
      console.log('🔄 Initializing session persistence...');
      await this.aicliService.sessionManager.initializePersistence();

      // Reconcile session state with AICLI CLI to clean up stale sessions
      try {
        const reconcileStats = await this.aicliService.sessionManager.reconcileSessionState();
        console.log(`📊 Session reconciliation stats:`, reconcileStats);
      } catch (error) {
        console.warn('⚠️ Session reconciliation failed:', error.message);
      }

      // Verify AICLI Code is available
      const isAvailable = await ServerStartup.checkAICLIAvailability(this.aicliService);

      // Start server
      this.server.listen(this.config.port, this.config.host, () => {
        const fingerprint = this.config.enableTLS
          ? this.tlsConfig.getCertificateFingerprint()
          : null;

        ServerStartup.displayStartupInfo(this.config, this.authToken, isAvailable, fingerprint);
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

  shutdown() {
    console.log('🔄 Shutting down server...');

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
