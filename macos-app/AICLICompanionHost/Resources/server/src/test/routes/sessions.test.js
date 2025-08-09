import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { mock } from 'node:test';
import sessionsRoutes from '../../routes/sessions.js';

describe('Sessions Routes', () => {
  let app;
  let mockAicliService;
  let mockSessionManager;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Create mock session manager
    mockSessionManager = {
      getAllSessions: mock.fn(() => [
        { sessionId: 'session-1', workingDirectory: '/path1', isActive: true },
        { sessionId: 'session-2', workingDirectory: '/path2', isActive: true },
      ]),
      getSessionStatus: mock.fn((sessionId) => {
        if (sessionId === 'test-session-123') {
          return {
            sessionId: 'test-session-123',
            workingDirectory: '/test/path',
            isActive: true,
            createdAt: Date.now(),
          };
        }
        return null;
      }),
      getSessionBuffer: mock.fn((sessionId) => {
        if (sessionId === 'test-session-123') {
          return {
            assistantMessages: ['Message 1', 'Message 2'],
          };
        }
        return null;
      }),
      cleanupDeadSession: mock.fn(() => Promise.resolve()),
      killSession: mock.fn((sessionId) => {
        if (sessionId === 'test-session-123') {
          return Promise.resolve(true);
        }
        return Promise.resolve(false);
      }),
      resetSessionTimeout: mock.fn(() => true),
      keepSessionAlive: mock.fn((sessionId) => {
        if (sessionId === 'test-session-123') {
          return true;
        }
        return false;
      }),
      getInteractiveSessions: mock.fn(() => [
        { sessionId: 'claude-1', status: 'active' },
        { sessionId: 'claude-2', status: 'idle' },
      ]),
      cleanupAllSessions: mock.fn(() => Promise.resolve({ cleaned: 2 })),
      cleanupExpiredClaudeSessions: mock.fn(() => 3),
      claudeSessions: new Map([
        [
          'claude-session-1',
          {
            lastActivity: Date.now() - 3600000, // 1 hour ago
            expired: false,
            warningsSent: [],
          },
        ],
        [
          'claude-session-2',
          {
            lastActivity: Date.now() - 7200000, // 2 hours ago
            expired: false,
            warningsSent: ['1h'],
          },
        ],
      ]),
    };

    // Create mock AICLI service as a plain object
    mockAicliService = {
      sessionManager: mockSessionManager,
    };

    app.set('aicliService', mockAicliService);
    app.use('/api/sessions', sessionsRoutes);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('GET /api/sessions', () => {
    it('should return list of active sessions', async () => {
      const response = await request(app).get('/api/sessions');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.sessions.length, 2);
      assert.strictEqual(response.body.count, 2);
    });
  });

  describe('GET /api/sessions/:sessionId/status', () => {
    it('should return session status when found', async () => {
      const response = await request(app).get('/api/sessions/test-session-123/status');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      // The route spreads ...status, so check individual properties
      assert.strictEqual(response.body.sessionId, 'test-session-123');
      assert.strictEqual(response.body.workingDirectory, '/test/path');
      assert.strictEqual(response.body.isActive, true);
      assert.strictEqual(response.body.hasNewMessages, true);
    });

    it('should return 404 when session not found', async () => {
      const response = await request(app).get('/api/sessions/non-existent/status');

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Session not found');
      assert.strictEqual(response.body.hasNewMessages, false);
    });
  });

  describe('DELETE /api/sessions/:sessionId', () => {
    it('should cleanup session successfully', async () => {
      const response = await request(app).delete('/api/sessions/test-session-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Session terminated');

      // Verify killSession was called
      assert.strictEqual(mockSessionManager.killSession.mock.calls.length, 1);
      assert.strictEqual(
        mockSessionManager.killSession.mock.calls[0].arguments[0],
        'test-session-123'
      );
    });

    it('should return 404 when session not found', async () => {
      const response = await request(app).delete('/api/sessions/non-existent');

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Session not found');
    });

    it('should handle cleanup errors', async () => {
      mockSessionManager.killSession = mock.fn(() => Promise.reject(new Error('Kill failed')));

      const response = await request(app).delete('/api/sessions/bad-session');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to terminate session');
    });
  });

  describe('POST /api/sessions/:sessionId/keepalive', () => {
    it('should reset session timeout successfully', async () => {
      const response = await request(app).post('/api/sessions/test-session-123/keepalive').send({});

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Session timeout reset');

      // Verify keepSessionAlive was called
      assert.strictEqual(mockSessionManager.keepSessionAlive.mock.calls.length, 1);
      assert.strictEqual(
        mockSessionManager.keepSessionAlive.mock.calls[0].arguments[0],
        'test-session-123'
      );
    });

    it('should return 404 when session not found', async () => {
      const response = await request(app).post('/api/sessions/non-existent/keepalive').send({});

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Session not found');
    });
  });

  describe('GET /api/sessions/claude', () => {
    it('should return interactive Claude sessions', async () => {
      const response = await request(app).get('/api/sessions/claude');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.sessions.length, 2);
      assert.strictEqual(response.body.sessions[0].sessionId, 'claude-session-1');
    });
  });

  describe('POST /api/sessions/claude/cleanup', () => {
    it('should cleanup all sessions', async () => {
      const response = await request(app).post('/api/sessions/claude/cleanup').send({});

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Cleaned up 3 expired Claude sessions');
      assert.strictEqual(response.body.cleanedCount, 3);

      // Verify cleanup was called
      assert.strictEqual(mockSessionManager.cleanupExpiredClaudeSessions.mock.calls.length, 1);
    });

    it('should handle cleanup errors', async () => {
      mockSessionManager.cleanupExpiredClaudeSessions = mock.fn(() => {
        throw new Error('Cleanup failed');
      });

      const response = await request(app).post('/api/sessions/claude/cleanup').send({});

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to cleanup expired sessions');
    });
  });
});
