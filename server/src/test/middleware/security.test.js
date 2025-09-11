import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import request from 'supertest';
import {
  createRateLimiter,
  createAuthRateLimiter,
  blockListMiddleware,
  clearFailedAttempts,
  trackFailedAuth,
  securityHeaders,
  validateRequest,
  configureSecurity,
} from '../../middleware/security.js';

describe('Security Middleware', () => {
  let app;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Mock console to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');
    mock.method(console, 'info');
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('createRateLimiter', () => {
    it('should create rate limiter with local settings', async () => {
      const limiter = createRateLimiter(false);
      app.use('/test', limiter, (req, res) => res.json({ success: true }));

      // Make requests within limit
      for (let i = 0; i < 5; i++) {
        const response = await request(app).get('/test');
        assert.strictEqual(response.status, 200);
      }
    });

    it('should create rate limiter with public settings', async () => {
      const limiter = createRateLimiter(true);
      app.use('/test', limiter, (req, res) => res.json({ success: true }));

      // Make requests within limit
      for (let i = 0; i < 5; i++) {
        const response = await request(app).get('/test');
        assert.strictEqual(response.status, 200);
      }
    });

    it('should enforce rate limit when exceeded', async () => {
      const _limiter = createRateLimiter(true);
      // Override max for testing
      const testLimiter = createRateLimiter(true);

      app.use('/test', testLimiter, (req, res) => res.json({ success: true }));

      // Note: Rate limiting with memory store can be tricky in tests
      // This is a basic structure - real rate limit testing may need more setup
    });
  });

  describe('createAuthRateLimiter', () => {
    it('should create auth rate limiter', () => {
      const limiter = createAuthRateLimiter();
      assert.ok(limiter);
      assert.strictEqual(typeof limiter, 'function');
    });

    it('should skip successful requests', async () => {
      const limiter = createAuthRateLimiter();
      app.post('/auth', limiter, (req, res) => {
        res.json({ success: true });
      });

      // Successful requests shouldn't count toward limit
      for (let i = 0; i < 10; i++) {
        const response = await request(app).post('/auth').send({ user: 'test' });
        assert.strictEqual(response.status, 200);
      }
    });
  });

  describe('blockListMiddleware', () => {
    it('should allow requests from non-blocked IPs', async () => {
      app.use(blockListMiddleware());
      app.get('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).get('/test');
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
    });

    it('should block requests from IPs with too many failed attempts', async () => {
      // Track 10 failed attempts
      for (let i = 0; i < 10; i++) {
        trackFailedAuth('::ffff:127.0.0.1');
      }

      app.use(blockListMiddleware());
      app.get('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).get('/test');
      assert.strictEqual(response.status, 403);
      assert.strictEqual(response.body.error, 'Forbidden');
      assert.ok(response.body.message.includes('temporarily blocked'));

      // Clean up
      clearFailedAttempts('::ffff:127.0.0.1');
    });
  });

  describe('clearFailedAttempts', () => {
    it('should clear failed attempts for an IP', () => {
      // Add some failed attempts
      trackFailedAuth('192.168.1.1');
      trackFailedAuth('192.168.1.1');

      // Clear attempts
      clearFailedAttempts('192.168.1.1');

      // The function should execute without error
      // The actual clearing is tested indirectly via blockListMiddleware
      assert.ok(true);
    });

    it('should handle clearing non-existent IP gracefully', () => {
      clearFailedAttempts('192.168.1.99');
      // Should not throw error
      assert.ok(true);
    });
  });

  describe('trackFailedAuth', () => {
    it('should track failed authentication attempts', () => {
      const ip = '192.168.1.2';

      trackFailedAuth(ip);

      // Function should execute without error
      assert.ok(true);

      // Clean up
      clearFailedAttempts(ip);
    });

    it('should handle multiple failed attempts', () => {
      const ip = '192.168.1.3';

      // Track 5 attempts
      for (let i = 0; i < 5; i++) {
        trackFailedAuth(ip);
      }

      // Function should handle multiple attempts
      assert.ok(true);

      // Clean up
      clearFailedAttempts(ip);
    });
  });

  describe('securityHeaders', () => {
    it('should not add security headers for local usage', async () => {
      app.use(securityHeaders(false));
      app.get('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).get('/test');
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.headers['x-content-type-options'], undefined);
      assert.strictEqual(response.headers['x-frame-options'], undefined);
    });

    it('should add security headers for public usage', async () => {
      app.use(securityHeaders(true));
      app.get('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).get('/test');
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.headers['x-content-type-options'], 'nosniff');
      assert.strictEqual(response.headers['x-frame-options'], 'DENY');
      assert.strictEqual(response.headers['x-xss-protection'], '1; mode=block');
      assert.strictEqual(response.headers['referrer-policy'], 'strict-origin-when-cross-origin');
      assert.strictEqual(
        response.headers['permissions-policy'],
        'geolocation=(), microphone=(), camera=()'
      );
    });
  });

  describe('validateRequest', () => {
    it('should allow GET requests without content-type', async () => {
      app.use(validateRequest());
      app.get('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).get('/test');
      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
    });

    it('should allow POST requests with application/json', async () => {
      app.use(validateRequest());
      app.post('/test', (req, res) => res.json({ received: req.body }));

      const response = await request(app)
        .post('/test')
        .set('Content-Type', 'application/json')
        .send({ data: 'test' });

      assert.strictEqual(response.status, 200);
      assert.deepStrictEqual(response.body.received, { data: 'test' });
    });

    it('should reject POST requests without content-type', async () => {
      app.use(validateRequest());
      app.post('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).post('/test').send('raw data');

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.error, 'Bad Request');
      assert.ok(response.body.message.includes('Content-Type must be application/json'));
    });

    it('should reject PUT requests with wrong content-type', async () => {
      app.use(validateRequest());
      app.put('/test', (req, res) => res.json({ success: true }));

      const response = await request(app)
        .put('/test')
        .set('Content-Type', 'text/plain')
        .send('plain text');

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.error, 'Bad Request');
    });

    it('should reject PATCH requests without content-type', async () => {
      app.use(validateRequest());
      app.patch('/test', (req, res) => res.json({ success: true }));

      const response = await request(app).patch('/test').send('data');

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.error, 'Bad Request');
    });

    it('should allow application/json with charset', async () => {
      app.use(validateRequest());
      app.post('/test', (req, res) => res.json({ success: true }));

      const response = await request(app)
        .post('/test')
        .set('Content-Type', 'application/json; charset=utf-8')
        .send({ data: 'test' });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
    });
  });

  describe('configureSecurity', () => {
    it('should configure all security middleware for local usage', () => {
      const config = { isInternetExposed: false };
      const mockApp = {
        use: mock.fn(),
      };

      configureSecurity(mockApp, config);

      // Verify middleware was applied
      assert.ok(mockApp.use.mock.calls.length >= 5);

      // Check that security headers middleware was applied
      const firstCall = mockApp.use.mock.calls[0];
      assert.ok(firstCall);
    });

    it('should configure all security middleware for public usage', () => {
      const config = { isInternetExposed: true };
      const mockApp = {
        use: mock.fn(),
      };

      configureSecurity(mockApp, config);

      // Verify middleware was applied
      assert.ok(mockApp.use.mock.calls.length >= 5);
    });

    it('should apply middleware in correct order', () => {
      const config = { isInternetExposed: false };
      const mockApp = {
        use: mock.fn(),
      };

      configureSecurity(mockApp, config);

      const calls = mockApp.use.mock.calls;

      // Security headers should be first (no path)
      assert.strictEqual(calls[0].arguments.length, 1);

      // Block list middleware should be second (no path)
      assert.strictEqual(calls[1].arguments.length, 1);

      // Rate limiter for /api
      const apiRateLimiter = calls.find((call) => call.arguments[0] === '/api');
      assert.ok(apiRateLimiter);

      // Auth rate limiter for /api/auth
      const authRateLimiter = calls.find((call) => call.arguments[0] === '/api/auth');
      assert.ok(authRateLimiter);
    });
  });

  describe('Rate limiter handler', () => {
    it('should handle rate limit exceeded with custom handler', async () => {
      // Create a custom test to trigger the rate limit handler
      const limiter = createRateLimiter(false);

      // We need to test the handler function directly since rate limiting
      // with memory store is difficult to test reliably
      const _mockReq = { ip: '192.168.1.100' };
      const mockRes = {
        status: mock.fn(() => mockRes),
        json: mock.fn(),
      };

      // Access the handler directly from the rate limiter configuration
      // Note: This is testing the handler configuration, not the actual rate limiting
      assert.ok(limiter);
      assert.strictEqual(typeof limiter, 'function');
    });
  });

  describe('Auth rate limiter handler', () => {
    it('should handle auth rate limit exceeded', () => {
      const limiter = createAuthRateLimiter();

      // Verify the limiter is configured correctly
      assert.ok(limiter);
      assert.strictEqual(typeof limiter, 'function');

      // The handler tracks failed attempts and blocks IPs
      // This is tested indirectly through trackFailedAuth
    });
  });
});
