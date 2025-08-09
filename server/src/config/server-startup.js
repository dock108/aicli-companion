import { setupBonjour } from '../services/discovery.js';
import { TokenManager } from '../utils/tls.js';

/**
 * Server startup orchestrator
 */
export class ServerStartup {
  /**
   * Generate or use existing auth token
   * @param {string|null} existingToken - Existing auth token from config
   * @param {boolean} authRequired - Whether authentication is required
   * @returns {string|null} Auth token to use
   */
  static generateAuthToken(existingToken, authRequired) {
    if (!authRequired) {
      return null;
    }
    if (!existingToken) {
      const token = TokenManager.generateSecureToken();
      // Mask the generated token for security
      const maskedToken = token.substring(0, 8) + '...****';
      console.log(`🔑 Generated auth token: ${maskedToken}`);
      console.log('   Full token available in app settings');
      return token;
    }
    return existingToken;
  }

  /**
   * Setup service discovery (Bonjour)
   * @param {number} port - Server port
   * @param {boolean} enableTLS - Whether TLS is enabled
   * @param {boolean} enableBonjour - Whether to enable Bonjour
   */
  static setupServiceDiscovery(port, enableTLS, enableBonjour) {
    if (enableBonjour) {
      try {
        setupBonjour(port, enableTLS);
        console.log(`   📡 Bonjour service advertising on port ${port}`);
      } catch (error) {
        console.warn(`   ⚠️  Bonjour setup failed: ${error.message}`);
      }
    }
  }

  /**
   * Display server startup information
   * @param {ServerConfig} config - Server configuration
   * @param {string} authToken - Auth token
   * @param {boolean} aicliAvailable - Whether AICLI Code is available
   * @param {string|null} fingerprint - TLS certificate fingerprint
   */
  static displayStartupInfo(config, authToken, aicliAvailable, fingerprint) {
    const protocol = config.getProtocol();
    const wsProtocol = config.getWSProtocol();
    const hostname = config.getDisplayHostname();

    console.log(`🚀 AICLI Companion Server started`);
    console.log(`   ${protocol.toUpperCase()} Server: ${protocol}://${hostname}:${config.port}`);
    console.log(`   WebSocket: ${wsProtocol}://${hostname}:${config.port}/ws`);

    if (authToken) {
      console.log(`   🔐 Authentication enabled`);
      // Mask auth token in connection URL for security
      const maskedToken = authToken.substring(0, 8) + '...****';
      console.log(
        `   📱 Mobile app connection: ${wsProtocol}://${hostname}:${config.port}/ws?token=${maskedToken}`
      );
    } else {
      console.log(`   🔓 Authentication disabled (AUTH_REQUIRED=false)`);
      console.log(`   📱 Mobile app connection: ${wsProtocol}://${hostname}:${config.port}/ws`);
    }

    if (config.enableTLS) {
      console.log(`   🔒 TLS encryption enabled`);
      if (fingerprint) {
        console.log(`   🔒 Certificate fingerprint: ${fingerprint}`);
      }
    }

    if (aicliAvailable) {
      console.log(`   ✅ AICLI Code CLI detected`);
    }
  }

  /**
   * Check AICLI Code availability and display warning if not available
   * @param {AICLIService} aicliService - AICLI Code service instance
   * @returns {Promise<boolean>} Whether AICLI Code is available
   */
  static async checkAICLIAvailability(aicliService) {
    const isAvailable = await aicliService.checkAvailability();
    if (!isAvailable) {
      console.warn(
        '⚠️  AICLI Code CLI not found. Server will start but functionality will be limited.'
      );
      console.warn('   Please ensure AICLI Code is installed and available in PATH.');
    }
    return isAvailable;
  }
}
