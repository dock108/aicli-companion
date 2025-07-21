import { describe, it } from 'node:test';
import assert from 'node:assert';
import { setupBonjour } from '../../services/discovery.js';

describe('Discovery Service', () => {
  describe('setupBonjour', () => {
    it('should create Bonjour service with correct configuration', () => {
      const port = 3001;
      const enableTLS = false;

      const service = setupBonjour(port, enableTLS);

      assert.ok(service);
      assert.strictEqual(service.port, port);
      assert.strictEqual(service.name, 'Claude Companion Server');
      assert.strictEqual(service.type, '_claudecode._tcp');
    });

    it('should set TLS configuration correctly', () => {
      const port = 3001;
      const enableTLS = true;

      const service = setupBonjour(port, enableTLS);

      assert.ok(service);
      assert.strictEqual(service.txt.tls, 'enabled');
      assert.strictEqual(service.txt.protocol, 'wss');
    });

    it('should set non-TLS configuration correctly', () => {
      const port = 3001;
      const enableTLS = false;

      const service = setupBonjour(port, enableTLS);

      assert.ok(service);
      assert.strictEqual(service.txt.tls, 'disabled');
      assert.strictEqual(service.txt.protocol, 'ws');
    });
  });
});
