import { createLogger } from '../utils/logger.js';

const logger = createLogger('TunnelService');

/**
 * Tunnel service for exposing local server to internet
 */
export class TunnelService {
  constructor() {
    this.ngrok = null;
    this.tunnelUrl = null;
    this.isActive = false;
    this.listener = null;
  }

  /**
   * Initialize ngrok if available
   */
  async initialize() {
    try {
      // Dynamic import to avoid errors if ngrok not installed
      const ngrokModule = await import('@ngrok/ngrok').catch(() => null);
      if (ngrokModule) {
        this.ngrok = ngrokModule.default || ngrokModule;
        logger.info('Ngrok module loaded successfully');
        return true;
      } else {
        logger.warn('Ngrok module not installed - tunnel feature disabled');
        logger.warn('To enable tunneling, run: npm install @ngrok/ngrok');
        return false;
      }
    } catch (error) {
      logger.error('Failed to initialize ngrok:', error);
      return false;
    }
  }

  /**
   * Start tunnel to expose local server
   * @param {number} port - Local server port
   * @param {string} authToken - Ngrok auth token (optional)
   * @returns {Promise<string|null>} Public URL or null if failed
   */
  async startTunnel(port, authToken) {
    if (!this.ngrok) {
      const initialized = await this.initialize();
      if (!initialized) {
        logger.error('Failed to initialize ngrok - tunnel unavailable');
        return null;
      }
    }

    try {
      logger.info(`Starting ngrok tunnel for port ${port}...`);
      logger.debug(`Environment NGROK_AUTH_TOKEN present: ${!!process.env.NGROK_AUTH_TOKEN}`);
      logger.debug(`Auth token parameter present: ${!!authToken}`);

      // Configure ngrok options
      const options = {
        addr: port,
        proto: 'http',
      };

      // Configure auth token if provided
      if (authToken) {
        // In newer versions, auth token is passed in options instead of separate method
        options.authtoken = authToken;
        logger.info('Ngrok auth token configured');
      } else {
        logger.warn('No ngrok auth token provided - may fail for public tunnels');
      }

      // Start the tunnel - @ngrok/ngrok v1.5+ uses forward() instead of connect()
      this.listener = await this.ngrok.forward(options);
      // The @ngrok/ngrok package returns a Listener object, not a URL string
      // We need to call .url() to get the actual URL
      this.tunnelUrl = typeof this.listener === 'string' ? this.listener : this.listener.url();
      this.isActive = true;

      logger.info(`✅ Ngrok tunnel established: ${this.tunnelUrl}`);

      // Log tunnel details
      const tunnelInfo = await this.getTunnelInfo();
      if (tunnelInfo) {
        logger.info('Tunnel details:', tunnelInfo);
      }

      return this.tunnelUrl;
    } catch (error) {
      logger.error('Failed to start ngrok tunnel:', error);

      // Provide helpful error messages based on error type
      if (error.errorCode === 'ERR_NGROK_105' || error.code === 'GenericFailure') {
        logger.error('💡 Ngrok authentication failed - invalid or expired token');
        logger.error('   1. Check your auth token at https://dashboard.ngrok.com/auth');
        logger.error('   2. Verify the token is copied correctly (no extra spaces)');
        logger.error('   3. Ensure the token starts with your account ID');
        logger.error('   4. Try generating a new token if this one is old');
      } else if (error.message?.includes('authtoken') || error.message?.includes('authentication')) {
        logger.error('💡 Ngrok requires an auth token for this operation');
        logger.error('   1. Sign up at https://ngrok.com');
        logger.error('   2. Get your auth token from the dashboard');
        logger.error('   3. Set NGROK_AUTH_TOKEN in your .env file');
      } else if (error.message?.includes('port')) {
        logger.error(`💡 Make sure the server is running on port ${port}`);
      }
      
      // Log additional debugging info for auth token issues
      if (authToken) {
        logger.debug(`Auth token length: ${authToken.length}`);
        logger.debug(`Auth token format: ${authToken.substring(0, 12)}...`);
      }

      this.isActive = false;
      return null;
    }
  }

  /**
   * Get tunnel information
   * @returns {Promise<Object|null>} Tunnel info or null
   */
  async getTunnelInfo() {
    if (!this.isActive || !this.tunnelUrl) {
      return null;
    }

    try {
      // Get tunnel details from ngrok API
      const apiUrl = 'http://localhost:4040/api/tunnels';
      const response = await fetch(apiUrl).catch(() => null);

      if (response && response.ok) {
        const data = await response.json();
        const tunnel = data.tunnels?.find((t) => t.public_url === this.tunnelUrl);

        if (tunnel) {
          return {
            publicUrl: tunnel.public_url,
            protocol: tunnel.proto,
            localAddr: tunnel.config?.addr,
            metrics: tunnel.metrics,
          };
        }
      }
    } catch (error) {
      logger.debug('Could not fetch tunnel info:', error.message);
    }

    return {
      publicUrl: this.tunnelUrl,
      protocol: 'http',
      localAddr: null,
    };
  }

  /**
   * Stop the tunnel
   */
  async stopTunnel() {
    if (this.isActive) {
      try {
        // In newer @ngrok/ngrok versions, we may have a listener object to close
        if (this.listener && typeof this.listener.close === 'function') {
          await this.listener.close();
          logger.info('Ngrok tunnel listener closed');
        }
        // Fallback for older API
        if (this.ngrok && typeof this.ngrok.disconnect === 'function') {
          await this.ngrok.disconnect();
          logger.info('Ngrok tunnel disconnected');
        }
        if (this.ngrok && typeof this.ngrok.kill === 'function') {
          await this.ngrok.kill();
          logger.info('Ngrok process killed');
        }
      } catch (error) {
        logger.error('Error stopping ngrok tunnel:', error);
      }

      this.tunnelUrl = null;
      this.isActive = false;
      this.listener = null;
    }
  }

  /**
   * Get the public URL
   * @returns {string|null} Public URL or null
   */
  getPublicUrl() {
    return this.tunnelUrl;
  }

  /**
   * Check if tunnel is active
   * @returns {boolean} True if tunnel is active
   */
  isTunnelActive() {
    return this.isActive;
  }

  /**
   * Generate QR code for mobile connection
   * @param {string} url - URL to encode
   * @param {string} authToken - Auth token to include
   * @returns {string} ASCII QR code
   */
  generateConnectionQR(url, authToken) {
    // For now, just return the connection string
    // Could integrate qrcode package later
    const connectionUrl = authToken ? `${url}?token=${authToken}` : url;
    return `
╔════════════════════════════════════════╗
║  Scan QR or use URL below to connect  ║
║                                        ║
║  ${connectionUrl.padEnd(36)} ║
╚════════════════════════════════════════╝
    `.trim();
  }
}

// Export singleton instance
export const tunnelService = new TunnelService();
