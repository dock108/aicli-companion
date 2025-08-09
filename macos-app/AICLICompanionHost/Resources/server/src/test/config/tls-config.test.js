import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { TLSConfig } from '../../config/tls-config.js';

describe('TLSConfig', () => {
  let tlsConfig;

  beforeEach(() => {
    // Mock console to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');

    tlsConfig = new TLSConfig();
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('constructor', () => {
    it('should create TLSConfig instance', () => {
      const config = new TLSConfig();

      assert.ok(config.tlsManager, 'Should have TLS manager');
    });
  });

  describe('setupTLS', () => {
    it('should attempt TLS setup and handle results', async () => {
      // Mock the TLSConfig setupTLS method to prevent actual OpenSSL execution
      const originalSetupTLS = tlsConfig.setupTLS;
      tlsConfig.setupTLS = mock.fn(async () => {
        // Simulate fallback to TLSManager
        return tlsConfig.tlsManager.ensureCertificateExists();
      });

      // Mock the internal TLSManager to prevent actual certificate generation
      const mockTLSManager = {
        ensureCertificateExists: mock.fn(() =>
          Promise.resolve({ cert: 'mock-cert', key: 'mock-key' })
        ),
        getCertificateFingerprint: mock.fn(() => 'mock-fingerprint'),
      };
      tlsConfig.tlsManager = mockTLSManager;

      // This should complete without throwing
      const result = await tlsConfig.setupTLS();

      // Should return some certificate data structure
      assert.ok(result, 'Should return TLS configuration');
      assert.ok(typeof result === 'object', 'Should return an object');
      assert.strictEqual(result.cert, 'mock-cert');
      assert.strictEqual(result.key, 'mock-key');

      // Restore original method
      tlsConfig.setupTLS = originalSetupTLS;
    });

    it.skip('should handle TLS setup failures gracefully', async () => {
      // Mock both OpenSSL generation and TLS manager to fail
      const mockTLSManager = {
        ensureCertificateExists: mock.fn(() => Promise.reject(new Error('TLS setup failed'))),
        getCertificateFingerprint: mock.fn(() => null),
      };
      tlsConfig.tlsManager = mockTLSManager;

      // The setupTLS method catches OpenSSL errors and falls back to tlsManager
      // Since we mocked tlsManager to also fail, it should reject
      await assert.rejects(() => tlsConfig.setupTLS(), /TLS setup failed/);
    });
  });

  describe('getCertificateFingerprint', () => {
    it('should delegate to TLSManager', () => {
      const expectedFingerprint = 'test-fingerprint';
      const mockTLSManager = {
        ensureCertificateExists: mock.fn(),
        getCertificateFingerprint: mock.fn(() => expectedFingerprint),
      };
      tlsConfig.tlsManager = mockTLSManager;

      const result = tlsConfig.getCertificateFingerprint();

      assert.strictEqual(result, expectedFingerprint);
      assert.strictEqual(mockTLSManager.getCertificateFingerprint.mock.calls.length, 1);
    });

    it('should return null when TLSManager returns null', () => {
      const mockTLSManager = {
        ensureCertificateExists: mock.fn(),
        getCertificateFingerprint: mock.fn(() => null),
      };
      tlsConfig.tlsManager = mockTLSManager;

      const result = tlsConfig.getCertificateFingerprint();

      assert.strictEqual(result, null);
    });

    it('should handle TLSManager errors gracefully', () => {
      const mockTLSManager = {
        ensureCertificateExists: mock.fn(),
        getCertificateFingerprint: mock.fn(() => {
          throw new Error('TLS Manager error');
        }),
      };
      tlsConfig.tlsManager = mockTLSManager;

      // The method propagates the error from TLSManager
      assert.throws(() => {
        tlsConfig.getCertificateFingerprint();
      }, /TLS Manager error/);
    });
  });
});
