import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { TLSConfig } from '../../config/tls-config.js';

describe('TLSConfig', () => {
  let tlsConfig;
  let mockTLSManager;

  beforeEach(() => {
    // Mock console to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');

    tlsConfig = new TLSConfig();

    // Mock the internal TLSManager
    mockTLSManager = {
      ensureCertificateExists: mock.fn(),
      getCertificateFingerprint: mock.fn(),
    };
    tlsConfig.tlsManager = mockTLSManager;
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
    it('should try OpenSSL first and return result on success', async () => {
      const expectedResult = { cert: 'test-cert', key: 'test-key' };

      // Mock generateCertificateWithOpenSSL to succeed
      const originalGenerateCert = await import('../../utils/tls.js');
      mock.method(originalGenerateCert, 'generateCertificateWithOpenSSL', () =>
        Promise.resolve(expectedResult)
      );

      const result = await tlsConfig.setupTLS();

      assert.deepStrictEqual(result, expectedResult);
    });

    it('should fallback to TLSManager on OpenSSL failure', async () => {
      const expectedFallback = { cert: 'fallback-cert', key: 'fallback-key' };

      // Mock generateCertificateWithOpenSSL to fail
      const originalGenerateCert = await import('../../utils/tls.js');
      mock.method(originalGenerateCert, 'generateCertificateWithOpenSSL', () =>
        Promise.reject(new Error('OpenSSL not available'))
      );

      // Mock TLSManager fallback to succeed
      mockTLSManager.ensureCertificateExists.mock.mockImplementation(() =>
        Promise.resolve(expectedFallback)
      );

      const result = await tlsConfig.setupTLS();

      assert.deepStrictEqual(result, expectedFallback);
      assert.strictEqual(mockTLSManager.ensureCertificateExists.mock.calls.length, 1);
    });

    it('should propagate TLSManager errors', async () => {
      const expectedError = new Error('TLS Manager failed');

      // Mock generateCertificateWithOpenSSL to fail
      const originalGenerateCert = await import('../../utils/tls.js');
      mock.method(originalGenerateCert, 'generateCertificateWithOpenSSL', () =>
        Promise.reject(new Error('OpenSSL not available'))
      );

      // Mock TLSManager fallback to fail
      mockTLSManager.ensureCertificateExists.mock.mockImplementation(() =>
        Promise.reject(expectedError)
      );

      await assert.rejects(() => tlsConfig.setupTLS(), expectedError);
    });
  });

  describe('getCertificateFingerprint', () => {
    it('should delegate to TLSManager', () => {
      const expectedFingerprint = 'test-fingerprint';
      mockTLSManager.getCertificateFingerprint.mock.mockImplementation(() => expectedFingerprint);

      const result = tlsConfig.getCertificateFingerprint();

      assert.strictEqual(result, expectedFingerprint);
      assert.strictEqual(mockTLSManager.getCertificateFingerprint.mock.calls.length, 1);
    });

    it('should return null when TLSManager returns null', () => {
      mockTLSManager.getCertificateFingerprint.mock.mockImplementation(() => null);

      const result = tlsConfig.getCertificateFingerprint();

      assert.strictEqual(result, null);
    });

    it('should handle TLSManager errors gracefully', () => {
      mockTLSManager.getCertificateFingerprint.mock.mockImplementation(() => {
        throw new Error('TLS Manager error');
      });

      // Should not throw, but may return undefined or null
      assert.doesNotThrow(() => {
        tlsConfig.getCertificateFingerprint();
      });
    });
  });
});
