#!/usr/bin/env node

import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import { createServer as createHttpsServer } from 'https';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';

import { setupRoutes } from './routes/index.js';
import { setupWebSocket } from './services/websocket-v2.js';
import { setupBonjour } from './services/discovery.js';
import { authMiddleware } from './middleware/auth.js';
import { errorHandler } from './middleware/error.js';
import { ClaudeCodeService } from './services/claude-code.js';
import { TLSManager, TokenManager, generateCertificateWithOpenSSL } from './utils/tls.js';

// Load environment variables
dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

class ClaudeCompanionServer {
  constructor() {
    this.app = express();
    this.claudeService = new ClaudeCodeService();
    this.tlsManager = new TLSManager();
    
    this.port = process.env.PORT || 3001;
    this.host = process.env.HOST || '0.0.0.0';
    this.authToken = process.env.AUTH_TOKEN || null;
    this.enableBonjour = process.env.ENABLE_BONJOUR !== 'false';
    this.enableTLS = process.env.ENABLE_TLS === 'true';
    
    // Will be set up during start()
    this.server = null;
    this.wss = null;
    
    this.setupMiddleware();
    this.setupRoutes();
    this.setupErrorHandling();
  }
  
  setupMiddleware() {
    // Security middleware
    this.app.use(helmet({
      contentSecurityPolicy: false, // Disable for API server
      crossOriginEmbedderPolicy: false
    }));
    
    // CORS configuration
    this.app.use(cors({
      origin: process.env.ALLOWED_ORIGINS?.split(',') || ['*'],
      credentials: true
    }));
    
    // Logging
    this.app.use(morgan('combined'));
    
    // Body parsing
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true }));
    
    // Authentication middleware (optional)
    if (this.authToken) {
      this.app.use('/api', authMiddleware(this.authToken));
    }
  }
  
  setupRoutes() {
    // Health check (no auth required)
    this.app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        version: '1.0.0',
        claudeCodeAvailable: this.claudeService.isAvailable(),
        timestamp: new Date().toISOString()
      });
    });
    
    // API routes
    setupRoutes(this.app, this.claudeService);
    
    // Static files (for web interface if needed)
    this.app.use('/static', express.static(join(__dirname, '../public')));
    
    // Default route
    this.app.get('/', (req, res) => {
      res.json({
        name: 'Claude Companion Server',
        version: '1.0.0',
        status: 'running',
        endpoints: {
          health: '/health',
          api: '/api',
          websocket: '/ws'
        }
      });
    });
  }
  
  setupWebSocket() {
    this.wss = new WebSocketServer({ server: this.server });
    setupWebSocket(this.wss, this.claudeService, this.authToken);
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
      // Generate auth token if not provided
      if (!this.authToken) {
        this.authToken = TokenManager.generateSecureToken();
        console.log(`🔑 Generated auth token: ${this.authToken}`);
        console.log('   Save this token to connect mobile clients');
      }
      
      // Set up TLS if enabled
      let tlsOptions = null;
      if (this.enableTLS) {
        try {
          tlsOptions = await this.setupTLS();
        } catch (error) {
          console.warn(`⚠️  TLS setup failed: ${error.message}`);
          console.warn('   Falling back to HTTP');
          this.enableTLS = false;
        }
      }
      
      // Create HTTP or HTTPS server
      if (this.enableTLS && tlsOptions) {
        this.server = createHttpsServer(tlsOptions, this.app);
      } else {
        this.server = createServer(this.app);
      }
      
      // Set up WebSocket
      this.setupWebSocket();
      
      // Verify Claude Code is available
      const isAvailable = await this.claudeService.checkAvailability();
      if (!isAvailable) {
        console.warn('⚠️  Claude Code CLI not found. Server will start but functionality will be limited.');
        console.warn('   Please ensure Claude Code is installed and available in PATH.');
      }
      
      // Start server
      this.server.listen(this.port, this.host, () => {
        const protocol = this.enableTLS ? 'https' : 'http';
        const wsProtocol = this.enableTLS ? 'wss' : 'ws';
        const hostname = this.host === '0.0.0.0' ? 'localhost' : this.host;
        
        console.log(`🚀 Claude Companion Server started`);
        console.log(`   ${protocol.toUpperCase()} Server: ${protocol}://${hostname}:${this.port}`);
        console.log(`   WebSocket: ${wsProtocol}://${hostname}:${this.port}/ws`);
        
        if (this.authToken) {
          console.log(`   🔐 Authentication enabled`);
          console.log(`   📱 Mobile app connection: ${wsProtocol}://${hostname}:${this.port}/ws?token=${this.authToken}`);
        }
        
        if (this.enableTLS) {
          console.log(`   🔒 TLS encryption enabled`);
          const fingerprint = this.tlsManager.getCertificateFingerprint();
          if (fingerprint) {
            console.log(`   🔒 Certificate fingerprint: ${fingerprint}`);
          }
        }
        
        if (isAvailable) {
          console.log(`   ✅ Claude Code CLI detected`);
        }
      });
      
      // Setup service discovery
      if (this.enableBonjour) {
        try {
          setupBonjour(this.port, this.enableTLS);
          console.log(`   📡 Bonjour service advertising on port ${this.port}`);
        } catch (error) {
          console.warn(`   ⚠️  Bonjour setup failed: ${error.message}`);
        }
      }
      
    } catch (error) {
      console.error('Failed to start server:', error);
      process.exit(1);
    }
  }
  
  async setupTLS() {
    try {
      // Try OpenSSL first for better certificate generation
      return await generateCertificateWithOpenSSL();
    } catch (error) {
      // Fallback to Node.js crypto
      return await this.tlsManager.ensureCertificateExists();
    }
  }
  
  shutdown() {
    console.log('🔄 Shutting down server...');
    
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
  const server = new ClaudeCompanionServer();
  server.start().catch(console.error);
}

export { ClaudeCompanionServer };