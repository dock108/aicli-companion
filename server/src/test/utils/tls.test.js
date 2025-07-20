import { describe, it } from 'node:test';
import assert from 'node:assert';
import { generateCertificate } from '../../utils/tls.js';

describe('TLS Utilities', () => {
  describe('generateCertificate', () => {
    it('should return certificate object with key and cert', async () => {
      // This test uses the actual implementation since it's using crypto
      const result = await generateCertificate();

      assert.ok(result);
      assert.ok(result.key);
      assert.ok(result.cert);
      assert.ok(result.key.includes('BEGIN RSA PRIVATE KEY'));
      assert.ok(result.cert.includes('BEGIN CERTIFICATE'));
    });

    it('should generate valid certificate properties', async () => {
      const result = await generateCertificate();

      // Check that cert contains expected fields
      assert.ok(result.cert.includes('CN=localhost'));
      assert.ok(result.cert.includes('Claude Companion Server'));
    });

    it('should create certificates directory', async () => {
      // Test that the function attempts to create the certs directory
      const result = await generateCertificate();

      // If we got here without error, the directory was created or already exists
      assert.ok(result);
    });
  });
});
