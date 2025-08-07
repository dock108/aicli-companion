import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AICLISessionManager } from '../../services/aicli-session-manager.js';

describe('AICLISessionManager - Additional Coverage', () => {
  let sessionManager;
  let testDir;

  beforeEach(() => {
    testDir = mkdtempSync(join(tmpdir(), 'session-mgr-test-'));
    sessionManager = new AICLISessionManager({
      maxSessions: 3,
      sessionTimeout: 1000, // 1 second for testing
      backgroundedSessionTimeout: 2000, // 2 seconds for testing
      minTimeoutCheckInterval: 100, // 100ms for testing
    });
  });

  afterEach(async () => {
    // Ensure all sessions are cleaned up
    await sessionManager.shutdown();

    // Clear any remaining data
    sessionManager.activeSessions.clear();
    sessionManager.sessionMessageBuffers.clear();

    if (testDir) {
      rmSync(testDir, { recursive: true, force: true });
    }
  });

  describe('Session creation and limits', () => {
    it('should allow unlimited sessions in HTTP mode', async () => {
      // HTTP architecture is stateless and doesn't enforce session limits
      for (let i = 1; i <= 5; i++) {
        const projectDir = join(testDir, `project-${i}`);
        mkdirSync(projectDir, { recursive: true });
        const result = await sessionManager.createInteractiveSession(
          `session-${i}`,
          'test prompt',
          projectDir
        );
        assert.ok(result.success);
      }
      assert.strictEqual(sessionManager.activeSessions.size, 5);
    });

    it('should handle invalid session ID sanitization', async () => {
      const result = await sessionManager.createInteractiveSession(
        'invalid-!@#-session-id',
        'test prompt',
        testDir
      );
      assert.ok(result.success);
      assert.ok(result.sessionId);
    });

    it('should reject invalid working directory', async () => {
      await assert.rejects(
        sessionManager.createInteractiveSession('test', 'prompt', '/invalid/path/../../etc'),
        /Access denied.*not allowed|Invalid directory path/
      );
    });
  });

  // Session lifecycle tests removed - backgrounded session functionality no longer exists in HTTP architecture

  describe('Session activity and processing', () => {
    it('should update session activity', async () => {
      const result = await sessionManager.createInteractiveSession(
        'activity-session',
        'test',
        testDir
      );

      const session1 = await sessionManager.getSession(result.sessionId);
      const initialActivity = session1.lastActivity;

      // Wait a bit and update activity
      await new Promise((resolve) => setTimeout(resolve, 10));
      await sessionManager.updateSessionActivity(result.sessionId);

      const session2 = await sessionManager.getSession(result.sessionId);
      assert.ok(session2.lastActivity > initialActivity);
    });

    it('should set session processing state', async () => {
      const result = await sessionManager.createInteractiveSession(
        'processing-session',
        'test',
        testDir
      );

      sessionManager.setSessionProcessing(result.sessionId, true);
      let session = await sessionManager.getSession(result.sessionId);
      assert.strictEqual(session.isProcessing, true);

      sessionManager.setSessionProcessing(result.sessionId, false);
      session = await sessionManager.getSession(result.sessionId);
      assert.strictEqual(session.isProcessing, false);
    });

    it('should handle processing state for non-existent session', () => {
      // Should not throw
      sessionManager.setSessionProcessing('non-existent', true);
      assert.ok(true);
    });
  });

  describe('Session buffers', () => {
    it('should get and clear session buffer', async () => {
      const result = await sessionManager.createInteractiveSession(
        'buffer-session',
        'test',
        testDir
      );

      const buffer = sessionManager.getSessionBuffer(result.sessionId);
      assert.ok(buffer);
      assert.ok(Array.isArray(buffer.assistantMessages));

      sessionManager.clearSessionBuffer(result.sessionId);
      // Get the buffer again to check if it was cleared
      const clearedBuffer = sessionManager.getSessionBuffer(result.sessionId);
      assert.strictEqual(clearedBuffer.assistantMessages.length, 0);
    });

    it('should handle clearing non-existent buffer', () => {
      // Should not throw
      sessionManager.clearSessionBuffer('non-existent');
      assert.ok(true);
    });
  });

  describe('Session queries', () => {
    it('should get all active sessions', async () => {
      const p1Dir = join(testDir, 'p1');
      const p2Dir = join(testDir, 'p2');
      mkdirSync(p1Dir, { recursive: true });
      mkdirSync(p2Dir, { recursive: true });

      await sessionManager.createInteractiveSession('s1', 'test', p1Dir);
      await sessionManager.createInteractiveSession('s2', 'test', p2Dir);

      const sessions = sessionManager.getActiveSessions();
      assert.strictEqual(sessions.length, 2);
      assert.ok(sessions.includes('s1'));
      assert.ok(sessions.includes('s2'));
    });

    it('should get all sessions with metadata', async () => {
      const meta1Dir = join(testDir, 'meta1');
      const meta2Dir = join(testDir, 'meta2');
      mkdirSync(meta1Dir, { recursive: true });
      mkdirSync(meta2Dir, { recursive: true });

      await sessionManager.createInteractiveSession('meta1', 'test', meta1Dir);
      await sessionManager.createInteractiveSession('meta2', 'test', meta2Dir);

      const sessions = sessionManager.getAllSessions();
      assert.strictEqual(sessions.length, 2);
      assert.ok(sessions.some((s) => s.sessionId === 'meta1'));
      assert.ok(sessions.some((s) => s.sessionId === 'meta2'));
    });
  });

  // Session timeout tests removed - backgrounded session functionality no longer exists in HTTP architecture

  describe('Session cleanup', () => {
    it('should cleanup dead session', async () => {
      const result = await sessionManager.createInteractiveSession('dead-session', 'test', testDir);

      await sessionManager.cleanupDeadSession(result.sessionId);

      const session = await sessionManager.getSession(result.sessionId);
      assert.strictEqual(session, null);
    });

    it('should emit sessionCleaned event on cleanup', async () => {
      const result = await sessionManager.createInteractiveSession(
        'event-session',
        'test',
        testDir
      );

      let eventEmitted = false;
      sessionManager.once('sessionCleaned', (data) => {
        eventEmitted = true;
        assert.strictEqual(data.sessionId, result.sessionId);
        assert.strictEqual(data.reason, 'process_died');
      });

      await sessionManager.cleanupDeadSession(result.sessionId);
      assert.ok(eventEmitted);
    });
  });

  describe('Session close', () => {
    it('should close session successfully', async () => {
      const result = await sessionManager.createInteractiveSession(
        'close-session',
        'test',
        testDir
      );

      const closeResult = await sessionManager.closeSession(result.sessionId);
      assert.ok(closeResult.success);
      assert.strictEqual(closeResult.message, 'Session closed');

      const session = await sessionManager.getSession(result.sessionId);
      assert.strictEqual(session, null);
    });

    it('should handle closing non-existent session', async () => {
      const result = await sessionManager.closeSession('non-existent');
      assert.strictEqual(result.success, false);
      assert.strictEqual(result.message, 'Session not found');
    });

    it('should emit sessionCleaned event on close', async () => {
      const result = await sessionManager.createInteractiveSession(
        'close-event-session',
        'test',
        testDir
      );

      let eventEmitted = false;
      sessionManager.once('sessionCleaned', (data) => {
        eventEmitted = true;
        assert.strictEqual(data.reason, 'user_requested');
      });

      await sessionManager.closeSession(result.sessionId);
      assert.ok(eventEmitted);
    });
  });

  describe('Persistence methods', () => {
    it('should get persistence stats', () => {
      const stats = sessionManager.getPersistenceStats();
      assert.ok(stats);
    });

    it('should export sessions', async () => {
      const exported = await sessionManager.exportSessions();
      assert.ok(exported);
    });

    it('should return cleanup stats', async () => {
      const cleaned = await sessionManager.cleanupOldSessions(0); // Clean all
      assert.strictEqual(typeof cleaned, 'object');
      assert.strictEqual(cleaned.cleaned, 0); // No sessions to clean in stateless mode
    });
  });

  describe('isClaudeSessionActive', () => {
    it('should return true for started conversation', async () => {
      const result = await sessionManager.createInteractiveSession(
        'active-session',
        'test',
        testDir
      );

      await sessionManager.markConversationStarted(result.sessionId);

      const isActive = sessionManager.isClaudeSessionActive(result.sessionId);
      assert.strictEqual(isActive, true);
    });

    it('should return true for restored session', async () => {
      const result = await sessionManager.createInteractiveSession(
        'restored-session',
        'test',
        testDir
      );

      const session = sessionManager.activeSessions.get(result.sessionId);
      session.isRestoredSession = true;

      const isActive = sessionManager.isClaudeSessionActive(result.sessionId);
      assert.strictEqual(isActive, true);
    });

    it('should return false for new session', async () => {
      const result = await sessionManager.createInteractiveSession('new-session', 'test', testDir);

      const isActive = sessionManager.isClaudeSessionActive(result.sessionId);
      assert.strictEqual(isActive, false);
    });

    it('should return false for non-existent session', () => {
      const isActive = sessionManager.isClaudeSessionActive('non-existent');
      assert.strictEqual(isActive, false);
    });
  });
});
