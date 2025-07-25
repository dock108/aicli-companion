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
      console.log(`🔑 Generated auth token: ${token}`);
      console.log('   Save this token to connect mobile clients');
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
   * @param {boolean} claudeAvailable - Whether Claude Code is available
   * @param {string|null} fingerprint - TLS certificate fingerprint
   */
  static displayStartupInfo(config, authToken, claudeAvailable, fingerprint) {
    const protocol = config.getProtocol();
    const wsProtocol = config.getWSProtocol();
    const hostname = config.getDisplayHostname();

    console.log(`🚀 Claude Companion Server started`);
    console.log(`   ${protocol.toUpperCase()} Server: ${protocol}://${hostname}:${config.port}`);
    console.log(`   WebSocket: ${wsProtocol}://${hostname}:${config.port}/ws`);

    if (authToken) {
      console.log(`   🔐 Authentication enabled`);
      console.log(
        `   📱 Mobile app connection: ${wsProtocol}://${hostname}:${config.port}/ws?token=${authToken}`
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

    if (claudeAvailable) {
      console.log(`   ✅ Claude Code CLI detected`);
    }
  }

  /**
   * Check Claude Code availability and display warning if not available
   * @param {ClaudeCodeService} claudeService - Claude Code service instance
   * @returns {Promise<boolean>} Whether Claude Code is available
   */
  static async checkClaudeAvailability(claudeService) {
    const isAvailable = await claudeService.checkAvailability();
    if (!isAvailable) {
      console.warn(
        '⚠️  Claude Code CLI not found. Server will start but functionality will be limited.'
      );
      console.warn('   Please ensure Claude Code is installed and available in PATH.');
    }
    return isAvailable;
  }
}
