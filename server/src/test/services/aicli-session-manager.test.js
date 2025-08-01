import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { AICLISessionManager } from '../../services/aicli-session-manager.js';

// Mock session persistence
const mockSessionPersistence = {
  initialize: mock.fn(() => Promise.resolve()),
  getAllSessions: mock.fn(() => []),
  setSession: mock.fn(() => Promise.resolve()),
  updateSession: mock.fn(() => Promise.resolve()),
  removeSession: mock.fn(() => Promise.resolve()),
  getStats: mock.fn(() => ({ total: 0, size: 0 })),
  exportSessions: mock.fn(() => Promise.resolve([])),
  cleanup: mock.fn(() => Promise.resolve(0)),
};

// Mock the module
await mock.module('../../services/session-persistence.js', {
  namedExports: {
    sessionPersistence: mockSessionPersistence,
  },
});

// Mock AICLIMessageHandler
const mockMessageHandler = {
  createSessionBuffer: mock.fn(() => ({
    messages: [],
    assistantMessages: [],
    deliverables: [],
    pendingFinalResponse: null,
  })),
  clearSessionBuffer: mock.fn(),
};

await mock.module('../../services/aicli-message-handler.js', {
  namedExports: {
    AICLIMessageHandler: mockMessageHandler,
  },
});

describe('AICLISessionManager', () => {
  let sessionManager;
  let timeoutIds;

  beforeEach(() => {
    // Reset mocks
    mockSessionPersistence.initialize.mock.resetCalls();
    mockSessionPersistence.getAllSessions.mock.resetCalls();
    mockSessionPersistence.setSession.mock.resetCalls();
    mockSessionPersistence.updateSession.mock.resetCalls();
    mockSessionPersistence.removeSession.mock.resetCalls();
    mockMessageHandler.createSessionBuffer.mock.resetCalls();
    mockMessageHandler.clearSessionBuffer.mock.resetCalls();

    // Track timeouts for cleanup
    timeoutIds = [];
    const originalSetTimeout = global.setTimeout;
    global.setTimeout = (...args) => {
      const id = originalSetTimeout(...args);
      timeoutIds.push(id);
      return id;
    };

    sessionManager = new AICLISessionManager({
      maxSessions: 5,
      sessionTimeout: 1000, // 1 second for testing
      backgroundedSessionTimeout: 2000, // 2 seconds for testing
    });
  });

  afterEach(() => {
    // Clear all timeouts
    timeoutIds.forEach((id) => clearTimeout(id));
    timeoutIds = [];
  });

  describe('constructor and initialization', () => {
    it('should initialize with default configuration', () => {
      const manager = new AICLISessionManager();
      assert.strictEqual(manager.maxSessions, 10);
      assert.strictEqual(manager.sessionTimeout, 30 * 60 * 1000);
      assert.strictEqual(manager.backgroundedSessionTimeout, 4 * 60 * 60 * 1000);
    });

    it('should accept custom configuration', () => {
      const manager = new AICLISessionManager({
        maxSessions: 20,
        sessionTimeout: 5000,
        backgroundedSessionTimeout: 10000,
      });
      assert.strictEqual(manager.maxSessions, 20);
      assert.strictEqual(manager.sessionTimeout, 5000);
      assert.strictEqual(manager.backgroundedSessionTimeout, 10000);
    });

    it('should initialize persistence on construction', async () => {
      await new Promise((resolve) => setTimeout(resolve, 10));
      assert.strictEqual(mockSessionPersistence.initialize.mock.calls.length, 1);
    });
  });

  describe('restorePersistedSessions', () => {
    it('should restore sessions from persistence', async () => {
      const persistedSessions = [
        {
          sessionId: 'session1',
          workingDirectory: '/dir1',
          createdAt: Date.now() - 1000,
          lastActivity: Date.now() - 500,
          initialPrompt: 'Test prompt',
          conversationStarted: true,
          skipPermissions: false,
          isBackgrounded: false,
          backgroundedAt: null,
        },
        {
          sessionId: 'session2',
          workingDirectory: '/dir2',
          createdAt: Date.now() - 2000,
          lastActivity: Date.now() - 1000,
          initialPrompt: 'Another prompt',
          conversationStarted: false,
          skipPermissions: true,
          isBackgrounded: true,
          backgroundedAt: Date.now() - 800,
        },
      ];

      mockSessionPersistence.getAllSessions.mock.mockImplementation(() => persistedSessions);

      await sessionManager.restorePersistedSessions();

      assert.strictEqual(sessionManager.activeSessions.size, 2);

      const session1 = sessionManager.getSession('session1');
      assert.ok(session1);
      assert.strictEqual(session1.workingDirectory, '/dir1');
      assert.strictEqual(session1.conversationStarted, true);
      assert.strictEqual(session1.isRestoredSession, true);

      const session2 = sessionManager.getSession('session2');
      assert.ok(session2);
      assert.strictEqual(session2.isBackgrounded, true);
      assert.strictEqual(session2.skipPermissions, true);

      // Should create message buffers
      assert.strictEqual(mockMessageHandler.createSessionBuffer.mock.calls.length, 2);
    });

    it('should handle empty persisted sessions', async () => {
      mockSessionPersistence.getAllSessions.mock.mockImplementation(() => []);

      await sessionManager.restorePersistedSessions();

      assert.strictEqual(sessionManager.activeSessions.size, 0);
    });
  });

  describe('createInteractiveSession', () => {
    it('should create a new session with valid inputs', async () => {
      const result = await sessionManager.createInteractiveSession(
        'test-session',
        'Initial prompt',
        '/test/dir',
        { skipPermissions: true }
      );

      assert.ok(result.success);
      assert.strictEqual(result.sessionId, 'test-session');

      const session = sessionManager.getSession('test-session');
      assert.ok(session);
      assert.strictEqual(session.workingDirectory, '/test/dir');
      assert.strictEqual(session.initialPrompt, 'Initial prompt');
      assert.strictEqual(session.skipPermissions, true);
      assert.strictEqual(session.conversationStarted, false);
      assert.strictEqual(session.isBackgrounded, false);

      // Should persist session
      assert.strictEqual(mockSessionPersistence.setSession.mock.calls.length, 1);
      assert.strictEqual(
        mockSessionPersistence.setSession.mock.calls[0].arguments[0],
        'test-session'
      );

      // Should create message buffer
      assert.strictEqual(mockMessageHandler.createSessionBuffer.mock.calls.length, 1);
    });

    it('should reject when max sessions reached', async () => {
      // Fill up sessions
      for (let i = 0; i < 5; i++) {
        await sessionManager.createInteractiveSession(`session${i}`, 'prompt', '/dir');
      }

      await assert.rejects(
        sessionManager.createInteractiveSession('session5', 'prompt', '/dir'),
        /Maximum number of sessions/
      );
    });

    it('should handle persistence failures gracefully', async () => {
      mockSessionPersistence.setSession.mock.mockImplementation(() =>
        Promise.reject(new Error('Persistence failed'))
      );

      // Should not throw
      const result = await sessionManager.createInteractiveSession(
        'test-session',
        'Initial prompt',
        '/test/dir'
      );

      assert.ok(result.success);
      assert.ok(sessionManager.hasSession('test-session'));
    });
  });

  describe('closeSession', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');
    });

    it('should close an active session', async () => {
      const result = await sessionManager.closeSession('test-session');

      assert.ok(result.success);
      assert.strictEqual(result.message, 'Session closed');
      assert.ok(!sessionManager.hasSession('test-session'));

      // Should remove from persistence
      assert.strictEqual(mockSessionPersistence.removeSession.mock.calls.length, 1);
      assert.strictEqual(
        mockSessionPersistence.removeSession.mock.calls[0].arguments[0],
        'test-session'
      );
    });

    it('should emit sessionCleaned event', async () => {
      const events = [];
      sessionManager.on('sessionCleaned', (data) => events.push(data));

      await sessionManager.closeSession('test-session');

      assert.strictEqual(events.length, 1);
      assert.strictEqual(events[0].sessionId, 'test-session');
      assert.strictEqual(events[0].reason, 'user_requested');
    });

    it('should handle non-existent session', async () => {
      const result = await sessionManager.closeSession('non-existent');

      assert.ok(!result.success);
      assert.strictEqual(result.message, 'Session not found');
    });

    it('should clear timeouts when closing session', async () => {
      const session = sessionManager.getSession('test-session');
      const timeoutId = session.timeoutId;
      assert.ok(timeoutId);

      await sessionManager.closeSession('test-session');

      // Timeout should be cleared (no direct way to test, but session should be gone)
      assert.ok(!sessionManager.hasSession('test-session'));
    });
  });

  describe('session activity management', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');
    });

    it('should update session activity', async () => {
      const session = sessionManager.getSession('test-session');
      const originalActivity = session.lastActivity;

      await new Promise((resolve) => setTimeout(resolve, 10));
      await sessionManager.updateSessionActivity('test-session');

      assert.ok(session.lastActivity > originalActivity);

      // Should update persistence
      assert.strictEqual(mockSessionPersistence.updateSession.mock.calls.length, 1);
    });

    it('should set session processing state', () => {
      sessionManager.setSessionProcessing('test-session', true);

      const session = sessionManager.getSession('test-session');
      assert.strictEqual(session.isProcessing, true);

      sessionManager.setSessionProcessing('test-session', false);
      assert.strictEqual(session.isProcessing, false);
    });

    it('should mark conversation as started', async () => {
      await sessionManager.markConversationStarted('test-session');

      const session = sessionManager.getSession('test-session');
      assert.strictEqual(session.conversationStarted, true);

      // Should update persistence
      assert.strictEqual(mockSessionPersistence.updateSession.mock.calls.length, 1);
      const updateCall = mockSessionPersistence.updateSession.mock.calls[0];
      assert.strictEqual(updateCall.arguments[0], 'test-session');
      assert.strictEqual(updateCall.arguments[1].conversationStarted, true);
    });
  });

  describe('background state management', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');
    });

    it('should mark session as backgrounded', async () => {
      await sessionManager.markSessionBackgrounded('test-session');

      const session = sessionManager.getSession('test-session');
      assert.strictEqual(session.isBackgrounded, true);
      assert.ok(session.backgroundedAt);

      // Should update persistence
      const updateCalls = mockSessionPersistence.updateSession.mock.calls;
      const bgCall = updateCalls.find((call) => call.arguments[1].isBackgrounded === true);
      assert.ok(bgCall);
    });

    it('should mark session as foregrounded', async () => {
      await sessionManager.markSessionBackgrounded('test-session');
      await sessionManager.markSessionForegrounded('test-session');

      const session = sessionManager.getSession('test-session');
      assert.strictEqual(session.isBackgrounded, false);
      assert.strictEqual(session.backgroundedAt, null);

      // Should update persistence
      const updateCalls = mockSessionPersistence.updateSession.mock.calls;
      const fgCall = updateCalls.find((call) => call.arguments[1].isBackgrounded === false);
      assert.ok(fgCall);
    });
  });

  describe('checkSessionTimeout', () => {
    it('should timeout inactive session', async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');

      const session = sessionManager.getSession('test-session');
      session.lastActivity = Date.now() - 2000; // 2 seconds ago
      session.isProcessing = false;

      sessionManager.checkSessionTimeout('test-session');

      // Session should be removed
      assert.ok(!sessionManager.hasSession('test-session'));
    });

    it('should not timeout active session', async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');

      const session = sessionManager.getSession('test-session');
      session.isProcessing = true;

      sessionManager.checkSessionTimeout('test-session');

      // Session should still exist
      assert.ok(sessionManager.hasSession('test-session'));
    });

    it('should use extended timeout for backgrounded sessions', async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');

      const session = sessionManager.getSession('test-session');
      session.lastActivity = Date.now() - 1500; // 1.5 seconds ago
      session.isBackgrounded = true;
      session.backgroundedAt = Date.now() - 1500;

      sessionManager.checkSessionTimeout('test-session');

      // Should still exist (backgrounded timeout is 2 seconds)
      assert.ok(sessionManager.hasSession('test-session'));

      // But would timeout if activity was longer ago
      session.lastActivity = Date.now() - 3000; // 3 seconds ago
      sessionManager.checkSessionTimeout('test-session');

      // Now should be removed
      assert.ok(!sessionManager.hasSession('test-session'));
    });

    it('should not timeout if buffer has messages', async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');

      const session = sessionManager.getSession('test-session');
      session.lastActivity = Date.now() - 2000;

      // Add messages to buffer
      const buffer = sessionManager.getSessionBuffer('test-session');
      buffer.messages.push({ type: 'test' });

      sessionManager.checkSessionTimeout('test-session');

      // Should still exist
      assert.ok(sessionManager.hasSession('test-session'));
    });
  });

  describe('message buffer management', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');
    });

    it('should get session buffer', () => {
      const buffer = sessionManager.getSessionBuffer('test-session');
      assert.ok(buffer);
      assert.ok(Array.isArray(buffer.messages));
    });

    it('should clear session buffer', () => {
      sessionManager.clearSessionBuffer('test-session');

      assert.strictEqual(mockMessageHandler.clearSessionBuffer.mock.calls.length, 1);
    });

    it('should return undefined for non-existent session buffer', () => {
      const buffer = sessionManager.getSessionBuffer('non-existent');
      assert.strictEqual(buffer, undefined);
    });
  });

  describe('cleanupDeadSession', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');
    });

    it('should cleanup dead session', async () => {
      const events = [];
      sessionManager.on('sessionCleaned', (data) => events.push(data));

      await sessionManager.cleanupDeadSession('test-session');

      assert.ok(!sessionManager.hasSession('test-session'));
      assert.strictEqual(events.length, 1);
      assert.strictEqual(events[0].reason, 'process_died');

      // Should remove from persistence
      assert.strictEqual(mockSessionPersistence.removeSession.mock.calls.length, 1);
    });

    it('should handle non-existent session gracefully', async () => {
      // Should not throw
      await sessionManager.cleanupDeadSession('non-existent');
    });
  });

  describe('shutdown', () => {
    it('should close all active sessions', async () => {
      // Create multiple sessions
      await sessionManager.createInteractiveSession('session1', 'prompt1', '/dir1');
      await sessionManager.createInteractiveSession('session2', 'prompt2', '/dir2');
      await sessionManager.createInteractiveSession('session3', 'prompt3', '/dir3');

      await sessionManager.shutdown();

      assert.strictEqual(sessionManager.activeSessions.size, 0);
      assert.strictEqual(sessionManager.sessionMessageBuffers.size, 0);
    });

    it('should handle session close errors gracefully', async () => {
      await sessionManager.createInteractiveSession('session1', 'prompt1', '/dir1');

      // Mock closeSession to throw
      const originalClose = sessionManager.closeSession;
      sessionManager.closeSession = mock.fn(() => Promise.reject(new Error('Close failed')));

      // Should not throw
      await sessionManager.shutdown();

      sessionManager.closeSession = originalClose;
    });
  });

  describe('persistence operations', () => {
    it('should get persistence stats', () => {
      mockSessionPersistence.getStats.mock.mockImplementation(() => ({
        total: 5,
        size: 1024,
      }));

      const stats = sessionManager.getPersistenceStats();
      assert.strictEqual(stats.total, 5);
      assert.strictEqual(stats.size, 1024);
    });

    it('should export sessions', async () => {
      mockSessionPersistence.exportSessions.mock.mockImplementation(() =>
        Promise.resolve([{ sessionId: 'test' }])
      );

      const exported = await sessionManager.exportSessions();
      assert.ok(Array.isArray(exported));
      assert.strictEqual(exported.length, 1);
    });

    it('should cleanup old sessions', async () => {
      mockSessionPersistence.cleanup.mock.mockImplementation(() => Promise.resolve(3));

      const cleaned = await sessionManager.cleanupOldSessions(7 * 24 * 60 * 60 * 1000);
      assert.strictEqual(cleaned, 3);
    });
  });

  describe('reconcileSessionState', () => {
    it('should reconcile session state and remove stale sessions', async () => {
      const oldSession = {
        sessionId: 'old-session',
        lastActivity: Date.now() - 10 * 24 * 60 * 60 * 1000, // 10 days old
        workingDirectory: '/old/dir',
      };

      const recentSession = {
        sessionId: 'recent-session',
        lastActivity: Date.now() - 1 * 24 * 60 * 60 * 1000, // 1 day old
        workingDirectory: '/recent/dir',
      };

      mockSessionPersistence.getAllSessions.mock.mockImplementation(() => [
        oldSession,
        recentSession,
      ]);

      const result = await sessionManager.reconcileSessionState();

      assert.strictEqual(result.totalPersisted, 2);
      assert.strictEqual(result.staleRemoved, 1);
      assert.strictEqual(result.activeInMemory, 0);

      // Should have tried to remove old session
      const removeCalls = mockSessionPersistence.removeSession.mock.calls;
      assert.ok(removeCalls.some((call) => call.arguments[0] === 'old-session'));
    });

    it('should skip sessions already active in memory', async () => {
      await sessionManager.createInteractiveSession('active-session', 'prompt', '/dir');

      mockSessionPersistence.getAllSessions.mock.mockImplementation(() => [
        {
          sessionId: 'active-session',
          lastActivity: Date.now(),
          workingDirectory: '/dir',
        },
      ]);

      const result = await sessionManager.reconcileSessionState();

      // Should not remove active session
      assert.strictEqual(result.staleRemoved, 0);
      assert.strictEqual(mockSessionPersistence.removeSession.mock.calls.length, 0);
    });

    it('should handle removal failures gracefully', async () => {
      mockSessionPersistence.getAllSessions.mock.mockImplementation(() => [
        {
          sessionId: 'old-session',
          lastActivity: Date.now() - 10 * 24 * 60 * 60 * 1000,
          workingDirectory: '/old/dir',
        },
      ]);

      mockSessionPersistence.removeSession.mock.mockImplementation(() =>
        Promise.reject(new Error('Remove failed'))
      );

      // Should not throw
      const result = await sessionManager.reconcileSessionState();
      assert.strictEqual(result.staleRemoved, 0);
    });
  });

  describe('getActiveSessions', () => {
    it('should return list of active session IDs', async () => {
      await sessionManager.createInteractiveSession('session1', 'prompt1', '/dir1');
      await sessionManager.createInteractiveSession('session2', 'prompt2', '/dir2');

      const sessions = sessionManager.getActiveSessions();
      assert.ok(Array.isArray(sessions));
      assert.strictEqual(sessions.length, 2);
      assert.ok(sessions.includes('session1'));
      assert.ok(sessions.includes('session2'));
    });

    it('should return empty array when no sessions', () => {
      const sessions = sessionManager.getActiveSessions();
      assert.ok(Array.isArray(sessions));
      assert.strictEqual(sessions.length, 0);
    });
  });

  describe('event emission', () => {
    it('should inherit from EventEmitter', () => {
      assert.ok(sessionManager instanceof EventEmitter);
    });

    it('should emit sessionCleaned on timeout', async () => {
      const events = [];
      sessionManager.on('sessionCleaned', (data) => events.push(data));

      await sessionManager.createInteractiveSession('test-session', 'prompt', '/dir');

      const session = sessionManager.getSession('test-session');
      session.lastActivity = Date.now() - 2000;
      session.isProcessing = false;

      sessionManager.checkSessionTimeout('test-session');

      assert.strictEqual(events.length, 1);
      assert.strictEqual(events[0].sessionId, 'test-session');
    });
  });
});
