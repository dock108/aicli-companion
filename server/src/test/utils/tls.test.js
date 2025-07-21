import { describe, it } from 'node:test';
import assert from 'node:assert';
import { TLSManager, TokenManager } from '../../utils/tls.js';

describe('TLS Utilities', () => {
  describe('TLSManager', () => {
    it('should generate self-signed certificate', async () => {
      const tlsManager = new TLSManager();
      const result = await tlsManager.generateSelfSignedCertificate();

      assert.ok(result);
      assert.ok(result.key);
      assert.ok(result.cert);
      assert.ok(result.cert.includes('BEGIN CERTIFICATE'));
    });
  });

  describe('TokenManager', () => {
    it('should generate secure tokens', () => {
      const token = TokenManager.generateSecureToken();
      assert.ok(token);
      assert.equal(typeof token, 'string');
      assert.ok(token.length > 0);
    });

    it('should generate API keys with prefix', () => {
      const apiKey = TokenManager.generateAPIKey();
      assert.ok(apiKey.startsWith('cc_'));
    });
  });
});
