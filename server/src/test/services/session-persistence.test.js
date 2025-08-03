import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { SessionPersistence } from '../../services/session-persistence.js';

describe('SessionPersistence', () => {
  let persistence;
  let testDir;

  beforeEach(async () => {
    // Create temporary test directory
    testDir = mkdtempSync(join(tmpdir(), 'session-persist-test-'));

    // Create new persistence instance with test directory
    persistence = new SessionPersistence();
    persistence.sessionDir = testDir;
    persistence.sessionsCache = new Map();
    persistence.isInitialized = false;

    // Initialize
    await persistence.initialize();
  });

  afterEach(() => {
    // Clean up test directory
    if (testDir && existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  it('should initialize and create session directory', async () => {
    assert.ok(existsSync(testDir));
    assert.ok(persistence.isInitialized);
  });

  it('should save and load sessions from disk', async () => {
    const sessionData = {
      workingDirectory: '/test/project',
      conversationStarted: false,
      initialPrompt: 'Test prompt',
      skipPermissions: false,
    };

    // Set session
    const session = await persistence.setSession('test-session-1', sessionData);
    assert.strictEqual(session.sessionId, 'test-session-1');
    assert.strictEqual(session.workingDirectory, '/test/project');

    // Force save to disk
    await persistence.saveSessions();

    // Create new instance and load from disk
    const newPersistence = new SessionPersistence();
    newPersistence.sessionDir = testDir;
    await newPersistence.initialize();

    // Check if session was loaded
    const loadedSession = newPersistence.getSession('test-session-1');
    assert.ok(loadedSession);
    assert.strictEqual(loadedSession.sessionId, 'test-session-1');
    assert.strictEqual(loadedSession.workingDirectory, '/test/project');
  });

  it('should get session by working directory', async () => {
    await persistence.setSession('session-1', {
      workingDirectory: '/project/one',
      conversationStarted: false,
    });

    await persistence.setSession('session-2', {
      workingDirectory: '/project/two',
      conversationStarted: true,
    });

    const result = persistence.getSessionByWorkingDirectory('/project/one');
    assert.ok(result);
    assert.strictEqual(result.sessionId, 'session-1');
    assert.strictEqual(result.session.workingDirectory, '/project/one');

    const notFound = persistence.getSessionByWorkingDirectory('/project/three');
    assert.strictEqual(notFound, null);
  });

  it('should update session fields', async () => {
    await persistence.setSession('update-test', {
      workingDirectory: '/test',
      conversationStarted: false,
    });

    const updated = await persistence.updateSession('update-test', {
      conversationStarted: true,
      isBackgrounded: true,
    });

    assert.strictEqual(updated.conversationStarted, true);
    assert.strictEqual(updated.isBackgrounded, true);
    assert.strictEqual(updated.workingDirectory, '/test'); // Original field preserved
  });

  it('should remove sessions', async () => {
    await persistence.setSession('remove-test', {
      workingDirectory: '/test',
      conversationStarted: false,
    });

    assert.ok(persistence.hasSession('remove-test'));

    const removed = await persistence.removeSession('remove-test');
    assert.strictEqual(removed, true);
    assert.strictEqual(persistence.hasSession('remove-test'), false);

    // Removing non-existent should return false
    const removedAgain = await persistence.removeSession('remove-test');
    assert.strictEqual(removedAgain, false);
  });

  it('should cleanup old sessions', async () => {
    const now = Date.now();

    // Create old session
    await persistence.setSession('old-session', {
      workingDirectory: '/old',
      conversationStarted: false,
      lastActivity: now - 8 * 24 * 60 * 60 * 1000, // 8 days old
    });

    // Create recent session
    await persistence.setSession('recent-session', {
      workingDirectory: '/recent',
      conversationStarted: false,
      lastActivity: now - 1 * 60 * 60 * 1000, // 1 hour old
    });

    // Override lastActivity after creation
    persistence.sessionsCache.get('old-session').lastActivity = now - 8 * 24 * 60 * 60 * 1000;

    // Cleanup sessions older than 7 days
    const removed = await persistence.cleanup();

    assert.strictEqual(removed.length, 1);
    assert.strictEqual(removed[0], 'old-session');
    assert.strictEqual(persistence.hasSession('old-session'), false);
    assert.strictEqual(persistence.hasSession('recent-session'), true);
  });

  it('should get all sessions', () => {
    persistence.sessionsCache.set('session-1', { sessionId: 'session-1' });
    persistence.sessionsCache.set('session-2', { sessionId: 'session-2' });

    const all = persistence.getAllSessions();
    assert.strictEqual(all.length, 2);
    assert.ok(all.some((s) => s.sessionId === 'session-1'));
    assert.ok(all.some((s) => s.sessionId === 'session-2'));
  });

  it('should get all session IDs', () => {
    persistence.sessionsCache.set('id-1', {});
    persistence.sessionsCache.set('id-2', {});
    persistence.sessionsCache.set('id-3', {});

    const ids = persistence.getAllSessionIds();
    assert.strictEqual(ids.length, 3);
    assert.ok(ids.includes('id-1'));
    assert.ok(ids.includes('id-2'));
    assert.ok(ids.includes('id-3'));
  });

  it('should identify stale sessions', () => {
    const now = Date.now();

    persistence.sessionsCache.set('fresh', {
      sessionId: 'fresh',
      lastActivity: now - 1 * 60 * 60 * 1000, // 1 hour old
    });

    persistence.sessionsCache.set('stale', {
      sessionId: 'stale',
      lastActivity: now - 5 * 60 * 60 * 1000, // 5 hours old
    });

    // Get sessions idle for more than 4 hours
    const stale = persistence.getStaleSessionIds();
    assert.strictEqual(stale.length, 1);
    assert.strictEqual(stale[0], 'stale');
  });

  it('should export sessions', async () => {
    await persistence.setSession('export-1', {
      workingDirectory: '/export/one',
      conversationStarted: true,
    });

    await persistence.setSession('export-2', {
      workingDirectory: '/export/two',
      conversationStarted: false,
    });

    const exported = await persistence.exportSessions();
    assert.strictEqual(exported.sessions.length, 2);
    assert.ok(exported.exportedAt);
    assert.strictEqual(exported.version, '1.0');
  });

  it('should get stats', () => {
    persistence.sessionsCache.set('s1', { lastActivity: Date.now() });
    persistence.sessionsCache.set('s2', { lastActivity: Date.now() - 5 * 60 * 60 * 1000 });

    const stats = persistence.getStats();
    assert.strictEqual(stats.totalSessions, 2);
    assert.strictEqual(stats.staleSessions, 1);
    assert.ok(stats.oldestSession);
    assert.ok(stats.newestSession);
  });

  it('should handle errors during initialization', async () => {
    const badPersistence = new SessionPersistence();
    badPersistence.sessionDir = '/invalid/path/that/cannot/exist';

    // Should not throw, but log error
    await badPersistence.initialize();

    // Should still be usable (in-memory only)
    await badPersistence.setSession('test', { workingDirectory: '/test' });
    assert.ok(badPersistence.hasSession('test'));
  });

  it('should handle update on non-existent session', async () => {
    try {
      await persistence.updateSession('non-existent', { conversationStarted: true });
      assert.fail('Should have thrown error');
    } catch (error) {
      assert.ok(error.message.includes('not found'));
    }
  });
});
