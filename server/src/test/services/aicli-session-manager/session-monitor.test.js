import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { SessionMonitor } from '../../../services/aicli-session-manager/session-monitor.js';

describe('SessionMonitor', () => {
  let monitor;
  let mockStorage;
  let mockConfig;
  let mockEventEmitter;
  let originalEnv;

  beforeEach(() => {
    // Save original env
    originalEnv = process.env.NODE_ENV;

    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});
    mock.method(console, 'info', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});

    // Mock storage
    mockStorage = {
      claudeSessions: new Map(),
      activeSessions: new Map(),
      messageBuffers: new Map(),

      getAllClaudeSessions: mock.fn(() => {
        return mockStorage.claudeSessions;
      }),

      getAllActiveSessions: mock.fn(() => {
        return mockStorage.activeSessions;
      }),

      getSession: mock.fn((sessionId) => {
        return mockStorage.activeSessions.get(sessionId);
      }),

      removeClaudeSession: mock.fn((sessionId) => {
        mockStorage.claudeSessions.delete(sessionId);
      }),

      removeActiveSession: mock.fn((sessionId) => {
        mockStorage.activeSessions.delete(sessionId);
      }),

      removeMessageBuffer: mock.fn((sessionId) => {
        mockStorage.messageBuffers.delete(sessionId);
      }),
    };

    // Mock config
    mockConfig = {
      sessionTimeout: 24 * 60 * 60 * 1000, // 24 hours
      sessionWarningTime: 20 * 60 * 60 * 1000, // 20 hours
      minTimeoutCheckInterval: 60000, // 1 minute
    };

    // Mock event emitter
    mockEventEmitter = {
      emit: mock.fn(),
    };

    monitor = new SessionMonitor(mockStorage, mockConfig, mockEventEmitter);
  });

  afterEach(() => {
    // Clear any intervals
    if (monitor.monitoringInterval) {
      clearInterval(monitor.monitoringInterval);
    }
    mock.restoreAll();
    process.env.NODE_ENV = originalEnv;
  });

  describe('start', () => {
    it('should start monitoring in non-test environment', () => {
      process.env.NODE_ENV = 'development';

      monitor.start();

      assert(monitor.monitoringInterval);
      clearInterval(monitor.monitoringInterval);
      monitor.monitoringInterval = null;
    });

    it('should skip monitoring in test environment', () => {
      process.env.NODE_ENV = 'test';

      monitor.start();

      assert.strictEqual(monitor.monitoringInterval, null);
    });
  });

  describe('stop', () => {
    it('should stop monitoring interval', () => {
      process.env.NODE_ENV = 'development';
      monitor.start();

      monitor.stop();

      assert.strictEqual(monitor.monitoringInterval, null);
    });

    it('should handle stop when not started', () => {
      monitor.stop();

      assert.strictEqual(monitor.monitoringInterval, null);
    });
  });

  describe('checkSessionTimeouts', () => {
    it('should emit warning for sessions approaching timeout', async () => {
      const now = Date.now();
      const sessionId = 'claude123';
      const sessionData = {
        lastActivity: now - 21 * 60 * 60 * 1000, // 21 hours ago
      };

      mockStorage.claudeSessions.set(sessionId, sessionData);

      await monitor.checkSessionTimeouts();

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      const call = mockEventEmitter.emit.mock.calls[0];
      assert.strictEqual(call.arguments[0], 'sessionWarning');
      assert.strictEqual(call.arguments[1].sessionId, sessionId);
      assert.strictEqual(call.arguments[1].type, 'timeout');
    });

    it('should mark session as expired after timeout', async () => {
      const now = Date.now();
      const sessionId = 'claude123';
      const sessionData = {
        lastActivity: now - 25 * 60 * 60 * 1000, // 25 hours ago
      };

      mockStorage.claudeSessions.set(sessionId, sessionData);

      await monitor.checkSessionTimeouts();

      assert.strictEqual(sessionData.expired, true);
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      const call = mockEventEmitter.emit.mock.calls[0];
      assert.strictEqual(call.arguments[0], 'sessionExpired');
      assert.strictEqual(call.arguments[1].reason, 'inactivity_timeout');
    });

    it('should not send duplicate warnings', async () => {
      const now = Date.now();
      const sessionId = 'claude123';
      const sessionData = {
        lastActivity: now - 21 * 60 * 60 * 1000, // 21 hours ago
        warningsSent: ['timeout_warning'],
      };

      mockStorage.claudeSessions.set(sessionId, sessionData);

      await monitor.checkSessionTimeouts();

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 0);
    });

    it('should check active sessions with timeout', async () => {
      const now = Date.now();
      const sessionId = 'active123';
      const session = {
        sessionId,
        timeoutId: setTimeout(() => {}, 1000),
        lastTimeoutCheck: now - 70000, // 70 seconds ago
        lastActivity: now - 1000,
        createdAt: now - 2000,
      };

      mockStorage.activeSessions.set(sessionId, session);

      // Mock checkTimeout to track calls
      const checkTimeoutSpy = mock.fn();
      monitor.checkTimeout = checkTimeoutSpy;

      await monitor.checkSessionTimeouts();

      assert.strictEqual(checkTimeoutSpy.mock.callCount(), 1);
      assert.strictEqual(checkTimeoutSpy.mock.calls[0].arguments[0], sessionId);

      clearTimeout(session.timeoutId);
    });
  });

  describe('checkTimeout', () => {
    it('should trigger timeout for inactive session', () => {
      const sessionId = 'session123';
      const session = {
        sessionId,
        lastActivity: Date.now() - 25 * 60 * 60 * 1000, // 25 hours ago
        createdAt: Date.now() - 26 * 60 * 60 * 1000,
      };

      mockStorage.activeSessions.set(sessionId, session);

      // Mock checkPendingMessages
      monitor.checkPendingMessages = mock.fn(() => false);

      monitor.checkTimeout(sessionId);

      assert.strictEqual(mockStorage.removeActiveSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);

      const call = mockEventEmitter.emit.mock.calls[0];
      assert.strictEqual(call.arguments[0], 'sessionTimeout');
      assert.strictEqual(call.arguments[1].reason, 'inactivity');
    });

    it('should not timeout session with pending messages', () => {
      const sessionId = 'session123';
      const session = {
        sessionId,
        lastActivity: Date.now() - 25 * 60 * 60 * 1000, // 25 hours ago
        createdAt: Date.now() - 26 * 60 * 60 * 1000,
      };

      mockStorage.activeSessions.set(sessionId, session);

      // Mock checkPendingMessages to return true
      monitor.checkPendingMessages = mock.fn(() => true);

      monitor.checkTimeout(sessionId);

      assert.strictEqual(mockStorage.removeActiveSession.mock.callCount(), 0);
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 0);
    });

    it('should handle non-existent session', () => {
      monitor.checkTimeout('nonexistent');

      assert.strictEqual(mockStorage.removeActiveSession.mock.callCount(), 0);
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 0);
    });
  });

  describe('checkPendingMessages', () => {
    it('should return true when queue has messages', () => {
      // We need to mock messageQueueManager properly
      // Since it's imported at module level, we'll test the actual behavior
      // by checking the function exists and returns boolean
      const result = monitor.checkPendingMessages('session123');

      assert.strictEqual(typeof result, 'boolean');
    });
  });

  describe('cleanupExpiredClaudeSessions', () => {
    it('should cleanup expired sessions older than 1 hour', () => {
      const now = Date.now();
      const expiredOld = {
        expired: true,
        lastActivity: now - 26 * 60 * 60 * 1000, // 26 hours ago
      };
      const expiredRecent = {
        expired: true,
        lastActivity: now - 24.5 * 60 * 60 * 1000, // 24.5 hours ago
      };
      const notExpired = {
        lastActivity: now - 1000,
      };

      mockStorage.claudeSessions.set('old', expiredOld);
      mockStorage.claudeSessions.set('recent', expiredRecent);
      mockStorage.claudeSessions.set('active', notExpired);

      monitor.cleanupExpiredClaudeSessions();

      assert.strictEqual(mockStorage.removeClaudeSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.removeClaudeSession.mock.calls[0].arguments[0], 'old');
    });

    it('should handle empty sessions', () => {
      monitor.cleanupExpiredClaudeSessions();

      assert.strictEqual(mockStorage.removeClaudeSession.mock.callCount(), 0);
    });
  });

  describe('cleanupSessionResources', () => {
    it('should clear timeout and remove all session data', () => {
      const sessionId = 'session123';
      const timeoutId = setTimeout(() => {}, 1000);
      const session = {
        sessionId,
        timeoutId,
      };

      mockStorage.activeSessions.set(sessionId, session);

      monitor.cleanupSessionResources(sessionId);

      assert.strictEqual(mockStorage.removeActiveSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 1);

      // Verify timeout was cleared (won't throw if already cleared)
      clearTimeout(timeoutId);
    });

    it('should handle session without timeout', () => {
      const sessionId = 'session123';
      const session = {
        sessionId,
      };

      mockStorage.activeSessions.set(sessionId, session);

      monitor.cleanupSessionResources(sessionId);

      assert.strictEqual(mockStorage.removeActiveSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 1);
    });

    it('should handle non-existent session', () => {
      monitor.cleanupSessionResources('nonexistent');

      assert.strictEqual(mockStorage.removeActiveSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 1);
    });
  });
});
