import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import request from 'supertest';
import QRCode from 'qrcode';
import os from 'os';
import authRoutes from '../../routes/auth.js';

describe('Auth Routes', () => {
  let app;
  let originalNetworkInterfaces;

  beforeEach(() => {
    // Create a fresh Express app for each test
    app = express();
    app.use(express.json());

    // Set up app locals for auth config
    app.locals.authRequired = false;
    app.locals.authToken = null;
    app.locals.port = 3001;
    app.locals.enableTLS = false;

    app.use('/api/auth', authRoutes);

    // Mock console methods
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');

    // Store original networkInterfaces function
    originalNetworkInterfaces = os.networkInterfaces;
  });

  afterEach(() => {
    // Restore original networkInterfaces
    os.networkInterfaces = originalNetworkInterfaces;
    mock.restoreAll();
  });

  describe('GET /api/auth/setup', () => {
    it('should generate QR code for connection without auth', async () => {
      // Mock network interfaces
      os.networkInterfaces = () => ({
        eth0: [
          {
            family: 'IPv4',
            internal: false,
            address: '192.168.1.100',
          },
        ],
        lo: [
          {
            family: 'IPv4',
            internal: true,
            address: '127.0.0.1',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.ok(response.body.connectionInfo);
      assert.strictEqual(response.body.connectionInfo.url, 'ws://192.168.1.100:3001/ws');
      assert.strictEqual(response.body.connectionInfo.host, '192.168.1.100');
      assert.strictEqual(response.body.connectionInfo.port, 3001);
      assert.strictEqual(response.body.connectionInfo.protocol, 'ws');
      assert.strictEqual(response.body.connectionInfo.authRequired, false);
      assert.strictEqual(response.body.connectionInfo.hasToken, false);

      assert.ok(response.body.qrCode);
      assert.ok(response.body.qrCode.dataUrl);
      assert.ok(response.body.qrCode.svg);
      assert.ok(response.body.qrCode.dataUrl.startsWith('data:image/png;base64,'));

      assert.ok(response.body.availableAddresses);
      assert.strictEqual(response.body.availableAddresses.length, 1);
      assert.strictEqual(response.body.availableAddresses[0].interface, 'eth0');
      assert.strictEqual(response.body.availableAddresses[0].address, '192.168.1.100');
    });

    it('should generate QR code with auth token', async () => {
      app.locals.authRequired = true;
      app.locals.authToken = 'test-auth-token-12345';

      os.networkInterfaces = () => ({
        eth0: [
          {
            family: 'IPv4',
            internal: false,
            address: '192.168.1.100',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(
        response.body.connectionInfo.url,
        'ws://192.168.1.100:3001/ws?token=test-auth-token-12345'
      );
      assert.strictEqual(response.body.connectionInfo.authRequired, true);
      assert.strictEqual(response.body.connectionInfo.hasToken, true);

      // Check that token is included in available addresses
      assert.strictEqual(
        response.body.availableAddresses[0].url,
        'ws://192.168.1.100:3001/ws?token=test-auth-token-12345'
      );
    });

    it('should generate QR code with TLS enabled', async () => {
      app.locals.enableTLS = true;

      os.networkInterfaces = () => ({
        wlan0: [
          {
            family: 'IPv4',
            internal: false,
            address: '10.0.0.50',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.connectionInfo.protocol, 'wss');
      assert.strictEqual(response.body.connectionInfo.url, 'wss://10.0.0.50:3001/ws');
      assert.strictEqual(response.body.availableAddresses[0].url, 'wss://10.0.0.50:3001/ws');
    });

    it('should handle multiple network interfaces', async () => {
      os.networkInterfaces = () => ({
        eth0: [
          {
            family: 'IPv4',
            internal: false,
            address: '192.168.1.100',
          },
        ],
        wlan0: [
          {
            family: 'IPv4',
            internal: false,
            address: '10.0.0.50',
          },
        ],
        docker0: [
          {
            family: 'IPv4',
            internal: false,
            address: '172.17.0.1',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.availableAddresses.length, 3);

      const addresses = response.body.availableAddresses.map((a) => a.address);
      assert.ok(addresses.includes('192.168.1.100'));
      assert.ok(addresses.includes('10.0.0.50'));
      assert.ok(addresses.includes('172.17.0.1'));
    });

    it('should fallback to localhost when no network interfaces found', async () => {
      os.networkInterfaces = () => ({});

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.connectionInfo.host, 'localhost');
      assert.strictEqual(response.body.connectionInfo.url, 'ws://localhost:3001/ws');
    });

    it('should filter out IPv6 addresses', async () => {
      os.networkInterfaces = () => ({
        eth0: [
          {
            family: 'IPv4',
            internal: false,
            address: '192.168.1.100',
          },
          {
            family: 'IPv6',
            internal: false,
            address: 'fe80::1',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.availableAddresses.length, 1);
      assert.strictEqual(response.body.availableAddresses[0].address, '192.168.1.100');
    });

    it('should handle QR code generation errors', async () => {
      // Mock QRCode.toDataURL to throw an error
      const originalToDataURL = QRCode.toDataURL;
      QRCode.toDataURL = async () => {
        throw new Error('QR code generation failed');
      };

      os.networkInterfaces = () => ({
        eth0: [
          {
            family: 'IPv4',
            internal: false,
            address: '192.168.1.100',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(500);

      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to generate QR code');
      assert.strictEqual(response.body.message, 'QR code generation failed');

      // Restore original function
      QRCode.toDataURL = originalToDataURL;
    });

    it('should use custom port from app locals', async () => {
      app.locals.port = 8080;

      os.networkInterfaces = () => ({
        eth0: [
          {
            family: 'IPv4',
            internal: false,
            address: '192.168.1.100',
          },
        ],
      });

      const response = await request(app).get('/api/auth/setup').expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.connectionInfo.port, 8080);
      assert.strictEqual(response.body.connectionInfo.url, 'ws://192.168.1.100:8080/ws');
    });
  });

  describe('GET /api/auth/status', () => {
    it('should return auth not required status', async () => {
      app.locals.authRequired = false;
      app.locals.authToken = null;

      const response = await request(app).get('/api/auth/status').expect(200);

      assert.strictEqual(response.body.authRequired, false);
      assert.strictEqual(response.body.hasToken, false);
      assert.strictEqual(response.body.authenticated, true);
    });

    it('should return auth required without token', async () => {
      app.locals.authRequired = true;
      app.locals.authToken = 'secret-token';

      const response = await request(app).get('/api/auth/status').expect(200);

      assert.strictEqual(response.body.authRequired, true);
      assert.strictEqual(response.body.hasToken, true);
      assert.strictEqual(response.body.authenticated, false);
    });

    it('should return authenticated with correct token', async () => {
      app.locals.authRequired = true;
      app.locals.authToken = 'secret-token';

      const response = await request(app)
        .get('/api/auth/status')
        .set('Authorization', 'Bearer secret-token')
        .expect(200);

      assert.strictEqual(response.body.authRequired, true);
      assert.strictEqual(response.body.hasToken, true);
      assert.strictEqual(response.body.authenticated, true);
    });

    it('should return not authenticated with wrong token', async () => {
      app.locals.authRequired = true;
      app.locals.authToken = 'secret-token';

      const response = await request(app)
        .get('/api/auth/status')
        .set('Authorization', 'Bearer wrong-token')
        .expect(200);

      assert.strictEqual(response.body.authRequired, true);
      assert.strictEqual(response.body.hasToken, true);
      assert.strictEqual(response.body.authenticated, false);
    });

    it('should handle missing Authorization header', async () => {
      app.locals.authRequired = true;
      app.locals.authToken = 'secret-token';

      const response = await request(app).get('/api/auth/status').expect(200);

      assert.strictEqual(response.body.authenticated, false);
    });

    it('should treat authRequired undefined as true', async () => {
      app.locals.authRequired = undefined;
      app.locals.authToken = 'token';

      const response = await request(app).get('/api/auth/status').expect(200);

      assert.strictEqual(response.body.authRequired, true);
    });
  });
});
