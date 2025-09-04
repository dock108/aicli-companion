import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { SessionRouter } from '../../../services/aicli-session-manager/session-router.js';

describe('SessionRouter', () => {
  let router;
  let mockStorage;

  beforeEach(() => {
    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});
    mock.method(console, 'warn', () => {});

    // Create mock storage
    mockStorage = {
      projectSessions: new Map(),
      claudeSessions: new Map(),
      activeSessions: new Map(),

      getProjectSession: mock.fn((path) => mockStorage.projectSessions.get(path)),
      setProjectSession: mock.fn((path, id) => mockStorage.projectSessions.set(path, id)),
      getAllProjectSessions: mock.fn(() => mockStorage.projectSessions),

      getSession: mock.fn((id) => mockStorage.activeSessions.get(id)),
      getActiveSessions: mock.fn(() => Array.from(mockStorage.activeSessions.values())),
      hasActiveSession: mock.fn((id) => mockStorage.activeSessions.has(id)),
      addActiveSession: mock.fn((id, session) => mockStorage.activeSessions.set(id, session)),

      getClaudeSession: mock.fn((id) => mockStorage.claudeSessions.get(id)),
      addClaudeSession: mock.fn((id, data) => mockStorage.claudeSessions.set(id, data)),
      getAllClaudeSessions: mock.fn(() => mockStorage.claudeSessions),
    };

    router = new SessionRouter(mockStorage);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('findByWorkingDirectory', () => {
    it('should find session by project mapping', async () => {
      const session = {
        sessionId: 'session1',
        workingDirectory: '/project/path',
      };
      mockStorage.projectSessions.set('/project/path', 'session1');
      mockStorage.activeSessions.set('session1', session);

      const found = await router.findByWorkingDirectory('/project/path');

      assert.deepStrictEqual(found, session);
      assert.strictEqual(mockStorage.getProjectSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.getSession.mock.callCount(), 1);
    });

    it('should fallback to searching active sessions', async () => {
      const session = {
        sessionId: 'session1',
        workingDirectory: '/project/path',
      };
      mockStorage.activeSessions.set('session1', session);

      const found = await router.findByWorkingDirectory('/project/path');

      assert.deepStrictEqual(found, session);
      assert.strictEqual(mockStorage.getActiveSessions.mock.callCount(), 1);
    });

    it('should return null when no session found', async () => {
      const found = await router.findByWorkingDirectory('/unknown/path');
      assert.strictEqual(found, null);
    });

    it('should handle orphaned project mapping', async () => {
      mockStorage.projectSessions.set('/project/path', 'nonexistent');

      const found = await router.findByWorkingDirectory('/project/path');
      assert.strictEqual(found, null);
    });

    it('should find session in active sessions when multiple exist', async () => {
      const session1 = { sessionId: 'session1', workingDirectory: '/path1' };
      const session2 = { sessionId: 'session2', workingDirectory: '/path2' };
      const session3 = { sessionId: 'session3', workingDirectory: '/path3' };

      mockStorage.activeSessions.set('session1', session1);
      mockStorage.activeSessions.set('session2', session2);
      mockStorage.activeSessions.set('session3', session3);

      const found = await router.findByWorkingDirectory('/path2');
      assert.deepStrictEqual(found, session2);
    });
  });

  describe('trackForRouting', () => {
    it('should track project path mapping', () => {
      router.trackForRouting('session1', '/project/path');

      assert(
        mockStorage.setProjectSession.mock.calls.some(
          (call) => call.arguments[0] === '/project/path' && call.arguments[1] === 'session1'
        )
      );
    });

    it('should track with our session ID when provided', () => {
      router.trackForRouting('claudeSession1', '/project/path', 'ourSession1');

      assert(
        mockStorage.setProjectSession.mock.calls.some((call) => call.arguments[1] === 'ourSession1')
      );
    });

    it('should track Claude session when different from our session', () => {
      router.trackForRouting('claudeSession1', '/project/path', 'ourSession1');

      assert(
        mockStorage.addClaudeSession.mock.calls.some(
          (call) =>
            call.arguments[0] === 'claudeSession1' &&
            call.arguments[1].ourSessionId === 'ourSession1'
        )
      );
    });

    it('should create temporary session if not exists', () => {
      mockStorage.hasActiveSession.mock.mockImplementation(() => false);

      router.trackForRouting('session1', '/project/path');

      assert(
        mockStorage.addActiveSession.mock.calls.some(
          (call) => call.arguments[0] === 'session1' && call.arguments[1].isTemporary === true
        )
      );
    });

    it('should not create temporary session if already exists', () => {
      mockStorage.hasActiveSession.mock.mockImplementation(() => true);

      router.trackForRouting('session1', '/project/path');

      assert.strictEqual(mockStorage.addActiveSession.mock.callCount(), 0);
    });

    it('should handle null project path', () => {
      router.trackForRouting('session1', null);

      assert.strictEqual(mockStorage.setProjectSession.mock.callCount(), 0);
    });

    it('should not track Claude session when IDs match', () => {
      router.trackForRouting('session1', '/project/path', 'session1');

      // Should not add Claude session when IDs are the same
      assert.strictEqual(mockStorage.addClaudeSession.mock.callCount(), 0);
    });

    it('should track Claude session without our session ID', () => {
      router.trackForRouting('claudeSession1', '/project/path');

      // Should still track Claude session even without ourSessionId
      assert(
        mockStorage.addClaudeSession.mock.calls.some(
          (call) =>
            call.arguments[0] === 'claudeSession1' &&
            call.arguments[1].projectPath === '/project/path'
        )
      );
    });

    it('should include timestamps in tracked data', () => {
      const beforeTime = Date.now();
      router.trackForRouting('claudeSession1', '/project/path', 'ourSession1');
      const afterTime = Date.now();

      const call = mockStorage.addClaudeSession.mock.calls[0];
      const data = call.arguments[1];

      assert(data.createdAt >= beforeTime && data.createdAt <= afterTime);
      assert(data.lastActivity >= beforeTime && data.lastActivity <= afterTime);
    });
  });

  describe('mapClaudeSession', () => {
    it('should create new Claude session mapping', () => {
      const ourSession = { sessionId: 'ourSession1' };
      mockStorage.activeSessions.set('ourSession1', ourSession);

      const result = router.mapClaudeSession('ourSession1', 'claudeSession1');

      assert.strictEqual(result, true);
      assert(
        mockStorage.addClaudeSession.mock.calls.some(
          (call) =>
            call.arguments[0] === 'claudeSession1' &&
            call.arguments[1].ourSessionId === 'ourSession1'
        )
      );
      assert.strictEqual(ourSession.claudeSessionId, 'claudeSession1');
    });

    it('should update existing Claude session mapping', () => {
      const existingSession = {
        ourSessionId: 'oldSession',
        createdAt: Date.now() - 10000,
      };
      mockStorage.claudeSessions.set('claudeSession1', existingSession);

      const ourSession = { sessionId: 'ourSession1' };
      mockStorage.activeSessions.set('ourSession1', ourSession);

      const result = router.mapClaudeSession('ourSession1', 'claudeSession1');

      assert.strictEqual(result, true);
      assert.strictEqual(existingSession.ourSessionId, 'ourSession1');
      assert(existingSession.lastActivity > existingSession.createdAt);
    });

    it('should handle invalid session IDs', () => {
      const result1 = router.mapClaudeSession(null, 'claudeSession1');
      const result2 = router.mapClaudeSession('ourSession1', null);
      const result3 = router.mapClaudeSession(null, null);
      const result4 = router.mapClaudeSession('', '');
      const result5 = router.mapClaudeSession(undefined, 'claudeSession1');

      assert.strictEqual(result1, false);
      assert.strictEqual(result2, false);
      assert.strictEqual(result3, false);
      assert.strictEqual(result4, false);
      assert.strictEqual(result5, false);
    });

    it('should handle missing our session', () => {
      // Our session doesn't exist
      const result = router.mapClaudeSession('nonexistent', 'claudeSession1');

      assert.strictEqual(result, true); // Still creates mapping
      assert.strictEqual(mockStorage.addClaudeSession.mock.callCount(), 1);
    });

    it('should update our session lastActivity', () => {
      const beforeTime = Date.now();
      const ourSession = {
        sessionId: 'ourSession1',
        lastActivity: beforeTime - 10000,
      };
      mockStorage.activeSessions.set('ourSession1', ourSession);

      router.mapClaudeSession('ourSession1', 'claudeSession1');

      assert(ourSession.lastActivity >= beforeTime);
    });
  });

  describe('findClaudeSessionForOurSession', () => {
    it('should find by direct reference', () => {
      const ourSession = {
        sessionId: 'ourSession1',
        claudeSessionId: 'claudeSession1',
      };
      mockStorage.activeSessions.set('ourSession1', ourSession);

      const result = router.findClaudeSessionForOurSession('ourSession1');

      assert.strictEqual(result, 'claudeSession1');
      assert.strictEqual(mockStorage.getSession.mock.callCount(), 1);
    });

    it('should search through Claude sessions', () => {
      const ourSession = { sessionId: 'ourSession1' };
      mockStorage.activeSessions.set('ourSession1', ourSession);

      mockStorage.claudeSessions.set('claudeSession1', {
        ourSessionId: 'ourSession1',
      });

      const result = router.findClaudeSessionForOurSession('ourSession1');

      assert.strictEqual(result, 'claudeSession1');
      assert.strictEqual(mockStorage.getAllClaudeSessions.mock.callCount(), 1);
    });

    it('should return null when not found', () => {
      const result = router.findClaudeSessionForOurSession('unknown');
      assert.strictEqual(result, null);
    });

    it('should handle session without Claude session', () => {
      const ourSession = { sessionId: 'ourSession1' };
      mockStorage.activeSessions.set('ourSession1', ourSession);

      const result = router.findClaudeSessionForOurSession('ourSession1');
      assert.strictEqual(result, null);
    });

    it('should find correct Claude session among multiple', () => {
      const ourSession = { sessionId: 'ourSession2' };
      mockStorage.activeSessions.set('ourSession2', ourSession);

      mockStorage.claudeSessions.set('claudeSession1', { ourSessionId: 'ourSession1' });
      mockStorage.claudeSessions.set('claudeSession2', { ourSessionId: 'ourSession2' });
      mockStorage.claudeSessions.set('claudeSession3', { ourSessionId: 'ourSession3' });

      const result = router.findClaudeSessionForOurSession('ourSession2');
      assert.strictEqual(result, 'claudeSession2');
    });
  });

  describe('findOurSessionForClaudeSession', () => {
    it('should find by Claude session reference', () => {
      mockStorage.claudeSessions.set('claudeSession1', {
        ourSessionId: 'ourSession1',
      });

      const result = router.findOurSessionForClaudeSession('claudeSession1');

      assert.strictEqual(result, 'ourSession1');
      assert.strictEqual(mockStorage.getClaudeSession.mock.callCount(), 1);
    });

    it('should search through active sessions', () => {
      mockStorage.claudeSessions.set('claudeSession1', {});

      mockStorage.activeSessions.set('ourSession1', {
        sessionId: 'ourSession1',
        claudeSessionId: 'claudeSession1',
      });

      const result = router.findOurSessionForClaudeSession('claudeSession1');

      assert.strictEqual(result, 'ourSession1');
      assert.strictEqual(mockStorage.getActiveSessions.mock.callCount(), 1);
    });

    it('should return null when not found', () => {
      const result = router.findOurSessionForClaudeSession('unknown');
      assert.strictEqual(result, null);
    });

    it('should handle Claude session without our session', () => {
      mockStorage.claudeSessions.set('claudeSession1', {});

      const result = router.findOurSessionForClaudeSession('claudeSession1');
      assert.strictEqual(result, null);
    });

    it('should find correct our session among multiple', () => {
      mockStorage.claudeSessions.set('claudeSession2', {});

      mockStorage.activeSessions.set('ourSession1', {
        sessionId: 'ourSession1',
        claudeSessionId: 'claudeSession1',
      });
      mockStorage.activeSessions.set('ourSession2', {
        sessionId: 'ourSession2',
        claudeSessionId: 'claudeSession2',
      });
      mockStorage.activeSessions.set('ourSession3', {
        sessionId: 'ourSession3',
        claudeSessionId: 'claudeSession3',
      });

      const result = router.findOurSessionForClaudeSession('claudeSession2');
      assert.strictEqual(result, 'ourSession2');
    });
  });

  describe('getRoutingStats', () => {
    it('should return routing statistics', () => {
      mockStorage.projectSessions.set('/path1', 'session1');
      mockStorage.projectSessions.set('/path2', 'session2');

      mockStorage.claudeSessions.set('claude1', {});
      mockStorage.claudeSessions.set('claude2', {});
      mockStorage.claudeSessions.set('claude3', {});

      mockStorage.activeSessions.set('session1', {});
      mockStorage.activeSessions.set('session2', {});

      const stats = router.getRoutingStats();

      assert.deepStrictEqual(stats, {
        projectMappings: 2,
        claudeSessions: 3,
        activeSessions: 2,
      });
    });

    it('should handle empty storage', () => {
      const stats = router.getRoutingStats();

      assert.deepStrictEqual(stats, {
        projectMappings: 0,
        claudeSessions: 0,
        activeSessions: 0,
      });
    });

    it('should handle large numbers', () => {
      // Add many sessions
      for (let i = 0; i < 100; i++) {
        mockStorage.projectSessions.set(`/path${i}`, `session${i}`);
        mockStorage.claudeSessions.set(`claude${i}`, {});
        mockStorage.activeSessions.set(`session${i}`, {});
      }

      const stats = router.getRoutingStats();

      assert.deepStrictEqual(stats, {
        projectMappings: 100,
        claudeSessions: 100,
        activeSessions: 100,
      });
    });
  });
});
