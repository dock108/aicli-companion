import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { SessionMonitor } from '../../../services/aicli-session-manager/session-monitor.js';
import EventEmitter from 'events';

describe('SessionMonitor', () => {
  let monitor;
  let mockStorage;
  let config;
  let eventEmitter;
  let originalEnv;
  let mockMessageQueueManager;

  beforeEach(() => {
    originalEnv = process.env.NODE_ENV;
    delete process.env.NODE_ENV;

    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});
    mock.method(console, 'info', () => {});
    mock.method(console, 'warn', () => {});

    // Create mock storage
    mockStorage = {
      claudeSessions: new Map(),
      activeSessions: new Map(),

      getAllClaudeSessions: mock.fn(() => mockStorage.claudeSessions),
      getAllActiveSessions: mock.fn(() => mockStorage.activeSessions),
      getSession: mock.fn((id) => mockStorage.activeSessions.get(id)),
      removeClaudeSession: mock.fn((id) => mockStorage.claudeSessions.delete(id)),
      removeActiveSession: mock.fn((id) => mockStorage.activeSessions.delete(id)),
      removeMessageBuffer: mock.fn(),
    };

    // Create config
    config = {
      sessionTimeout: 24 * 60 * 60 * 1000, // 24 hours
      sessionWarningTime: 20 * 60 * 60 * 1000, // 20 hours
      minTimeoutCheckInterval: 60 * 1000, // 1 minute
    };

    // Create event emitter
    eventEmitter = new EventEmitter();

    // Mock message queue manager
    mockMessageQueueManager = {
      getQueueStatus: mock.fn(() => null),
      removeQueue: mock.fn(),
    };

    // Create monitor instance
    monitor = new SessionMonitor(mockStorage, config, eventEmitter);

    // Mock the messageQueueManager import
    monitor.messageQueueManager = mockMessageQueueManager;
  });

  afterEach(() => {
    monitor.stop();
    process.env.NODE_ENV = originalEnv;
    mock.restoreAll();
  });

  describe('start', () => {
    it('should start monitoring with interval', () => {
      monitor.start();
      assert(monitor.monitoringInterval);
      monitor.stop();
    });

    it('should skip monitoring in test environment', () => {
      process.env.NODE_ENV = 'test';
      monitor.start();
      assert.strictEqual(monitor.monitoringInterval, null);
    });

    it('should set proper interval timing', () => {
      monitor.start();
      assert(monitor.monitoringInterval);
      // Verify it's an interval (has _idleTimeout property)
      assert(monitor.monitoringInterval._idleTimeout);
      monitor.stop();
    });
  });

  describe('stop', () => {
    it('should stop monitoring and clear interval', () => {
      monitor.start();
      const interval = monitor.monitoringInterval;
      monitor.stop();

      assert.strictEqual(monitor.monitoringInterval, null);
      assert(interval);
    });

    it('should handle stop when not started', () => {
      monitor.stop();
      assert.strictEqual(monitor.monitoringInterval, null);
    });

    it('should be idempotent', () => {
      monitor.start();
      monitor.stop();
      monitor.stop();
      assert.strictEqual(monitor.monitoringInterval, null);
    });
  });

  describe('checkSessionTimeouts', () => {
    it('should emit warning for sessions approaching timeout', async () => {
      const now = Date.now();
      const sessionData = {
        lastActivity: now - 21 * 60 * 60 * 1000, // 21 hours ago
        warningsSent: [],
      };
      mockStorage.claudeSessions.set('session1', sessionData);

      let warningEmitted = false;
      eventEmitter.on('sessionWarning', (data) => {
        warningEmitted = true;
        assert.strictEqual(data.sessionId, 'session1');
        assert.strictEqual(data.type, 'timeout');
      });

      await monitor.checkSessionTimeouts();

      assert(warningEmitted);
      assert(sessionData.warningsSent.includes('timeout_warning'));
    });

    it('should not send duplicate warnings', async () => {
      const now = Date.now();
      const sessionData = {
        lastActivity: now - 21 * 60 * 60 * 1000,
        warningsSent: ['timeout_warning'],
      };
      mockStorage.claudeSessions.set('session1', sessionData);

      let warningCount = 0;
      eventEmitter.on('sessionWarning', () => {
        warningCount++;
      });

      await monitor.checkSessionTimeouts();
      assert.strictEqual(warningCount, 0);
    });

    it('should mark sessions as expired after timeout', async () => {
      const now = Date.now();
      const sessionData = {
        lastActivity: now - 25 * 60 * 60 * 1000, // 25 hours ago
        expired: false,
      };
      mockStorage.claudeSessions.set('session1', sessionData);

      let expiredEmitted = false;
      eventEmitter.on('sessionExpired', (data) => {
        expiredEmitted = true;
        assert.strictEqual(data.sessionId, 'session1');
        assert.strictEqual(data.reason, 'inactivity_timeout');
      });

      await monitor.checkSessionTimeouts();

      assert(expiredEmitted);
      assert.strictEqual(sessionData.expired, true);
    });

    it('should not re-expire already expired sessions', async () => {
      const now = Date.now();
      const sessionData = {
        lastActivity: now - 25 * 60 * 60 * 1000,
        expired: true,
      };
      mockStorage.claudeSessions.set('session1', sessionData);

      let expiredCount = 0;
      eventEmitter.on('sessionExpired', () => {
        expiredCount++;
      });

      await monitor.checkSessionTimeouts();
      assert.strictEqual(expiredCount, 0);
    });

    it('should check active session timeouts', async () => {
      const now = Date.now();
      const activeSession = {
        lastTimeoutCheck: now - 2 * 60 * 1000, // 2 minutes ago
        timeoutId: 'timeout123',
        lastActivity: now - 25 * 60 * 60 * 1000, // 25 hours ago
        createdAt: now - 26 * 60 * 60 * 1000,
      };
      mockStorage.activeSessions.set('active1', activeSession);

      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => ({
        queue: [],
      }));

      await monitor.checkSessionTimeouts();

      assert(activeSession.lastTimeoutCheck > now - 1000);
    });

    it('should skip timeout check if checked recently', async () => {
      const now = Date.now();
      const activeSession = {
        lastTimeoutCheck: now - 30000, // 30 seconds ago
        timeoutId: 'timeout123',
      };
      mockStorage.activeSessions.set('active1', activeSession);

      const originalTime = activeSession.lastTimeoutCheck;
      await monitor.checkSessionTimeouts();

      assert.strictEqual(activeSession.lastTimeoutCheck, originalTime);
    });

    it('should handle sessions without lastActivity', async () => {
      const sessionData = {
        warningsSent: [],
      };
      mockStorage.claudeSessions.set('session1', sessionData);

      await monitor.checkSessionTimeouts();

      // Should treat as expired (NaN - now > timeout)
      assert(sessionData.expired);
    });

    it('should initialize warningsSent array if missing', async () => {
      const now = Date.now();
      const sessionData = {
        lastActivity: now - 21 * 60 * 60 * 1000,
      };
      mockStorage.claudeSessions.set('session1', sessionData);

      await monitor.checkSessionTimeouts();

      assert(Array.isArray(sessionData.warningsSent));
      assert(sessionData.warningsSent.includes('timeout_warning'));
    });
  });

  describe('checkTimeout', () => {
    it('should trigger timeout for inactive session without messages', () => {
      const session = {
        createdAt: Date.now() - 25 * 60 * 60 * 1000,
        lastActivity: Date.now() - 25 * 60 * 60 * 1000,
        timeoutId: 'timeout123',
      };
      mockStorage.activeSessions.set('session1', session);

      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => ({
        queue: [],
      }));

      let timeoutEmitted = false;
      eventEmitter.on('sessionTimeout', (data) => {
        timeoutEmitted = true;
        assert.strictEqual(data.sessionId, 'session1');
        assert.strictEqual(data.reason, 'inactivity');
      });

      monitor.checkTimeout('session1');

      assert(timeoutEmitted);
      assert(mockStorage.removeActiveSession.mock.callCount() === 1);
      assert(mockMessageQueueManager.removeQueue.mock.callCount() === 1);
    });

    it('should not timeout session with pending messages', () => {
      const session = {
        createdAt: Date.now() - 25 * 60 * 60 * 1000,
        lastActivity: Date.now() - 25 * 60 * 60 * 1000,
      };
      mockStorage.activeSessions.set('session1', session);

      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => ({
        queue: ['message1', 'message2'],
      }));

      let timeoutEmitted = false;
      eventEmitter.on('sessionTimeout', () => {
        timeoutEmitted = true;
      });

      monitor.checkTimeout('session1');

      assert(!timeoutEmitted);
      assert(mockStorage.removeActiveSession.mock.callCount() === 0);
    });

    it('should handle non-existent session', () => {
      monitor.checkTimeout('nonexistent');
      assert(mockStorage.removeActiveSession.mock.callCount() === 0);
    });

    it('should use createdAt if lastActivity is not set', () => {
      const session = {
        createdAt: Date.now() - 25 * 60 * 60 * 1000,
      };
      mockStorage.activeSessions.set('session1', session);

      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => null);

      monitor.checkTimeout('session1');
      assert(mockStorage.removeActiveSession.mock.callCount() === 1);
    });

    it('should not timeout recent sessions', () => {
      const session = {
        createdAt: Date.now() - 1 * 60 * 60 * 1000, // 1 hour ago
        lastActivity: Date.now() - 30 * 60 * 1000, // 30 minutes ago
      };
      mockStorage.activeSessions.set('session1', session);

      let timeoutEmitted = false;
      eventEmitter.on('sessionTimeout', () => {
        timeoutEmitted = true;
      });

      monitor.checkTimeout('session1');

      assert(!timeoutEmitted);
      assert(mockStorage.removeActiveSession.mock.callCount() === 0);
    });
  });

  describe('checkPendingMessages', () => {
    it('should return true when queue has messages', () => {
      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => ({
        queue: ['message1'],
      }));

      const result = monitor.checkPendingMessages('session1');
      assert.strictEqual(result, true);
    });

    it('should return false when queue is empty', () => {
      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => ({
        queue: [],
      }));

      const result = monitor.checkPendingMessages('session1');
      assert.strictEqual(result, false);
    });

    it('should return false when no queue status', () => {
      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => null);

      const result = monitor.checkPendingMessages('session1');
      assert.strictEqual(result, false);
    });

    it('should return false for undefined queue', () => {
      mockMessageQueueManager.getQueueStatus.mock.mockImplementation(() => ({
        queue: undefined,
      }));

      const result = monitor.checkPendingMessages('session1');
      assert.strictEqual(result, false);
    });
  });

  describe('cleanupExpiredClaudeSessions', () => {
    it('should remove sessions expired more than 1 hour ago', () => {
      const now = Date.now();

      // Expired > 1 hour ago
      mockStorage.claudeSessions.set('expired1', {
        expired: true,
        lastActivity: now - 26 * 60 * 60 * 1000, // 26 hours ago
      });

      // Expired recently
      mockStorage.claudeSessions.set('expired2', {
        expired: true,
        lastActivity: now - 24.5 * 60 * 60 * 1000, // 24.5 hours ago
      });

      // Not expired
      mockStorage.claudeSessions.set('active1', {
        expired: false,
        lastActivity: now - 20 * 60 * 60 * 1000,
      });

      monitor.cleanupExpiredClaudeSessions();

      assert(
        mockStorage.removeClaudeSession.mock.calls.some((call) => call.arguments[0] === 'expired1')
      );
      assert(
        !mockStorage.removeClaudeSession.mock.calls.some((call) => call.arguments[0] === 'expired2')
      );
      assert(
        !mockStorage.removeClaudeSession.mock.calls.some((call) => call.arguments[0] === 'active1')
      );
    });

    it('should handle no expired sessions', () => {
      mockStorage.claudeSessions.set('active1', {
        expired: false,
        lastActivity: Date.now(),
      });

      monitor.cleanupExpiredClaudeSessions();
      assert.strictEqual(mockStorage.removeClaudeSession.mock.callCount(), 0);
    });

    it('should handle multiple expired sessions', () => {
      const now = Date.now();

      for (let i = 0; i < 5; i++) {
        mockStorage.claudeSessions.set(`expired${i}`, {
          expired: true,
          lastActivity: now - 30 * 60 * 60 * 1000,
        });
      }

      monitor.cleanupExpiredClaudeSessions();
      assert.strictEqual(mockStorage.removeClaudeSession.mock.callCount(), 5);
    });
  });

  describe('cleanupSessionResources', () => {
    it('should clear timeout and remove all session data', () => {
      const clearTimeoutSpy = mock.fn();
      global.clearTimeout = clearTimeoutSpy;

      const session = {
        timeoutId: 'timeout123',
      };
      mockStorage.activeSessions.set('session1', session);

      monitor.cleanupSessionResources('session1');

      assert(clearTimeoutSpy.mock.callCount() === 1);
      assert(mockStorage.removeActiveSession.mock.callCount() === 1);
      assert(mockStorage.removeMessageBuffer.mock.callCount() === 1);
      assert(mockMessageQueueManager.removeQueue.mock.callCount() === 1);
    });

    it('should handle session without timeout', () => {
      const session = {};
      mockStorage.activeSessions.set('session1', session);

      monitor.cleanupSessionResources('session1');

      assert(mockStorage.removeActiveSession.mock.callCount() === 1);
      assert(mockStorage.removeMessageBuffer.mock.callCount() === 1);
    });

    it('should handle non-existent session', () => {
      monitor.cleanupSessionResources('nonexistent');

      // Should still try to clean up
      assert(mockStorage.removeActiveSession.mock.callCount() === 1);
      assert(mockStorage.removeMessageBuffer.mock.callCount() === 1);
      assert(mockMessageQueueManager.removeQueue.mock.callCount() === 1);
    });

    it('should handle null session ID', () => {
      monitor.cleanupSessionResources(null);

      // Should still attempt cleanup
      assert(mockStorage.removeActiveSession.mock.callCount() === 1);
      assert(mockStorage.removeMessageBuffer.mock.callCount() === 1);
      assert(mockMessageQueueManager.removeQueue.mock.callCount() === 1);
    });
  });
});
