import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import DiscoveryService from '../../services/discovery.js';

describe('DiscoveryService', () => {
  let service;

  beforeEach(() => {
    service = new DiscoveryService();
  });

  afterEach(() => {
    // Clean up
    if (service) {
      service.stop();
    }
  });

  describe('constructor', () => {
    it('should initialize with null service', () => {
      assert.strictEqual(service.service, null);
      assert.ok(service.bonjour);
    });
  });

  describe('start', () => {
    it('should publish service on specified port', () => {
      const port = 3001;

      service.start(port);

      assert.ok(service.service);
      assert.strictEqual(service.service.name, 'claude-companion');
      assert.strictEqual(service.service.port, port);
    });

    it('should not publish twice if already started', () => {
      const port = 3001;

      service.start(port);
      const firstService = service.service;

      service.start(port);
      const secondService = service.service;

      assert.strictEqual(firstService, secondService);
    });
  });

  describe('stop', () => {
    it('should stop published service', () => {
      service.start(3001);
      assert.ok(service.service);

      service.stop();
      assert.strictEqual(service.service, null);
    });

    it('should handle stop when not started', () => {
      assert.doesNotThrow(() => {
        service.stop();
      });
    });
  });

  describe('getServiceInfo', () => {
    it('should return service info when running', () => {
      const port = 3001;
      service.start(port);

      const info = service.getServiceInfo();

      assert.ok(info);
      assert.strictEqual(info.name, 'claude-companion');
      assert.strictEqual(info.port, port);
      assert.strictEqual(info.type, 'http');
    });

    it('should return null when not running', () => {
      const info = service.getServiceInfo();
      assert.strictEqual(info, null);
    });
  });
});
