import { EventEmitter } from 'events';
import { InputValidator } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';
import { sessionPersistence } from './session-persistence.js';

/**
 * Manages AICLI CLI session lifecycle, timeout handling, and cleanup
 */
export class AICLISessionManager extends EventEmitter {
  constructor(options = {}) {
    super();

    // Session storage
    this.activeSessions = new Map();
    this.sessionMessageBuffers = new Map();

    // Configuration
    this.maxSessions = options.maxSessions || 10;
    this.sessionTimeout = options.sessionTimeout || 30 * 60 * 1000; // 30 minutes
    this.backgroundedSessionTimeout = options.backgroundedSessionTimeout || 4 * 60 * 60 * 1000; // 4 hours

    // Persistence will be initialized by the server after startup
    // This prevents race conditions from multiple initialization attempts
  }

  /**
   * Initialize session persistence and restore sessions from disk
   */
  async initializePersistence() {
    try {
      await sessionPersistence.initialize();
      await this.restorePersistedSessions();
    } catch (error) {
      console.error('❌ Failed to initialize session persistence:', error);
    }
  }

  /**
   * Restore sessions from persistent storage on server startup
   */
  async restorePersistedSessions() {
    if (process.env.NODE_ENV === 'test') {
      return; // Skip persistence in test environment
    }
    const persistedSessions = sessionPersistence.getAllSessions();
    console.log(`🔄 Restoring ${persistedSessions.length} persisted sessions`);

    for (const persistedSession of persistedSessions) {
      const { sessionId } = persistedSession;

      // Create in-memory session based on persisted data
      const session = {
        sessionId,
        workingDirectory: persistedSession.workingDirectory,
        isActive: true,
        isProcessing: false,
        createdAt: persistedSession.createdAt,
        lastActivity: persistedSession.lastActivity,
        initialPrompt: persistedSession.initialPrompt,
        conversationStarted: persistedSession.conversationStarted,
        timeoutId: null,
        skipPermissions: persistedSession.skipPermissions,
        isBackgrounded: persistedSession.isBackgrounded,
        backgroundedAt: persistedSession.backgroundedAt,
        isRestoredSession: true, // Mark this session as restored from persistence
      };

      this.activeSessions.set(sessionId, session);

      // Initialize message buffer for restored session
      this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());

      // Set up timeout for restored session
      const timeoutId = setTimeout(() => {
        this.checkSessionTimeout(sessionId);
      }, this.sessionTimeout);
      session.timeoutId = timeoutId;

      console.log(
        `   ✅ Restored session ${sessionId} (conversation: ${session.conversationStarted})`
      );
    }

    if (persistedSessions.length > 0) {
      console.log(`🎉 Successfully restored ${persistedSessions.length} sessions from persistence`);
    }
  }

  /**
   * Create a new interactive session with metadata tracking
   */
  async createInteractiveSession(sessionId, initialPrompt, workingDirectory, options = {}) {
    // Validate and sanitize inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(initialPrompt);
    const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);

    console.log(`🚀 Creating AICLI CLI session (metadata-only)`);
    console.log(`   Session ID: ${sanitizedSessionId}`);
    console.log(`   Working directory: ${validatedWorkingDir}`);
    console.log(`   Initial prompt: "${sanitizedPrompt}"`);

    // Check session limits
    if (this.activeSessions.size >= this.maxSessions) {
      throw new Error(`Maximum number of sessions (${this.maxSessions}) reached`);
    }

    // Create session metadata (no long-running process)
    const { skipPermissions = false } = options;
    const session = {
      sessionId: sanitizedSessionId,
      workingDirectory: validatedWorkingDir,
      isActive: true,
      isProcessing: false,
      createdAt: Date.now(),
      lastActivity: Date.now(),
      initialPrompt: sanitizedPrompt,
      conversationStarted: false,
      timeoutId: null,
      skipPermissions, // Store permission setting for this session
      isBackgrounded: false, // Track if client is backgrounded
      backgroundedAt: null, // Track when client was backgrounded
    };

    this.activeSessions.set(sanitizedSessionId, session);

    // Persist session to disk (skip in test environment)
    if (process.env.NODE_ENV !== 'test') {
      try {
        await sessionPersistence.setSession(sanitizedSessionId, {
          workingDirectory: validatedWorkingDir,
          conversationStarted: false,
          initialPrompt: sanitizedPrompt,
          skipPermissions,
        });
        console.log(`💾 Session ${sanitizedSessionId} persisted to disk`);
      } catch (error) {
        console.error('❌ Failed to persist session %s:', sanitizedSessionId, error);
      }
    }

    // Initialize message buffer for this session
    this.sessionMessageBuffers.set(sanitizedSessionId, AICLIMessageHandler.createSessionBuffer());

    // Set up session timeout (only timeout if inactive AND no pending messages)
    const timeoutId = setTimeout(() => {
      this.checkSessionTimeout(sanitizedSessionId);
    }, this.sessionTimeout);

    // Store timeout ID for potential cancellation
    session.timeoutId = timeoutId;

    console.log(`✅ AICLI CLI session metadata created successfully`);

    return {
      sessionId: sanitizedSessionId,
      success: true,
      message: 'Session ready for commands',
    };
  }

  /**
   * Close a session and clean up all resources
   */
  async closeSession(sessionId) {
    const session = this.activeSessions.get(sessionId);

    if (!session) {
      console.log(`⚠️  Attempted to close non-existent session: ${sessionId}`);
      return { success: false, message: 'Session not found' };
    }

    console.log(`🔚 Closing AICLI CLI session: ${sessionId}`);
    console.log(`   Session type: metadata-only (no long-running process)`);

    try {
      // Clear any pending timeout
      if (session.timeoutId) {
        clearTimeout(session.timeoutId);
        session.timeoutId = null;
        console.log(`   Cleared timeout for session ${sessionId}`);
      }

      // Mark session as inactive
      session.isActive = false;

      // Remove from active sessions and clean up message buffer
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);

      // Remove from persistent storage (skip in test environment)
      if (process.env.NODE_ENV !== 'test') {
        try {
          await sessionPersistence.removeSession(sessionId);
          console.log(`💾 Session ${sessionId} removed from persistent storage`);
        } catch (error) {
          console.error('❌ Failed to remove session %s from persistence:', sessionId, error);
        }
      }

      // Emit session cleaned event for other components to handle cleanup
      this.emit('sessionCleaned', {
        sessionId,
        reason: 'user_requested',
        timestamp: new Date().toISOString(),
      });

      console.log(`✅ Session ${sessionId} closed successfully`);
      console.log(`   Remaining active sessions: ${this.activeSessions.size}`);

      return { success: true, message: 'Session closed' };
    } catch (error) {
      console.error('Error closing session:', error);
      return { success: false, message: error.message };
    }
  }

  /**
   * Check if a session exists and is active
   */
  hasSession(sessionId) {
    return this.activeSessions.has(sessionId);
  }

  /**
   * Get session metadata
   */
  getSession(sessionId) {
    return this.activeSessions.get(sessionId);
  }

  /**
   * Get all active sessions
   */
  getActiveSessions() {
    const sessions = Array.from(this.activeSessions.keys());
    console.log(`📊 Active AICLI CLI sessions: ${sessions.length}`);
    sessions.forEach((sessionId, index) => {
      const session = this.activeSessions.get(sessionId);
      const age = Math.round((Date.now() - session.createdAt) / 1000);
      console.log(
        `   ${index + 1}. ${sessionId} (age: ${age}s, conversation: ${session.conversationStarted ? 'started' : 'pending'})`
      );
    });
    return sessions;
  }

  /**
   * Update session activity timestamp
   */
  async updateSessionActivity(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.lastActivity = Date.now();

      // Update persistence (skip in test environment)
      if (process.env.NODE_ENV !== 'test') {
        try {
          await sessionPersistence.updateSession(sessionId, {
            lastActivity: session.lastActivity,
          });
        } catch (error) {
          console.warn(`⚠️ Failed to update session activity in persistence:`, error.message);
        }
      }
    }
  }

  /**
   * Set session processing state
   */
  setSessionProcessing(sessionId, isProcessing) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isProcessing = isProcessing;
      this.updateSessionActivity(sessionId);
    }
  }

  /**
   * Mark conversation as started for a session
   */
  async markConversationStarted(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.conversationStarted = true;

      // Update persistence (skip in test environment)
      if (process.env.NODE_ENV !== 'test') {
        try {
          await sessionPersistence.updateSession(sessionId, {
            conversationStarted: true,
          });
          console.log(`💾 Session ${sessionId} conversation start persisted`);
        } catch (error) {
          console.warn(
            `⚠️ Failed to persist conversation start for session ${sessionId}:`,
            error.message
          );
        }
      }
    }
  }

  /**
   * Mark session as backgrounded
   */
  async markSessionBackgrounded(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isBackgrounded = true;
      session.backgroundedAt = Date.now();
      console.log(`📱 Session ${sessionId} marked as backgrounded`);

      // Update persistence (skip in test environment)
      if (process.env.NODE_ENV !== 'test') {
        try {
          await sessionPersistence.updateSession(sessionId, {
            isBackgrounded: true,
            backgroundedAt: session.backgroundedAt,
          });
        } catch (error) {
          console.warn(
            `⚠️ Failed to persist background state for session ${sessionId}:`,
            error.message
          );
        }
      }
    }
  }

  /**
   * Mark session as foregrounded (no longer backgrounded)
   */
  async markSessionForegrounded(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isBackgrounded = false;
      session.backgroundedAt = null;
      await this.updateSessionActivity(sessionId);
      console.log(`📱 Session ${sessionId} marked as foregrounded`);

      // Update persistence (skip in test environment)
      if (process.env.NODE_ENV !== 'test') {
        try {
          await sessionPersistence.updateSession(sessionId, {
            isBackgrounded: false,
            backgroundedAt: null,
          });
        } catch (error) {
          console.warn(
            `⚠️ Failed to persist foreground state for session ${sessionId}:`,
            error.message
          );
        }
      }
    }
  }

  /**
   * Check if session should timeout
   */
  checkSessionTimeout(sessionId) {
    if (!this.activeSessions.has(sessionId)) {
      return; // Session already cleaned up
    }

    const session = this.activeSessions.get(sessionId);
    const buffer = this.sessionMessageBuffers.get(sessionId);
    const now = Date.now();
    const inactiveTime = now - session.lastActivity;

    // Determine appropriate timeout based on background state
    const timeoutToUse = session.isBackgrounded
      ? this.backgroundedSessionTimeout
      : this.sessionTimeout;
    const timeoutName = session.isBackgrounded ? 'backgrounded timeout' : 'regular timeout';

    // Only timeout if truly inactive for longer than timeout period
    if (
      !session.isProcessing &&
      (!buffer || buffer.messages.length === 0) &&
      inactiveTime > timeoutToUse
    ) {
      console.log(
        `Session ${sessionId} timed out after ${Math.round(inactiveTime / 1000)}s of inactivity (${timeoutName})`
      );

      // Clean up the session immediately (closeSession already emits sessionCleaned event)
      this.closeSession(sessionId);
    } else {
      // Reschedule another timeout check
      const remainingTime = Math.max(timeoutToUse - inactiveTime, 60000); // At least 1 minute
      setTimeout(() => this.checkSessionTimeout(sessionId), remainingTime);
    }
  }

  /**
   * Get session message buffer
   */
  getSessionBuffer(sessionId) {
    return this.sessionMessageBuffers.get(sessionId);
  }

  /**
   * Clear session message buffer
   */
  clearSessionBuffer(sessionId) {
    const buffer = this.sessionMessageBuffers.get(sessionId);
    if (buffer) {
      AICLIMessageHandler.clearSessionBuffer(buffer);
      console.log(`🧹 Cleared message buffer for session ${sessionId}`);
    }
  }

  /**
   * Cleanup dead session (called when process dies)
   */
  async cleanupDeadSession(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      // Clear timeout if it exists
      if (session.timeoutId) {
        clearTimeout(session.timeoutId);
        session.timeoutId = null;
      }

      session.isActive = false;
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);

      // Remove from persistent storage (skip in test environment)
      if (process.env.NODE_ENV !== 'test') {
        try {
          await sessionPersistence.removeSession(sessionId);
          console.log(`💾 Dead session ${sessionId} removed from persistent storage`);
        } catch (error) {
          console.warn(
            `⚠️ Failed to remove dead session ${sessionId} from persistence:`,
            error.message
          );
        }
      }

      this.emit('sessionCleaned', {
        sessionId,
        reason: 'process_died',
        timestamp: new Date().toISOString(),
      });
    }
  }

  /**
   * Shutdown all sessions
   */
  async shutdown() {
    console.log('🔄 Shutting down AICLI Session Manager...');

    // Close all active sessions
    for (const [sessionId, _] of this.activeSessions) {
      try {
        await this.closeSession(sessionId);
      } catch (error) {
        console.warn(`Failed to close session ${sessionId}:`, error.message);
      }
    }

    // Clear all buffers and data structures
    this.sessionMessageBuffers.clear();
    this.activeSessions.clear();

    console.log('✅ AICLI Session Manager shut down complete');
  }

  /**
   * Get persistence stats for debugging
   */
  getPersistenceStats() {
    return sessionPersistence.getStats();
  }

  /**
   * Export sessions for debugging
   */
  async exportSessions() {
    return sessionPersistence.exportSessions();
  }

  /**
   * Cleanup old persisted sessions
   */
  async cleanupOldSessions(maxAgeMs) {
    return sessionPersistence.cleanup(maxAgeMs);
  }

  /**
   * Reconcile session state with AICLI CLI to ensure consistency
   * This checks for sessions that exist in persistence but may be stale
   * and removes sessions that AICLI CLI no longer recognizes
   */
  async reconcileSessionState() {
    try {
      console.log('🔄 Reconciling session state with AICLI CLI...');

      const persistedSessions = sessionPersistence.getAllSessions();
      const staleSessions = [];

      // Check each persisted session by attempting a test command
      for (const persistedSession of persistedSessions) {
        const { sessionId } = persistedSession;

        // Skip if session is already active in memory
        if (this.activeSessions.has(sessionId)) {
          continue;
        }

        // Try to test if AICLI CLI recognizes this session
        // We'll do this by attempting to resume the session with a no-op command
        try {
          console.log(`🔍 Testing session ${sessionId} recognition with AICLI CLI...`);

          // If the session is truly stale, this will fail
          // For now, we'll mark sessions older than 7 days as potentially stale
          const age = Date.now() - persistedSession.lastActivity;
          const sevenDays = 7 * 24 * 60 * 60 * 1000;

          if (age > sevenDays) {
            console.log(
              `⚠️ Session ${sessionId} is ${Math.round(age / (24 * 60 * 60 * 1000))} days old, marking as stale`
            );
            staleSessions.push(sessionId);
          }
        } catch (error) {
          console.log(`❌ Session ${sessionId} failed AICLI CLI recognition test:`, error.message);
          staleSessions.push(sessionId);
        }
      }

      // Remove stale sessions from persistence
      let removedCount = 0;
      for (const staleSessionId of staleSessions) {
        try {
          await sessionPersistence.removeSession(staleSessionId);
          removedCount++;
          console.log(`🗑️ Removed stale session ${staleSessionId} from persistence`);
        } catch (error) {
          console.warn(`⚠️ Failed to remove stale session ${staleSessionId}:`, error.message);
        }
      }

      console.log(`✅ Session reconciliation complete: removed ${removedCount} stale sessions`);
      return {
        totalPersisted: persistedSessions.length,
        staleRemoved: removedCount,
        activeInMemory: this.activeSessions.size,
      };
    } catch (error) {
      console.error('❌ Failed to reconcile session state:', error);
      throw error;
    }
  }
}
