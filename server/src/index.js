#!/usr/bin/env node

import express from 'express';
import { createServer } from 'http';
import { createServer as createHttpsServer } from 'https';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

import { setupRoutes } from './routes/api-routes.js';
import { setupProjectRoutes } from './routes/projects.js';
import { setupAICLIStatusRoutes } from './routes/aicli-status.js';
import sessionRoutes from './routes/sessions.js';
import telemetryRoutes from './routes/telemetry-api.js';
import pushNotificationRoutes from './routes/push-notifications.js';
import chatRoutes from './routes/chat.js';
import devicesRoutes from './routes/devices.js';
import authRoutes from './routes/auth.js';
import { errorHandler } from './middleware/error.js';
import { AICLIService } from './services/aicli.js';
import { ServerConfig } from './config/server-config.js';
import { MiddlewareConfig } from './config/middleware-config.js';
import { TLSConfig } from './config/tls-config.js';
import { ServerStartup } from './config/server-startup.js';
import { pushNotificationService } from './services/push-notification.js';
import { tunnelService } from './services/tunnel.js';

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
    this.app.use(telemetryRoutes);
    this.app.use(pushNotificationRoutes);

    // New HTTP + APNS routes
    this.app.set('aicliService', this.aicliService); // Make available to route handlers
    this.app.use('/api/chat', chatRoutes);
    this.app.use('/api/devices', devicesRoutes);
    this.app.use('/api/sessions', sessionRoutes);

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
          chat: '/api/chat',
          devices: '/api/devices',
          projects: '/api/projects',
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

      // WebSocket infrastructure removed - using HTTP + APNS only

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

  async shutdown() {
    console.log('🔄 Shutting down server...');

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
