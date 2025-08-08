import dotenv from 'dotenv';
import path from 'path';
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
    this.authRequired = process.env.AUTH_REQUIRED !== 'false';
    this.authToken = this.authRequired ? process.env.AUTH_TOKEN || null : null;
    this.enableBonjour = process.env.ENABLE_BONJOUR !== 'false';
    this.enableTLS = process.env.ENABLE_TLS === 'true';
    this.allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || ['*'];
    this.nodeEnv = process.env.NODE_ENV || 'development';
    this.configPath = process.env.CONFIG_PATH || path.dirname(process.cwd());
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
}
