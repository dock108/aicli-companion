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
    it('should enforce max session limit', async () => {
      // Create sessions up to limit
      for (let i = 1; i <= 3; i++) {
        const projectDir = join(testDir, `project-${i}`);
        mkdirSync(projectDir, { recursive: true });
        const result = await sessionManager.createInteractiveSession(
          `session-${i}`,
          'test prompt',
          projectDir
        );
        assert.ok(result.success);
      }

      // Try to create one more
      const project4Dir = join(testDir, 'project-4');
      mkdirSync(project4Dir, { recursive: true });
      await assert.rejects(
        sessionManager.createInteractiveSession('session-4', 'test', project4Dir),
        /Maximum number of sessions/
      );
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

  describe('Session lifecycle', () => {
    it('should mark session as backgrounded', async () => {
      const result = await sessionManager.createInteractiveSession('bg-session', 'test', testDir);

      await sessionManager.markSessionBackgrounded(result.sessionId);

      const session = await sessionManager.getSession(result.sessionId);
      assert.strictEqual(session.isBackgrounded, true);
      assert.ok(session.backgroundedAt);
    });

    it('should mark session as foregrounded', async () => {
      const result = await sessionManager.createInteractiveSession('fg-session', 'test', testDir);

      await sessionManager.markSessionBackgrounded(result.sessionId);
      await sessionManager.markSessionForegrounded(result.sessionId);

      const session = await sessionManager.getSession(result.sessionId);
      assert.strictEqual(session.isBackgrounded, false);
      assert.strictEqual(session.backgroundedAt, null);
    });

    it('should handle marking non-existent session as foregrounded', async () => {
      // Should not throw, just log warning
      await sessionManager.markSessionForegrounded('non-existent');
      assert.ok(true); // If we get here, it didn't throw
    });
  });

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

  describe('Session timeout', () => {
    it('should timeout inactive session', { timeout: 3000 }, async () => {

      // Create a fresh session manager for this test
      const timeoutManager = new AICLISessionManager({
        sessionTimeout: 500, // 500ms for testing
        minTimeoutCheckInterval: 50, // 50ms for testing
      });

      const result = await timeoutManager.createInteractiveSession(
        'timeout-session',
        'test',
        testDir
      );

      // Wait for timeout
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Session should be cleaned up
      const session = await timeoutManager.getSession(result.sessionId);
      assert.strictEqual(session, null);

      // Clean up
      await timeoutManager.shutdown();
    });

    it('should handle backgrounded session with longer timeout', { timeout: 5000 }, async () => {

      // Create a fresh session manager for this test
      const bgTimeoutManager = new AICLISessionManager({
        sessionTimeout: 500, // 500ms for testing
        backgroundedSessionTimeout: 1500, // 1.5 seconds for testing
        minTimeoutCheckInterval: 50, // 50ms for testing
      });

      const result = await bgTimeoutManager.createInteractiveSession(
        'bg-timeout-session',
        'test',
        testDir
      );

      // Mark as backgrounded
      await bgTimeoutManager.markSessionBackgrounded(result.sessionId);

      // Wait for regular timeout (should still exist due to longer backgrounded timeout)
      await new Promise((resolve) => setTimeout(resolve, 800));

      let session = await bgTimeoutManager.getSession(result.sessionId);
      assert.ok(session); // Should still exist

      // Wait for backgrounded timeout
      await new Promise((resolve) => setTimeout(resolve, 1000));

      session = await bgTimeoutManager.getSession(result.sessionId);
      assert.strictEqual(session, null); // Should be cleaned up

      // Clean up
      await bgTimeoutManager.shutdown();
    });
  });

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

    it('should cleanup old sessions', async () => {
      const cleaned = await sessionManager.cleanupOldSessions(0); // Clean all
      assert.ok(Array.isArray(cleaned));
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

      const session = await sessionManager.getSession(result.sessionId);
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
