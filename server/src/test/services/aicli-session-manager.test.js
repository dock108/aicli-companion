import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { AICLISessionManager } from '../../services/aicli-session-manager.js';

describe('AICLISessionManager', () => {
  let sessionManager;
  
  beforeEach(() => {
    sessionManager = new AICLISessionManager({
      maxSessions: 5,
      sessionTimeout: 10000, // 10 seconds for testing
    });
  });

  afterEach(() => {
    sessionManager.shutdown();
  });

  describe('constructor', () => {
    it('should initialize with default options', () => {
      const manager = new AICLISessionManager();
      assert.strictEqual(manager.maxSessions, 10);
      assert.strictEqual(manager.sessionTimeout, 30 * 60 * 1000);
      assert.ok(manager.activeSessions instanceof Map);
      assert.ok(manager.sessionMessageBuffers instanceof Map);
    });

    it('should initialize with custom options', () => {
      const manager = new AICLISessionManager({
        maxSessions: 3,
        sessionTimeout: 5000,
      });
      assert.strictEqual(manager.maxSessions, 3);
      assert.strictEqual(manager.sessionTimeout, 5000);
    });
  });

  describe('createInteractiveSession', () => {
    it('should create a new session successfully', async () => {
      const result = await sessionManager.createInteractiveSession(
        'test-session',
        'Hello world',
        '/tmp'
      );

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.sessionId, 'test-session');
      assert.ok(result.message);
      assert.ok(sessionManager.hasSession('test-session'));
    });

    it('should reject session creation when max sessions reached', async () => {
      // Create max sessions
      for (let i = 0; i < 5; i++) {
        await sessionManager.createInteractiveSession(`session-${i}`, 'test', '/tmp');
      }

      // Try to create one more
      await assert.rejects(
        sessionManager.createInteractiveSession('overflow-session', 'test', '/tmp'),
        /Maximum number of sessions/
      );
    });

    it('should sanitize session ID and prompt', async () => {
      const result = await sessionManager.createInteractiveSession(
        'test-session!@#',
        'Hello\x00world',
        '/tmp'
      );

      assert.strictEqual(result.success, true);
      // Session ID should be sanitized
      assert.match(result.sessionId, /^[a-zA-Z0-9_-]+$/);
    });

    it('should reject invalid working directory', async () => {
      await assert.rejects(
        sessionManager.createInteractiveSession('test', 'hello', '/nonexistent/directory'),
        /Invalid working directory/
      );
    });
  });

  describe('session lifecycle', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'test', '/tmp');
    });

    it('should check if session exists', () => {
      assert.strictEqual(sessionManager.hasSession('test-session'), true);
      assert.strictEqual(sessionManager.hasSession('nonexistent'), false);
    });

    it('should get session metadata', () => {
      const session = sessionManager.getSession('test-session');
      assert.ok(session);
      assert.strictEqual(session.sessionId, 'test-session');
      assert.strictEqual(session.isActive, true);
      assert.strictEqual(session.conversationStarted, false);
      assert.ok(session.createdAt);
      assert.ok(session.lastActivity);
    });

    it('should update session activity', () => {
      const session = sessionManager.getSession('test-session');
      const originalActivity = session.lastActivity;
      
      // Wait a bit then update activity
      setTimeout(() => {
        sessionManager.updateSessionActivity('test-session');
        const updatedSession = sessionManager.getSession('test-session');
        assert.ok(updatedSession.lastActivity > originalActivity);
      }, 10);
    });

    it('should set session processing state', () => {
      sessionManager.setSessionProcessing('test-session', true);
      const session = sessionManager.getSession('test-session');
      assert.strictEqual(session.isProcessing, true);

      sessionManager.setSessionProcessing('test-session', false);
      assert.strictEqual(session.isProcessing, false);
    });

    it('should mark conversation as started', () => {
      sessionManager.markConversationStarted('test-session');
      const session = sessionManager.getSession('test-session');
      assert.strictEqual(session.conversationStarted, true);
    });

    it('should close session successfully', async () => {
      const result = await sessionManager.closeSession('test-session');
      assert.strictEqual(result.success, true);
      assert.strictEqual(sessionManager.hasSession('test-session'), false);
    });

    it('should handle closing non-existent session', async () => {
      const result = await sessionManager.closeSession('nonexistent');
      assert.strictEqual(result.success, false);
      assert.match(result.message, /not found/);
    });
  });

  describe('session buffers', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('test-session', 'test', '/tmp');
    });

    it('should create session buffer on session creation', () => {
      const buffer = sessionManager.getSessionBuffer('test-session');
      assert.ok(buffer);
      assert.ok(Array.isArray(buffer.messages));
      assert.strictEqual(buffer.messages.length, 0);
    });

    it('should clear session buffer', () => {
      const buffer = sessionManager.getSessionBuffer('test-session');
      buffer.messages.push({ type: 'test', content: 'hello' });
      
      sessionManager.clearSessionBuffer('test-session');
      assert.strictEqual(buffer.messages.length, 0);
    });

    it('should return null for non-existent session buffer', () => {
      const buffer = sessionManager.getSessionBuffer('nonexistent');
      assert.strictEqual(buffer, undefined);
    });
  });

  describe('session timeout', () => {
    it('should timeout inactive sessions', (done) => {
      // Create a session manager with very short timeout
      const shortTimeoutManager = new AICLISessionManager({
        sessionTimeout: 50, // 50ms
      });

      shortTimeoutManager.createInteractiveSession('timeout-session', 'test', '/tmp')
        .then(() => {
          // Session should exist initially
          assert.ok(shortTimeoutManager.hasSession('timeout-session'));

          // Wait for timeout
          setTimeout(() => {
            // Session should be removed after timeout
            assert.strictEqual(shortTimeoutManager.hasSession('timeout-session'), false);
            shortTimeoutManager.shutdown();
            done();
          }, 100);
        })
        .catch(done);
    });

    it('should not timeout active sessions', (done) => {
      const shortTimeoutManager = new AICLISessionManager({
        sessionTimeout: 50,
      });

      shortTimeoutManager.createInteractiveSession('active-session', 'test', '/tmp')
        .then(() => {
          // Mark session as processing
          shortTimeoutManager.setSessionProcessing('active-session', true);

          // Wait beyond timeout period
          setTimeout(() => {
            // Session should still exist because it's processing
            assert.ok(shortTimeoutManager.hasSession('active-session'));
            shortTimeoutManager.shutdown();
            done();
          }, 100);
        })
        .catch(done);
    });

    it('should not timeout sessions with pending messages', (done) => {
      const shortTimeoutManager = new AICLISessionManager({
        sessionTimeout: 50,
      });

      shortTimeoutManager.createInteractiveSession('pending-session', 'test', '/tmp')
        .then(() => {
          // Add a message to the buffer
          const buffer = shortTimeoutManager.getSessionBuffer('pending-session');
          buffer.messages.push({ type: 'test', content: 'pending' });

          // Wait beyond timeout period
          setTimeout(() => {
            // Session should still exist because it has pending messages
            assert.ok(shortTimeoutManager.hasSession('pending-session'));
            shortTimeoutManager.shutdown();
            done();
          }, 100);
        })
        .catch(done);
    });
  });

  describe('getActiveSessions', () => {
    it('should return empty array when no sessions', () => {
      const sessions = sessionManager.getActiveSessions();
      assert.ok(Array.isArray(sessions));
      assert.strictEqual(sessions.length, 0);
    });

    it('should return array of session IDs', async () => {
      await sessionManager.createInteractiveSession('session-1', 'test', '/tmp');
      await sessionManager.createInteractiveSession('session-2', 'test', '/tmp');

      const sessions = sessionManager.getActiveSessions();
      assert.strictEqual(sessions.length, 2);
      assert.ok(sessions.includes('session-1'));
      assert.ok(sessions.includes('session-2'));
    });
  });

  describe('cleanupDeadSession', () => {
    beforeEach(async () => {
      await sessionManager.createInteractiveSession('dead-session', 'test', '/tmp');
    });

    it('should clean up dead session', () => {
      // Verify session exists
      assert.ok(sessionManager.hasSession('dead-session'));

      // Clean up the session
      sessionManager.cleanupDeadSession('dead-session');

      // Verify session is removed
      assert.strictEqual(sessionManager.hasSession('dead-session'), false);
    });

    it('should emit sessionCleaned event', (done) => {
      sessionManager.once('sessionCleaned', (event) => {
        assert.strictEqual(event.sessionId, 'dead-session');
        assert.strictEqual(event.reason, 'process_died');
        assert.ok(event.timestamp);
        done();
      });

      sessionManager.cleanupDeadSession('dead-session');
    });

    it('should handle cleaning non-existent session gracefully', () => {
      assert.doesNotThrow(() => {
        sessionManager.cleanupDeadSession('nonexistent');
      });
    });
  });

  describe('shutdown', () => {
    it('should close all sessions on shutdown', async () => {
      await sessionManager.createInteractiveSession('session-1', 'test', '/tmp');
      await sessionManager.createInteractiveSession('session-2', 'test', '/tmp');

      assert.strictEqual(sessionManager.getActiveSessions().length, 2);

      sessionManager.shutdown();

      assert.strictEqual(sessionManager.getActiveSessions().length, 0);
    });

    it('should clear all data structures', async () => {
      await sessionManager.createInteractiveSession('test-session', 'test', '/tmp');
      
      sessionManager.shutdown();

      assert.strictEqual(sessionManager.activeSessions.size, 0);
      assert.strictEqual(sessionManager.sessionMessageBuffers.size, 0);
    });
  });

  describe('event emission', () => {
    it('should emit sessionCleaned event on session close', (done) => {
      sessionManager.createInteractiveSession('event-session', 'test', '/tmp')
        .then(() => {
          sessionManager.once('sessionCleaned', (event) => {
            assert.strictEqual(event.sessionId, 'event-session');
            assert.strictEqual(event.reason, 'user_requested');
            assert.ok(event.timestamp);
            done();
          });

          return sessionManager.closeSession('event-session');
        })
        .catch(done);
    });
  });
});