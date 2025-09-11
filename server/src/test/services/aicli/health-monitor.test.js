import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { HealthMonitor } from '../../../services/aicli/health-monitor.js';

describe('HealthMonitor', () => {
  let healthMonitor;
  let mockSessionManager;
  let mockEventEmitter;
  let originalEnv;

  beforeEach(() => {
    originalEnv = process.env.NODE_ENV;

    mockSessionManager = {
      activeSessions: new Map(),
      getActiveSessions: mock.fn(() => []),
      getSession: mock.fn(),
      cleanupDeadSession: mock.fn(),
      sessionTimeout: 24 * 60 * 60 * 1000, // 24 hours
    };

    mockEventEmitter = {
      emit: mock.fn(),
    };

    healthMonitor = new HealthMonitor(mockSessionManager, mockEventEmitter);
  });

  afterEach(() => {
    process.env.NODE_ENV = originalEnv;
    if (healthMonitor.processHealthCheckInterval) {
      healthMonitor.stopProcessHealthMonitoring();
    }
  });

  describe('constructor', () => {
    it('should initialize with session manager and event emitter', () => {
      assert.ok(healthMonitor.sessionManager);
      assert.ok(healthMonitor.emit);
      assert.equal(healthMonitor.processHealthCheckInterval, null);
    });
  });

  describe('startProcessHealthMonitoring', () => {
    it('should skip in test environment', () => {
      process.env.NODE_ENV = 'test';
      healthMonitor.startProcessHealthMonitoring();
      assert.equal(healthMonitor.processHealthCheckInterval, null);
    });

    it('should start monitoring in non-test environment', () => {
      process.env.NODE_ENV = 'production';
      healthMonitor.startProcessHealthMonitoring();
      assert.ok(healthMonitor.processHealthCheckInterval);
      healthMonitor.stopProcessHealthMonitoring();
    });
  });

  describe('stopProcessHealthMonitoring', () => {
    it('should clear the interval', () => {
      process.env.NODE_ENV = 'production';
      healthMonitor.startProcessHealthMonitoring();
      assert.ok(healthMonitor.processHealthCheckInterval);

      healthMonitor.stopProcessHealthMonitoring();
      assert.equal(healthMonitor.processHealthCheckInterval, null);
    });

    it('should handle stopping when not started', () => {
      assert.doesNotThrow(() => healthMonitor.stopProcessHealthMonitoring());
    });
  });

  describe('checkAllProcessHealth', () => {
    it('should handle empty sessions', async () => {
      await healthMonitor.checkAllProcessHealth();
      assert.equal(mockSessionManager.cleanupDeadSession.mock.calls.length, 0);
      assert.equal(mockEventEmitter.emit.mock.calls.length, 0);
    });

    it('should check sessions with processes', async () => {
      const session = {
        sessionId: 'test-session',
        process: { pid: 12345 },
      };
      mockSessionManager.activeSessions.set('test-session', session);

      // Mock processMonitor would need to be injected for full test
      // This is a simplified version
      await healthMonitor.checkAllProcessHealth();
    });

    it('should emit unhealthy session events', async () => {
      const session = {
        sessionId: 'unhealthy-session',
        process: { pid: 99999 }, // Non-existent process
      };
      mockSessionManager.activeSessions.set('unhealthy-session', session);

      await healthMonitor.checkAllProcessHealth();
      // Would need process monitor mock to fully test
    });
  });

  describe('checkSessionTimeout', () => {
    it('should detect timed out session', () => {
      const session = {
        sessionId: 'old-session',
        startTime: new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString(), // 25 hours ago
      };
      mockSessionManager.getSession = mock.fn(() => session);

      const result = healthMonitor.checkSessionTimeout('old-session');
      assert.equal(result.timedOut, true);
      assert.ok(result.reason.includes('inactive'));
    });

    it('should detect active session', () => {
      const session = {
        sessionId: 'active-session',
        lastActivity: new Date(Date.now() - 5 * 60 * 1000).toISOString(), // 5 minutes ago
      };
      mockSessionManager.getSession = mock.fn(() => session);

      const result = healthMonitor.checkSessionTimeout('active-session');
      assert.equal(result.timedOut, false);
      assert.ok(result.timeRemaining > 0);
    });

    it('should handle missing session', () => {
      mockSessionManager.getSession = mock.fn(() => null);

      const result = healthMonitor.checkSessionTimeout('missing-session');
      assert.equal(result.timedOut, true);
      assert.equal(result.reason, 'Session not found');
    });

    it('should use startTime if lastActivity is missing', () => {
      const session = {
        sessionId: 'new-session',
        startTime: new Date().toISOString(),
      };
      mockSessionManager.getSession = mock.fn(() => session);

      const result = healthMonitor.checkSessionTimeout('new-session');
      assert.equal(result.timedOut, false);
    });

    it('should handle missing timestamps', () => {
      const session = {
        sessionId: 'no-time-session',
      };
      mockSessionManager.getSession = mock.fn(() => session);

      const result = healthMonitor.checkSessionTimeout('no-time-session');
      assert.equal(result.timedOut, false);
    });
  });

  describe('healthCheck', () => {
    beforeEach(() => {
      healthMonitor.checkAvailability = mock.fn(async () => ({
        available: true,
        version: '1.0.0',
      }));
    });

    it('should check all health aspects', async () => {
      mockSessionManager.getActiveSessions = mock.fn(() => [
        {
          sessionId: 'session1',
          startTime: new Date().toISOString(),
          workingDirectory: '/test',
        },
      ]);

      const health = await healthMonitor.healthCheck();

      assert.equal(health.status, 'healthy');
      assert.equal(health.checks.aicli, true);
      assert.equal(health.checks.sessions, true);
      assert.equal(health.checks.memory, true);
      assert.ok(health.details.aicli);
      assert.ok(health.details.sessions);
      assert.ok(health.details.memory);
    });

    it('should detect unhealthy state', async () => {
      healthMonitor.checkAvailability = mock.fn(async () => ({
        available: false,
        error: 'Not found',
      }));

      const health = await healthMonitor.healthCheck();

      assert.equal(health.status, 'unhealthy');
      assert.equal(health.checks.aicli, false);
    });

    it('should handle checkAvailability errors', async () => {
      healthMonitor.checkAvailability = mock.fn(async () => {
        throw new Error('Check failed');
      });

      const health = await healthMonitor.healthCheck();

      assert.equal(health.checks.aicli, false);
      assert.equal(health.details.aicli.error, 'Check failed');
    });

    it('should check memory usage', async () => {
      const health = await healthMonitor.healthCheck();

      assert.ok(health.details.memory);
      assert.ok(health.details.memory.heapUsed);
      assert.ok(health.details.memory.rss);
    });
  });

  describe('setCheckAvailabilityFn', () => {
    it('should set the check availability function', () => {
      const mockFn = mock.fn();
      healthMonitor.setCheckAvailabilityFn(mockFn);
      assert.equal(healthMonitor.checkAvailability, mockFn);
    });
  });
});
