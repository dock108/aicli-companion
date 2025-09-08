import dotenv from 'dotenv';
import path from 'path';
import os from 'os';
import { DEFAULT_CONFIG, SERVER_VERSION } from '../constants/index.js';

// Load environment variables
dotenv.config();

/**
 * Server configuration manager
 */
export class ServerConfig {
  constructor() {
    this.version = SERVER_VERSION;
    this.port = process.env.PORT || DEFAULT_CONFIG.PORT;
    this.host = process.env.HOST || DEFAULT_CONFIG.HOST;
    this.enableTunnel = process.env.ENABLE_TUNNEL === 'true';
    this.tunnelProvider = process.env.TUNNEL_PROVIDER || 'ngrok';

    // Auto-require auth if exposed to internet
    const explicitAuthRequired = process.env.AUTH_REQUIRED === 'true';
    const explicitAuthDisabled = process.env.AUTH_REQUIRED === 'false';

    if (this.isInternetExposed && !explicitAuthDisabled) {
      // Force auth for internet exposure unless explicitly disabled
      this.authRequired = true;
      console.log('🔒 Internet exposure detected - authentication required');
    } else {
      // Use explicit setting or default to false for local
      this.authRequired = explicitAuthRequired;
    }

    this.authToken = this.authRequired ? process.env.AUTH_TOKEN || null : null;
    this.enableBonjour = process.env.ENABLE_BONJOUR !== 'false';
    this.enableTLS = process.env.ENABLE_TLS === 'true';
    this.allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || ['*'];
    this.nodeEnv = process.env.NODE_ENV || 'development';
    
    // Set appropriate default path based on environment
    if (this.nodeEnv === 'test') {
      // For tests, use a test-specific directory to avoid searching entire home directory
      this.configPath = process.env.CONFIG_PATH || path.join(os.tmpdir(), 'aicli-test');
    } else {
      // For production/development, use the user's home directory
      this.configPath = process.env.CONFIG_PATH || os.homedir();
    }
  }

  /**
   * Get CORS configuration
   */
  getCorsConfig() {
    return {
      origin: this.allowedOrigins,
      credentials: true,
    };
  }

  /**
   * Get helmet security configuration
   */
  getHelmetConfig() {
    return {
      contentSecurityPolicy: false, // Disable for API server
      crossOriginEmbedderPolicy: false,
    };
  }

  /**
   * Check if running in development mode
   */
  isDevelopment() {
    return this.nodeEnv === 'development';
  }

  /**
   * Check if running in test mode
   */
  isTest() {
    return this.nodeEnv === 'test';
  }

  /**
   * Get the protocol string based on TLS setting
   */
  getProtocol() {
    return this.enableTLS ? 'https' : 'http';
  }

  /**
   * Get the WebSocket protocol string based on TLS setting
   */
  getWSProtocol() {
    return this.enableTLS ? 'wss' : 'ws';
  }

  /**
   * Get the hostname for display purposes
   */
  getDisplayHostname() {
    return this.host === '0.0.0.0' ? 'localhost' : this.host;
  }

  /**
   * Check if server is exposed to internet
   */
  get isInternetExposed() {
    // Tunnel explicitly enables internet exposure
    if (this.enableTunnel) {
      return true;
    }

    // Check if explicitly marked for public exposure
    if (process.env.EXPOSE_PUBLIC === 'true') {
      return true;
    }

    // Default to false (local only)
    return false;
  }
}
