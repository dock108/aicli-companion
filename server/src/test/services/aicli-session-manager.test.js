import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { AICLISessionManager } from '../../services/aicli-session-manager.js';
import { EventEmitter } from 'events';

describe('AICLISessionManager', () => {
  let sessionManager;

  beforeEach(() => {
    sessionManager = new AICLISessionManager({
      sessionTimeout: 1000, // Short timeout for testing
      sessionWarningTime: 800,
      minTimeoutCheckInterval: 100,
      maxConcurrentSessions: 5,
      maxMemoryPerSession: 1024 * 1024,
      maxTotalMemory: 5 * 1024 * 1024,
    });
  });

  afterEach(async () => {
    // Clean up any active sessions and timers
    if (sessionManager) {
      await sessionManager.shutdown();
    }
  });

  describe('Constructor', () => {
    it('should initialize with correct data structures', () => {
      assert.ok(sessionManager);
      assert.ok(sessionManager.activeSessions instanceof Map);
      assert.ok(sessionManager.sessionMessageBuffers instanceof Map);
      assert.ok(sessionManager.interactiveSessions instanceof Map);
      assert.ok(sessionManager.claudeSessions instanceof Map);
      assert.ok(sessionManager.projectSessions instanceof Map);
      assert.strictEqual(sessionManager.activeSessions.size, 0);
    });

    it('should set configuration options', () => {
      assert.strictEqual(sessionManager.sessionTimeout, 1000);
      assert.strictEqual(sessionManager.sessionWarningTime, 800);
      assert.strictEqual(sessionManager.maxConcurrentSessions, 5);
      assert.strictEqual(sessionManager.maxMemoryPerSession, 1024 * 1024);
    });

    it('should use default values when no options provided', async () => {
      const defaultManager = new AICLISessionManager();
      assert.strictEqual(defaultManager.sessionTimeout, 24 * 60 * 60 * 1000);
      assert.strictEqual(defaultManager.maxConcurrentSessions, 10);
      await defaultManager.shutdown();
    });

    it('should start session monitoring', () => {
      assert.ok(sessionManager.monitoringInterval);
    });
  });

  describe('trackSessionForRouting', () => {
    it('should track session for routing', async () => {
      await sessionManager.trackSessionForRouting('test-session', '/test/dir');

      assert.ok(sessionManager.claudeSessions.has('test-session'));
      assert.strictEqual(sessionManager.projectSessions.get('/test/dir'), 'test-session');
    });

    it('should handle null sessionId', async () => {
      await sessionManager.trackSessionForRouting(null, '/test/dir');
      assert.strictEqual(sessionManager.claudeSessions.size, 0);
    });

    it('should update lastActivity', async () => {
      await sessionManager.trackSessionForRouting('test-session', '/test/dir');
      const session = sessionManager.claudeSessions.get('test-session');

      assert.ok(session);
      assert.ok(session.lastActivity);
    });
  });

  describe('updateClaudeSessionActivity', () => {
    it('should update session activity', async () => {
      await sessionManager.trackSessionForRouting('test-session', '/test/dir');
      const initialActivity = sessionManager.claudeSessions.get('test-session').lastActivity;

      // Wait a bit to ensure time difference
      await new Promise((resolve) => setTimeout(resolve, 10));

      sessionManager.updateClaudeSessionActivity('test-session');
      const updatedActivity = sessionManager.claudeSessions.get('test-session').lastActivity;

      assert.ok(updatedActivity > initialActivity);
    });

    it('should handle non-existent session', () => {
      // Should not throw
      assert.doesNotThrow(() => {
        sessionManager.updateClaudeSessionActivity('non-existent');
      });
    });
  });

  describe('getSessionByProjectPath', () => {
    it('should get session by project path', async () => {
      await sessionManager.trackSessionForRouting('test-session', '/test/dir');

      const sessionId = sessionManager.getSessionByProjectPath('/test/dir');
      assert.strictEqual(sessionId, 'test-session');
    });

    it('should return null for unknown path', () => {
      const sessionId = sessionManager.getSessionByProjectPath('/unknown/dir');
      assert.strictEqual(sessionId, null);
    });
  });

  describe('getClaudeSessionInfo', () => {
    it('should get Claude session info', async () => {
      await sessionManager.trackSessionForRouting('test-session', '/test/dir');

      const info = sessionManager.getClaudeSessionInfo('test-session');
      assert.ok(info);
      assert.strictEqual(info.workingDirectory, '/test/dir');
      assert.ok(info.lastActivity);
      assert.strictEqual(info.expired, false);
    });

    it('should return null for non-existent session', () => {
      const info = sessionManager.getClaudeSessionInfo('non-existent');
      assert.strictEqual(info, null);
    });
  });

  describe('cleanupExpiredClaudeSessions', () => {
    it('should cleanup expired sessions', async () => {
      await sessionManager.trackSessionForRouting('expired-session', '/test/dir');

      // Mark as expired
      const session = sessionManager.claudeSessions.get('expired-session');
      session.expired = true;

      sessionManager.cleanupExpiredClaudeSessions();

      assert.strictEqual(sessionManager.claudeSessions.has('expired-session'), false);
      assert.strictEqual(sessionManager.projectSessions.has('/test/dir'), false);
    });

    it('should not cleanup active sessions', async () => {
      await sessionManager.trackSessionForRouting('active-session', '/test/dir');

      sessionManager.cleanupExpiredClaudeSessions();

      assert.strictEqual(sessionManager.claudeSessions.has('active-session'), true);
    });
  });

  describe('createInteractiveSession', () => {
    it('should create interactive session', async () => {
      const result = await sessionManager.createInteractiveSession(
        'new-session',
        'Hello Claude',
        '/test/dir'
      );

      assert.ok(result);
      assert.strictEqual(result.sessionId, 'new-session');
      assert.strictEqual(result.success, true);
      assert.ok(sessionManager.activeSessions.has('new-session'));
    });

    it('should reuse existing session for same directory', async () => {
      // Create first session
      await sessionManager.createInteractiveSession('session1', 'Hello', '/test/dir');

      // Try to create another for same directory
      const result = await sessionManager.createInteractiveSession(
        'session2',
        'Hello again',
        '/test/dir'
      );

      assert.strictEqual(result.reused, true);
      assert.strictEqual(result.sessionId, 'session1');
    });

    it('should set skip permissions option', async () => {
      const _result = await sessionManager.createInteractiveSession(
        'perm-session',
        'Hello',
        '/test/dir',
        { skipPermissions: true }
      );

      const session = sessionManager.activeSessions.get('perm-session');
      assert.strictEqual(session.skipPermissions, true);
    });
  });

  describe('closeSession', () => {
    it('should close existing session', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      const result = await sessionManager.closeSession('test-session');

      assert.strictEqual(result.success, true);
      assert.strictEqual(sessionManager.activeSessions.has('test-session'), false);
      assert.strictEqual(sessionManager.sessionMessageBuffers.has('test-session'), false);
    });

    it('should handle non-existent session', async () => {
      const result = await sessionManager.closeSession('non-existent');

      assert.strictEqual(result.success, false);
      assert.ok(result.message.includes('not found'));
    });

    it('should emit sessionCleaned event', async (_context) => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      let eventEmitted = false;
      sessionManager.once('sessionCleaned', (data) => {
        eventEmitted = true;
        assert.strictEqual(data.sessionId, 'test-session');
        assert.strictEqual(data.reason, 'user_requested');
      });

      await sessionManager.closeSession('test-session');
      assert.ok(eventEmitted);
    });
  });

  describe('hasSession', () => {
    it('should return true for existing session', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      assert.strictEqual(sessionManager.hasSession('test-session'), true);
    });

    it('should return false for non-existent session', () => {
      assert.strictEqual(sessionManager.hasSession('non-existent'), false);
    });
  });

  describe('getSessionStatus', () => {
    it('should get status for interactive session', () => {
      // Add an interactive session
      sessionManager.interactiveSessions.set('test-session', {
        sessionId: 'test-session',
        createdAt: Date.now() - 1000,
        lastActivity: Date.now(),
        messageCount: 5,
        workingDirectory: '/test/dir',
        pid: 12345,
      });

      const status = sessionManager.getSessionStatus('test-session');

      assert.ok(status);
      assert.strictEqual(status.sessionId, 'test-session');
      assert.strictEqual(status.active, true);
      assert.strictEqual(status.messageCount, 5);
      assert.ok(status.timeRemaining > 0);
    });

    it('should return null for non-existent session', () => {
      const status = sessionManager.getSessionStatus('non-existent');
      assert.strictEqual(status, null);
    });
  });

  describe('keepSessionAlive', () => {
    it('should reset session timeout', () => {
      const now = Date.now();
      sessionManager.interactiveSessions.set('test-session', {
        sessionId: 'test-session',
        createdAt: now - 5000,
        warningsSent: ['20hr'],
      });

      const result = sessionManager.keepSessionAlive('test-session');

      assert.strictEqual(result, true);
      const session = sessionManager.interactiveSessions.get('test-session');
      assert.ok(session.createdAt >= now);
      assert.strictEqual(session.warningsSent.length, 0);
    });

    it('should return false for non-existent session', () => {
      const result = sessionManager.keepSessionAlive('non-existent');
      assert.strictEqual(result, false);
    });
  });

  describe('getSessionBuffer and setSessionBuffer', () => {
    it('should get and set session buffer', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      const buffer = sessionManager.getSessionBuffer('test-session');
      assert.ok(buffer);

      // Modify buffer
      buffer.testData = 'test';

      // Set it back
      sessionManager.setSessionBuffer('test-session', buffer);

      const retrievedBuffer = sessionManager.getSessionBuffer('test-session');
      assert.strictEqual(retrievedBuffer.testData, 'test');
    });

    it('should return undefined for non-existent session', () => {
      const buffer = sessionManager.getSessionBuffer('non-existent');
      assert.strictEqual(buffer, undefined);
    });
  });

  describe('storeMessage', () => {
    it('should store message in session buffer', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      const message = sessionManager.storeMessage(
        'test-session',
        'msg-123',
        'Test message content',
        { type: 'user' }
      );

      assert.ok(message);
      assert.strictEqual(message.id, 'msg-123');
      assert.strictEqual(message.content, 'Test message content');

      const buffer = sessionManager.getSessionBuffer('test-session');
      assert.ok(buffer.messagesById.has('msg-123'));
    });

    it('should schedule message expiry', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      sessionManager.storeMessage('test-session', 'msg-123', 'Test', {});

      assert.ok(sessionManager.messageExpiryTimeouts);
      assert.ok(sessionManager.messageExpiryTimeouts.has('test-session'));
    });
  });

  describe('getSessionMessages', () => {
    it('should get paginated messages', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      // Store some messages
      for (let i = 0; i < 10; i++) {
        sessionManager.storeMessage('test-session', `msg-${i}`, `Message content ${i}`, {
          type: 'user',
        });
      }

      const result = sessionManager.getSessionMessages('test-session', 5, 0);

      assert.strictEqual(result.messages.length, 5);
      assert.strictEqual(result.total, 10);
      assert.strictEqual(result.hasMore, true);
    });

    it('should return empty for non-existent session', () => {
      const result = sessionManager.getSessionMessages('non-existent');

      assert.strictEqual(result.messages.length, 0);
      assert.strictEqual(result.total, 0);
    });
  });

  describe('clearSessionBuffer', () => {
    it('should clear session buffer', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      // Add some data to buffer
      const buffer = sessionManager.getSessionBuffer('test-session');
      buffer.assistantMessages = ['msg1', 'msg2'];

      sessionManager.clearSessionBuffer('test-session');

      const clearedBuffer = sessionManager.getSessionBuffer('test-session');
      assert.deepStrictEqual(clearedBuffer.assistantMessages, []);
    });
  });

  describe('checkSessionTimeouts', () => {
    it('should emit warning for sessions approaching timeout', async () => {
      // Add a Claude session close to timeout
      sessionManager.claudeSessions.set('test-session', {
        sessionId: 'test-session',
        lastActivity: Date.now() - 20 * 60 * 60 * 1000, // 20 hours ago
        workingDirectory: '/test/dir',
      });

      let warningEmitted = false;
      sessionManager.once('sessionWarning', (data) => {
        warningEmitted = true;
        assert.strictEqual(data.sessionId, 'test-session');
        assert.strictEqual(data.type, 'timeout');
      });

      await sessionManager.checkSessionTimeouts();
      assert.ok(warningEmitted);
    });

    it('should mark expired sessions', async () => {
      // Add an expired session
      sessionManager.claudeSessions.set('expired-session', {
        sessionId: 'expired-session',
        lastActivity: Date.now() - 25 * 60 * 60 * 1000, // 25 hours ago
        workingDirectory: '/test/dir',
      });

      await sessionManager.checkSessionTimeouts();

      const session = sessionManager.claudeSessions.get('expired-session');
      assert.strictEqual(session.expired, true);
    });
  });

  describe('checkResourceUsage', () => {
    it('should emit warning for session limit', async () => {
      // Add sessions up to the limit
      for (let i = 0; i < 5; i++) {
        sessionManager.interactiveSessions.set(`session-${i}`, {
          sessionId: `session-${i}`,
          pid: 1000 + i,
        });
      }

      let warningEmitted = false;
      sessionManager.once('resourceWarning', (data) => {
        warningEmitted = true;
        assert.strictEqual(data.type, 'session_limit');
      });

      await sessionManager.checkResourceUsage();
      assert.ok(warningEmitted);
    });
  });

  describe('cleanupDeadSession', () => {
    it('should cleanup dead session', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      await sessionManager.cleanupDeadSession('test-session');

      assert.strictEqual(sessionManager.activeSessions.has('test-session'), false);
      assert.strictEqual(sessionManager.sessionMessageBuffers.has('test-session'), false);
    });

    it('should emit sessionCleaned event', async () => {
      await sessionManager.createInteractiveSession('test-session', 'Hello', '/test/dir');

      let eventEmitted = false;
      sessionManager.once('sessionCleaned', (data) => {
        eventEmitted = true;
        assert.strictEqual(data.reason, 'process_died');
      });

      await sessionManager.cleanupDeadSession('test-session');
      assert.ok(eventEmitted);
    });
  });

  describe('shutdown', () => {
    it('should close all sessions and clear data', async () => {
      // Create multiple sessions
      await sessionManager.createInteractiveSession('session1', 'Hello', '/dir1');
      await sessionManager.createInteractiveSession('session2', 'Hello', '/dir2');
      await sessionManager.trackSessionForRouting('claude-session', '/dir3');

      await sessionManager.shutdown();

      assert.strictEqual(sessionManager.activeSessions.size, 0);
      assert.strictEqual(sessionManager.sessionMessageBuffers.size, 0);
      assert.strictEqual(sessionManager.claudeSessions.size, 0);
      assert.strictEqual(sessionManager.projectSessions.size, 0);
      assert.strictEqual(sessionManager.monitoringInterval, null);
    });
  });

  describe('killSession', () => {
    it('should kill interactive session', async () => {
      // Add an interactive session
      sessionManager.interactiveSessions.set('test-session', {
        sessionId: 'test-session',
        process: { kill: () => true },
        pid: 12345,
      });

      const result = await sessionManager.killSession('test-session');

      assert.strictEqual(result.success, true);
      assert.strictEqual(sessionManager.interactiveSessions.has('test-session'), false);
    });

    it('should return false for non-existent session', async () => {
      const result = await sessionManager.killSession('non-existent');
      assert.strictEqual(result.success, false);
    });
  });

  describe('Stateless methods', () => {
    it('getPersistenceStats should return zeros', () => {
      const stats = sessionManager.getPersistenceStats();
      assert.strictEqual(stats.sessions, 0);
      assert.strictEqual(stats.buffers, 0);
      assert.strictEqual(stats.totalSize, 0);
    });

    it('exportSessions should return empty array', async () => {
      const sessions = await sessionManager.exportSessions();
      assert.deepStrictEqual(sessions, []);
    });

    it('cleanupOldSessions should return zero cleaned', async () => {
      const result = await sessionManager.cleanupOldSessions(1000);
      assert.strictEqual(result.cleaned, 0);
    });

    it('reconcileSessionState should return stateless response', async () => {
      const result = await sessionManager.reconcileSessionState();
      assert.strictEqual(result.totalPersisted, 0);
      assert.strictEqual(result.staleRemoved, 0);
      assert.ok(result.activeInMemory >= 0);
    });
  });

  describe('EventEmitter functionality', () => {
    it('should inherit from EventEmitter', () => {
      assert.ok(sessionManager instanceof EventEmitter);
    });

    it('should emit and handle events', (done) => {
      sessionManager.once('test-event', (data) => {
        assert.strictEqual(data, 'test-data');
        done();
      });

      sessionManager.emit('test-event', 'test-data');
    });
  });
});
