import { TLSManager, generateCertificateWithOpenSSL } from '../utils/tls.js';

/**
 * TLS configuration manager
 */
export class TLSConfig {
  constructor() {
    this.tlsManager = new TLSManager();
  }

  /**
   * Set up TLS configuration and return TLS options
   * @returns {Promise<Object>} TLS options for HTTPS server
   */
  async setupTLS() {
    try {
      // Try OpenSSL first for better certificate generation
      return generateCertificateWithOpenSSL();
    } catch (error) {
      // Fallback to Node.js crypto
      return this.tlsManager.ensureCertificateExists();
    }
  }

  /**
   * Get certificate fingerprint
   * @returns {string|null} Certificate fingerprint
   */
  getCertificateFingerprint() {
    return this.tlsManager.getCertificateFingerprint();
  }
}
