import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { mock } from 'node:test';
import sessionsRoutes from '../../routes/sessions.js';

describe('Sessions Routes Coverage', () => {
  let app;
  let mockAicliService;
  let mockSessionManager;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Create mock session manager
    mockSessionManager = {
      getAllSessions: mock.fn(() => {
        throw new Error('Database error');
      }),
      claudeSessions: new Map([
        [
          'expired-session-1',
          {
            lastActivity: Date.now() - 25 * 60 * 60 * 1000, // 25 hours ago
            expired: true,
            warningsSent: ['1h', '12h', '23h'],
          },
        ],
      ]),
      isClaudeSessionExpired: mock.fn((sessionId) => {
        return sessionId === 'expired-session-1';
      }),
    };

    // Create mock AICLI service
    mockAicliService = {
      sessionManager: mockSessionManager,
    };

    app.set('aicliService', mockAicliService);
    app.use('/api/sessions', sessionsRoutes);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('GET /api/sessions - error handling', () => {
    it('should handle errors when getting sessions fails', async () => {
      const response = await request(app).get('/api/sessions');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to retrieve sessions');
    });
  });

  describe('GET /api/sessions/claude - error handling', () => {
    it('should handle errors when getting Claude sessions fails', async () => {
      // Make claudeSessions throw when accessed
      Object.defineProperty(mockSessionManager, 'claudeSessions', {
        get: () => {
          throw new Error('Map access error');
        },
        configurable: true,
      });

      const response = await request(app).get('/api/sessions/claude');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to retrieve Claude sessions');

      // Clean up property
      delete mockSessionManager.claudeSessions;
    });
  });

  describe('GET /api/sessions/:sessionId/expired', () => {
    it('should check if session is expired', async () => {
      const response = await request(app).get('/api/sessions/expired-session-1/expired');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.sessionId, 'expired-session-1');
      assert.strictEqual(response.body.expired, true);
      assert.strictEqual(response.body.tracked, true);
      assert.ok(response.body.lastActivity);
      assert.strictEqual(response.body.hoursInactive, 25);
      assert.strictEqual(response.body.hoursUntilExpiry, 0);
    });

    it('should handle non-tracked sessions', async () => {
      const response = await request(app).get('/api/sessions/unknown-session/expired');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.sessionId, 'unknown-session');
      assert.strictEqual(response.body.expired, false);
      assert.strictEqual(response.body.tracked, false);
      assert.strictEqual(
        response.body.message,
        'Session not being tracked (may be new or unknown)'
      );
    });

    it('should handle active sessions', async () => {
      mockSessionManager.claudeSessions.set('active-session', {
        lastActivity: Date.now() - 2 * 60 * 60 * 1000, // 2 hours ago
        expired: false,
        warningsSent: [],
      });
      mockSessionManager.isClaudeSessionExpired = mock.fn(() => false);

      const response = await request(app).get('/api/sessions/active-session/expired');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.expired, false);
      assert.strictEqual(response.body.tracked, true);
      assert.strictEqual(response.body.hoursInactive, 2);
      assert.strictEqual(response.body.hoursUntilExpiry, 22);
    });

    it('should handle errors when checking expiry', async () => {
      mockSessionManager.isClaudeSessionExpired = mock.fn(() => {
        throw new Error('Expiry check failed');
      });

      const response = await request(app).get('/api/sessions/error-session/expired');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to check session expiry');
    });
  });
});
