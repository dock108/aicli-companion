import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AICLISessionManager } from '../../services/aicli-session-manager.js';
import { sessionPersistence } from '../../services/session-persistence.js';

describe('Session Deduplication', () => {
  let sessionManager;
  let originalGetSessionByWorkingDirectory;
  let testDir;

  beforeEach(async () => {
    // Create temporary test directory
    testDir = mkdtempSync(join(tmpdir(), 'session-test-'));

    // Store original methods
    originalGetSessionByWorkingDirectory = sessionPersistence.getSessionByWorkingDirectory;

    // Mock the persistence methods we need with simple functions
    sessionPersistence.getSessionByWorkingDirectory = () => null;
    sessionPersistence.getSession = () => null;
    sessionPersistence.updateSession = () => Promise.resolve();
    sessionPersistence.setSession = () => Promise.resolve();

    sessionManager = new AICLISessionManager();
  });

  afterEach(() => {
    // Restore original method
    sessionPersistence.getSessionByWorkingDirectory = originalGetSessionByWorkingDirectory;

    // Clean up test directory
    if (testDir) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  it('should reuse existing session for same working directory', async () => {
    const workingDir = testDir;
    const initialPrompt = 'Initial prompt';

    // First session creation
    const result1 = await sessionManager.createInteractiveSession(
      'session-1',
      initialPrompt,
      workingDir
    );

    assert.strictEqual(result1.success, true);
    assert.strictEqual(result1.reused, undefined);

    // Second session creation with same directory
    const result2 = await sessionManager.createInteractiveSession(
      'session-2',
      'Different prompt',
      workingDir
    );

    assert.strictEqual(result2.success, true);
    assert.strictEqual(result2.reused, true);
    assert.strictEqual(result2.sessionId, result1.sessionId);
    assert.strictEqual(result2.message, 'Reusing existing session for this project');
  });

  it('should create new session for different working directory', async () => {
    const workingDir1 = mkdtempSync(join(testDir, 'project1-'));
    const workingDir2 = mkdtempSync(join(testDir, 'project2-'));

    const result1 = await sessionManager.createInteractiveSession(
      'session-1',
      'Prompt 1',
      workingDir1
    );

    const result2 = await sessionManager.createInteractiveSession(
      'session-2',
      'Prompt 2',
      workingDir2
    );

    assert.strictEqual(result1.success, true);
    assert.strictEqual(result2.success, true);
    assert.notStrictEqual(result1.sessionId, result2.sessionId);
    assert.strictEqual(result2.reused, undefined);
  });

  it('should restore session from persistence by working directory', async () => {
    const workingDir = testDir;
    const persistedSession = {
      sessionId: 'persisted-session',
      workingDirectory: workingDir,
      conversationStarted: true,
      initialPrompt: 'Original prompt',
      createdAt: Date.now() - 1000,
      lastActivity: Date.now() - 500,
    };

    // Temporarily change NODE_ENV to enable persistence checking
    const originalNodeEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'development';

    // Mock persistence to return session
    sessionPersistence.getSessionByWorkingDirectory = (dir) => {
      if (dir === workingDir) {
        return { sessionId: persistedSession.sessionId, session: persistedSession };
      }
      return null;
    };

    sessionPersistence.getSession = (id) => {
      if (id === persistedSession.sessionId) {
        return persistedSession;
      }
      return null;
    };

    // Mock _restoreSingleSession to add the session to activeSessions
    sessionManager._restoreSingleSession = async (sessionId) => {
      sessionManager.activeSessions.set(sessionId, persistedSession);
    };

    try {
      const result = await sessionManager.createInteractiveSession(
        'new-session',
        'New prompt',
        workingDir
      );

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.reused, true);
      assert.strictEqual(result.sessionId, 'persisted-session');
    } finally {
      // Always restore NODE_ENV
      process.env.NODE_ENV = originalNodeEnv;
    }
  });

  it('should handle multiple clients connecting to same project', async () => {
    const workingDir = testDir;

    // Simulate multiple clients trying to create sessions
    const results = await Promise.all([
      sessionManager.createInteractiveSession('client1-session', 'Client 1', workingDir),
      sessionManager.createInteractiveSession('client2-session', 'Client 2', workingDir),
      sessionManager.createInteractiveSession('client3-session', 'Client 3', workingDir),
    ]);

    // All should get the same session
    const sessionIds = results.map((r) => r.sessionId);
    assert.strictEqual(sessionIds[0], sessionIds[1]);
    assert.strictEqual(sessionIds[1], sessionIds[2]);

    // At least one should be reused
    const reusedCount = results.filter((r) => r.reused).length;
    assert.ok(reusedCount >= 2, 'At least 2 sessions should be reused');
  });

  it('should update session activity when reusing', async () => {
    const workingDir = testDir;

    // Create first session
    await sessionManager.createInteractiveSession('session-1', 'Initial', workingDir);

    // Get the session to check initial activity time
    const session1 = await sessionManager.getSession('session-1');
    const initialActivity = session1.lastActivity;

    // Wait a bit
    await new Promise((resolve) => setTimeout(resolve, 50));

    // Temporarily override NODE_ENV to ensure activity update works
    const originalNodeEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'development';

    try {
      // Reuse session
      await sessionManager.createInteractiveSession('session-2', 'Reuse', workingDir);

      // Activity should be updated
      const session2 = await sessionManager.getSession('session-1');
      assert.ok(session2.lastActivity > initialActivity, 'Activity timestamp should be updated');
    } finally {
      // Always restore NODE_ENV
      process.env.NODE_ENV = originalNodeEnv;
    }
  });
});
