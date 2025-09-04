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
    mock.method(console, 'error', () => {});

    // Create mock storage with all required methods
    mockStorage = {
      projectSessions: new Map(),
      claudeSessions: new Map(),
      activeSessions: new Map(),

      getProjectSession: mock.fn((workingDirectory) => {
        return mockStorage.projectSessions.get(workingDirectory);
      }),

      setProjectSession: mock.fn((projectPath, sessionId) => {
        mockStorage.projectSessions.set(projectPath, sessionId);
      }),

      getSession: mock.fn((sessionId) => {
        return mockStorage.activeSessions.get(sessionId);
      }),

      getActiveSessions: mock.fn(() => {
        return Array.from(mockStorage.activeSessions.values());
      }),

      hasActiveSession: mock.fn((sessionId) => {
        return mockStorage.activeSessions.has(sessionId);
      }),

      addActiveSession: mock.fn((sessionId, session) => {
        mockStorage.activeSessions.set(sessionId, session);
      }),

      getClaudeSession: mock.fn((sessionId) => {
        return mockStorage.claudeSessions.get(sessionId);
      }),

      addClaudeSession: mock.fn((sessionId, data) => {
        mockStorage.claudeSessions.set(sessionId, data);
      }),

      getAllClaudeSessions: mock.fn(() => {
        return mockStorage.claudeSessions;
      }),

      getAllProjectSessions: mock.fn(() => {
        return mockStorage.projectSessions;
      }),
    };

    router = new SessionRouter(mockStorage);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('findByWorkingDirectory', () => {
    it('should find session by project mapping', async () => {
      const workingDirectory = '/project/path';
      const sessionId = 'session123';
      const session = { sessionId, workingDirectory };

      mockStorage.projectSessions.set(workingDirectory, sessionId);
      mockStorage.activeSessions.set(sessionId, session);

      const result = await router.findByWorkingDirectory(workingDirectory);

      assert.strictEqual(result, session);
      assert.strictEqual(mockStorage.getProjectSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.getSession.mock.callCount(), 1);
    });

    it('should fallback to searching active sessions', async () => {
      const workingDirectory = '/project/path';
      const session = { sessionId: 'session456', workingDirectory };

      mockStorage.activeSessions.set('session456', session);

      const result = await router.findByWorkingDirectory(workingDirectory);

      assert.strictEqual(result, session);
      assert.strictEqual(mockStorage.getProjectSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.getActiveSessions.mock.callCount(), 1);
    });

    it('should return null if no session found', async () => {
      const result = await router.findByWorkingDirectory('/unknown/path');

      assert.strictEqual(result, null);
      assert.strictEqual(mockStorage.getProjectSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.getActiveSessions.mock.callCount(), 1);
    });

    it('should handle null working directory', async () => {
      const result = await router.findByWorkingDirectory(null);

      assert.strictEqual(result, null);
    });
  });

  describe('trackForRouting', () => {
    it('should track project path mapping', () => {
      const sessionId = 'session123';
      const projectPath = '/project/path';

      router.trackForRouting(sessionId, projectPath);

      assert.strictEqual(mockStorage.setProjectSession.mock.callCount(), 1);
      const call = mockStorage.setProjectSession.mock.calls[0];
      assert.strictEqual(call.arguments[0], projectPath);
      assert.strictEqual(call.arguments[1], sessionId);
    });

    it('should track with custom ourSessionId', () => {
      const sessionId = 'claude123';
      const projectPath = '/project/path';
      const ourSessionId = 'our456';

      router.trackForRouting(sessionId, projectPath, ourSessionId);

      assert.strictEqual(mockStorage.setProjectSession.mock.callCount(), 1);
      const setCall = mockStorage.setProjectSession.mock.calls[0];
      assert.strictEqual(setCall.arguments[1], ourSessionId);

      assert.strictEqual(mockStorage.addClaudeSession.mock.callCount(), 1);
      const addCall = mockStorage.addClaudeSession.mock.calls[0];
      assert.strictEqual(addCall.arguments[0], sessionId);
      assert.strictEqual(addCall.arguments[1].ourSessionId, ourSessionId);
    });

    it('should create temporary session if not exists', () => {
      const sessionId = 'session123';
      const projectPath = '/project/path';

      router.trackForRouting(sessionId, projectPath);

      assert.strictEqual(mockStorage.hasActiveSession.mock.callCount(), 1);
      assert.strictEqual(mockStorage.addActiveSession.mock.callCount(), 1);
      
      const call = mockStorage.addActiveSession.mock.calls[0];
      assert.strictEqual(call.arguments[0], sessionId);
      assert.strictEqual(call.arguments[1].sessionId, sessionId);
      assert.strictEqual(call.arguments[1].workingDirectory, projectPath);
      assert.strictEqual(call.arguments[1].isTemporary, true);
    });

    it('should handle null projectPath', () => {
      const sessionId = 'session123';

      router.trackForRouting(sessionId, null);

      assert.strictEqual(mockStorage.setProjectSession.mock.callCount(), 0);
      assert.strictEqual(mockStorage.addActiveSession.mock.callCount(), 1);
    });
  });

  describe('mapClaudeSession', () => {
    it('should map Claude session to our session', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';

      const result = router.mapClaudeSession(ourSessionId, claudeSessionId);

      assert.strictEqual(result, true);
      assert.strictEqual(mockStorage.addClaudeSession.mock.callCount(), 1);
      
      const call = mockStorage.addClaudeSession.mock.calls[0];
      assert.strictEqual(call.arguments[0], claudeSessionId);
      assert.strictEqual(call.arguments[1].ourSessionId, ourSessionId);
    });

    it('should update existing Claude session', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';
      const existingSession = {
        ourSessionId: 'old123',
        createdAt: Date.now() - 1000,
      };

      mockStorage.claudeSessions.set(claudeSessionId, existingSession);

      const result = router.mapClaudeSession(ourSessionId, claudeSessionId);

      assert.strictEqual(result, true);
      assert.strictEqual(existingSession.ourSessionId, ourSessionId);
      assert(existingSession.lastActivity > existingSession.createdAt);
    });

    it('should update our session with Claude session ID', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';
      const ourSession = { sessionId: ourSessionId };

      mockStorage.activeSessions.set(ourSessionId, ourSession);

      router.mapClaudeSession(ourSessionId, claudeSessionId);

      assert.strictEqual(ourSession.claudeSessionId, claudeSessionId);
      assert(ourSession.lastActivity);
    });

    it('should return false for invalid inputs', () => {
      assert.strictEqual(router.mapClaudeSession(null, 'claude123'), false);
      assert.strictEqual(router.mapClaudeSession('our123', null), false);
      assert.strictEqual(router.mapClaudeSession(null, null), false);
    });
  });

  describe('findClaudeSessionForOurSession', () => {
    it('should find Claude session from our session reference', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';
      const ourSession = { 
        sessionId: ourSessionId, 
        claudeSessionId 
      };

      mockStorage.activeSessions.set(ourSessionId, ourSession);

      const result = router.findClaudeSessionForOurSession(ourSessionId);

      assert.strictEqual(result, claudeSessionId);
    });

    it('should search Claude sessions if no direct reference', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';

      mockStorage.claudeSessions.set(claudeSessionId, { ourSessionId });
      mockStorage.activeSessions.set(ourSessionId, { sessionId: ourSessionId });

      const result = router.findClaudeSessionForOurSession(ourSessionId);

      assert.strictEqual(result, claudeSessionId);
    });

    it('should return null if not found', () => {
      const result = router.findClaudeSessionForOurSession('unknown');

      assert.strictEqual(result, null);
    });
  });

  describe('findOurSessionForClaudeSession', () => {
    it('should find our session from Claude session data', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';

      mockStorage.claudeSessions.set(claudeSessionId, { ourSessionId });

      const result = router.findOurSessionForClaudeSession(claudeSessionId);

      assert.strictEqual(result, ourSessionId);
    });

    it('should search active sessions if no Claude session data', () => {
      const ourSessionId = 'our123';
      const claudeSessionId = 'claude456';
      const session = { 
        sessionId: ourSessionId, 
        claudeSessionId 
      };

      mockStorage.activeSessions.set(ourSessionId, session);

      const result = router.findOurSessionForClaudeSession(claudeSessionId);

      assert.strictEqual(result, ourSessionId);
    });

    it('should return null if not found', () => {
      const result = router.findOurSessionForClaudeSession('unknown');

      assert.strictEqual(result, null);
    });
  });

  describe('getRoutingStats', () => {
    it('should return routing statistics', () => {
      mockStorage.projectSessions.set('/path1', 'session1');
      mockStorage.projectSessions.set('/path2', 'session2');
      mockStorage.claudeSessions.set('claude1', {});
      mockStorage.activeSessions.set('session1', {});
      mockStorage.activeSessions.set('session2', {});
      mockStorage.activeSessions.set('session3', {});

      const stats = router.getRoutingStats();

      assert.strictEqual(stats.projectMappings, 2);
      assert.strictEqual(stats.claudeSessions, 1);
      assert.strictEqual(stats.activeSessions, 3);
    });

    it('should handle empty storage', () => {
      const stats = router.getRoutingStats();

      assert.strictEqual(stats.projectMappings, 0);
      assert.strictEqual(stats.claudeSessions, 0);
      assert.strictEqual(stats.activeSessions, 0);
    });
  });
});