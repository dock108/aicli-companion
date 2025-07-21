import { describe, it, after } from 'node:test';
import assert from 'node:assert';
import { setupBonjour } from '../../services/discovery.js';

describe('Discovery Service', () => {
  const services = [];

  after(() => {
    // Ensure all services are stopped
    services.forEach((service) => {
      if (service && service.stop) {
        try {
          service.stop();
        } catch (e) {
          // Ignore cleanup errors
        }
      }
    });

    // Force exit in test mode to ensure process ends
    if (process.env.NODE_ENV === 'test') {
      setTimeout(() => process.exit(0), 100);
    }
  });

  describe('setupBonjour', () => {
    it('should create Bonjour service with correct configuration', () => {
      const port = 3002; // Use different port to avoid conflicts
      const enableTLS = false;

      const service = setupBonjour(port, enableTLS);
      services.push(service);

      assert.ok(service);
      assert.strictEqual(service.port, port);
      assert.strictEqual(service.name, 'Claude Companion Server');
      assert.strictEqual(service.type, '_claudecode._tcp');
    });

    it('should set TLS configuration correctly', () => {
      const port = 3003; // Use different port to avoid conflicts
      const enableTLS = true;

      const service = setupBonjour(port, enableTLS);
      services.push(service);

      assert.ok(service);
      assert.strictEqual(service.txt.tls, 'enabled');
      assert.strictEqual(service.txt.protocol, 'wss');
    });

    it('should set non-TLS configuration correctly', () => {
      const port = 3004; // Use different port to avoid conflicts
      const enableTLS = false;

      const service = setupBonjour(port, enableTLS);
      services.push(service);

      assert.ok(service);
      assert.strictEqual(service.txt.tls, 'disabled');
      assert.strictEqual(service.txt.protocol, 'ws');
    });
  });
});
